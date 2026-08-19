# Testing

What is testable, what is mocked, and what is deliberately outside the suite.
Reviewers: this file plus `tests/run.sh` *is* the expectation contract — every
assertion prints one `ok`/`FAIL` line with a plain-language description.

```bash
tests/run.sh        # from the repo root; exit 0 = pass
```

## The suite's boundary: the CLI contract

The suite pins the **CLI contract** — the JSON/exit-code surface that the QML
plugin, the systemd units, and the metrics review consume. Everything outside
that contract (rendering, scheduling, delivery) is verified manually, below.

## What is tested, and how

All logic tests run the real CLI as a subprocess against throwaway state.
Assertions cover: seed input validation (shape *and* semantics, incl. the
poison-path "writes nothing"), the day state machine (done/open/restart,
idempotent mark, today-only undo, toggle), streak and longest-run computation
across gaps, reminder policy gating (ping hours, dedup window, catch-up-once,
done-day silence), metrics (M3 conversion math), policy switching, and month
grid shape.

## What is mocked — and why these three, no more

The CLI's environment overrides are the only seams; they were designed in at
build time, not bolted on for tests:

| Seam | Mock | Why it must be mocked |
|---|---|---|
| `WRITING_STREAK_FAKE_NOW` | fixed clock | reminder gating is time-dependent; real-time tests would be slow, flaky, and unable to hit window edges |
| `WRITING_STREAK_NOTIFY` | spy script appending to a log | notifications are a side-effect boundary — assert *that* we called, never *how* the daemon renders |
| `WRITING_STREAK_STATE_HOME` / `_CONFIG` | throwaway dirs | isolation: a test run must never touch the practice's real event log |

## What is deliberately NOT mocked

- **The event log files.** Real files, real bytes. jq parsing of the actual
  file (including the tolerant skip of corrupt lines) is part of what is under
  test — mocking the filesystem would test a fiction.
- **The CLI process itself.** Real exit codes, real stderr; that is the
  contract the systemd unit and the plugin's `Process` calls depend on.

## What is NOT testable in this harness (manual recipes)

| Layer | Why out of suite | Manual check |
|---|---|---|
| `Panel.qml` rendering & panel | needs a live Quickshell session | left-click panel, month grid, token states |
| Bar integration (slot, hot-reload) | live shell | token appears center, right of weather; edits reload on save |
| QML→CLI wiring | live shell | `omarchy-shell -q noviadi.writing-streak toggleMark` round-trips; `status` JSON parses |
| systemd units | needs the user session | `systemctl --user list-timers omarchy-writing-streak.timer`; after reboot, `journalctl --user -u omarchy-writing-streak.service` shows the `Persistent=true` catch-up fire |
| Notification delivery | needs the shell's daemon | one forced `omarchy-notification-send -g ✒ …` at install time |
| Day rollover in the widget | QML 60 s timer vs real midnight | next morning: token flipped without any event append |

Regression history argues for this split rather than "test everything":
every shipped defect so far (P4: swallowed jq/bash argument bug; R4: seed
shape-only validation) lived in the CLI contract — exactly where the suite
aims. No defect has come from the QML layer, which is why it stays a viewer
with no logic of its own.
