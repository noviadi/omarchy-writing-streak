# AGENTS.md — protocol for agents working on this plugin

A tiny Omarchy shell plugin with a strict shape. Read this before changing
anything. The decision record with rationale is [`docs/DESIGN.md`](docs/DESIGN.md);
the repo README carries the essentials.

## Non-negotiable guardrails

1. **The event log is the only truth.** `events.jsonl` is append-only, owned
   by the CLI. Never add streak math to QML — the plugin is a viewer that
   shells out to `status` and renders. Never edit the log by hand (except
   documented recovery).
2. **Data, never verdict.** The number 0 is never a display value; states are
   `done` (`✒ N`) / `open` (`✒ N°`) / `restart` (`✒ ↻1`). No red, no ✗, no
   guilt copy, no escalating alerts. If a change makes a miss feel like an
   accusation, it is wrong regardless of how good it looks.
3. **windowStart/windowEnd mirror the systemd timer span (06–17).** They
   distinguish in-window fires from boot-catch-up fires. `set-policy` must
   never rewrite them (bug P9 in the build log — it once did).
4. **The CLI's env overrides are the test harness:** `WRITING_STREAK_STATE_HOME`,
   `WRITING_STREAK_CONFIG`, `WRITING_STREAK_NOTIFY`, `WRITING_STREAK_FAKE_NOW`.
   Tests (`tests/run.sh`) must never touch real state or send real notifications.
   The full testability boundary — what's mocked, what's real, what's manual —
   is [`docs/TESTING.md`](docs/TESTING.md). New CLI behavior ships with a new
   assertion in the same commit.

## Workflow

```bash
tests/run.sh                          # before and after every change
./install.sh                           # deploy after edits (repo is source of truth)
```

Plugin QML under `~/.config/omarchy/plugins/` hot-reloads on save, but
`install.sh` copies then restarts the shell anyway — replaced QML is not
reliably swapped by rescan alone.

## Verifying a change live

```bash
omarchy-writing-streak status | jq '{state,streak,best}'
omarchy-shell -q noviadi.writing-streak toggleMark   # IPC round trip
systemctl --user list-timers omarchy-writing-streak.timer
journalctl --user --since "-2 min" | grep -i writing-streak   # reload lines, errors
```

Undo test side effects with `toggle` — never by editing the log.

## API references (read-only system sources)

- Shell UI components: `/usr/share/omarchy/shell/Ui/` (`Panel`, `KeyboardPanel`,
  `WidgetButton`, `Button`, `PanelKeyCatcher`), `Commons/Style.qml` (font
  tokens: caption/body/bodySmall/subtitle/title — there is no `mini`).
- Bar integration contract: a bar-widget root needs `open()/close()/opened`
  (`Bar.qml` discovers panels by shape).
- The omarchy skill (`~/.pi/agent/skills/omarchy/SKILL.md`) governs any work
  under `~/.config/`; never edit anything under `/usr/share/omarchy/`.

## Conventions

- Commits: imperative one-liners ("Add …", "Fix …"), one logical change each.
- Copy the omarchy-agents repo pattern (`~/Developments/code/omarchy-agents`)
  for anything repo-level (docs layout, install behavior).
- bash + jq only for the CLI; no new runtime dependencies.
