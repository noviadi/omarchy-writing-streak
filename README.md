# omarchy-writing-streak

An [Omarchy](https://omarchy.org) shell widget for a daily pen-and-paper practice:
an always-visible run token, a month grid, one-click day completion, and an
hourly reminder policy. Built for a free-writing practice; usable for any
"did I do the thing today?" habit.

Design philosophy, carried through every pixel and byte: **state as data,
never verdict.** The number 0 is never rendered. A missed day reads as
information ("no session logged", "day 1 of a new run"), never as accusation.
No red, no ✗, no escalating anything.

| Bar token | Meaning |
|---|---|
| `✒ 4` | today done, current run 4 days |
| `✒ 3°` | today still open, run of 3 alive until midnight |
| `✒ ↻1` | yesterday missed — today is day 1 of a new run |

Left-click opens the panel (month grid, current/longest run, policy footer,
mark/undo). Right-click toggles today. The widget is a **viewer only** — all
state and policy live in the CLI.

## Architecture: three dumb parts, one smart file

```
systemd user timer                     bin/omarchy-writing-streak
OnCalendar=*-*-* 06..17:00:00   ───▶   check | mark | undo | toggle | status
Persistent=true                                 │ appends events
        │                                       ▼
        └── fires hourly, policy filters   ~/.local/state/omarchy/
                                             writing-streak/events.jsonl
                                                       ▲ (read + watch)
                                    plugin (manifest.json + Panel.qml)
```

The **append-only event log is the only truth.** Every derived number —
streak, longest run, grid, reminder-conversion metrics — is recomputed from
the log on demand. `seed`/`completed`/`undone` decide a day's state (last one
per date wins); `reminder` events record pings without changing day state.

Why not a QML timer: the reminder must survive shell crashes, sleep, and
powered-off machines (`Persistent=true` fires a missed run at next boot —
the "long weekend broke my routine" failure mode this exists to prevent).
The timer is deliberately dumb; the *policy* lives in config, so switching
reminder cadence never touches systemd.

## Install

Requires Omarchy and `jq`.

```bash
./install.sh
```

Installs the CLI to `~/.local/bin`, the systemd units to
`~/.config/systemd/user/` (and enables the timer), the plugin to
`~/.config/omarchy/plugins/<user>.writing-streak/`, and — only if missing —
the bar entry (center section, after the weather widget) and the config
default at `~/.config/omarchy/writing-streak.json`. Re-run after any edit;
never touches your event log.

## Usage

```bash
omarchy-writing-streak mark        # today's session happened (idempotent)
omarchy-writing-streak undo        # un-mark today (today only; for accidents)
omarchy-writing-streak toggle      # mark if open, undo if done
omarchy-writing-streak status      # JSON state blob (what the bar renders)
omarchy-writing-streak metrics     # reminder→session conversion + time-to-comply
omarchy-writing-streak set-policy <every-2h|bounded|once> [hours...]
omarchy-writing-streak seed <YYYY-MM-DD> [YYYY-MM-DD …]   # one-shot backfill
omarchy-writing-streak self-test   # sandboxed behavior tests
```

Also: `omarchy-shell -q noviadi.writing-streak toggleMark` (IPC), and the
panel's mark/undo button.

### Reminder policy lifecycle

The timer fires hourly 06:00–17:00; the config decides which fires ping:
`every-2h` (06 08 10 12 14 16), `bounded` (explicit hours), or `once`.
Outside-window fires (boot catch-up) ping only if today had none; pings stop
the moment the day is marked; duplicate fires within 55 min are absorbed.

Week 1 runs `every-2h` as instrumentation — the log records time-to-comply,
which picks the permanent `bounded` hours from data instead of guesswork:

```bash
omarchy-writing-streak metrics                  # read timeToComplyByHour
omarchy-writing-streak set-policy bounded 8 13 16   # hours from the data
```

## Data

`~/.local/state/omarchy/writing-streak/events.jsonl` — one JSON object per
line: `{"type":"completed","date":"2026-08-21","ts":1755747600}`. It doubles
as the measurement record for the practice (completion coverage,
reminder→session conversion). Deleting the widget does not delete the data;
uninstall instructions keep it.

## Uninstall

```bash
systemctl --user disable --now omarchy-writing-streak.timer
rm ~/.config/systemd/user/omarchy-writing-streak.{service,timer} && systemctl --user daemon-reload
rm -rf ~/.config/omarchy/plugins/$(id -un).writing-streak
# remove the $(id -un).writing-streak entry from ~/.config/omarchy/shell.json
omarchy restart shell
rm -f ~/.local/bin/omarchy-writing-streak ~/.config/omarchy/writing-streak.json
# keep ~/.local/state/omarchy/writing-streak/ — it is the measurement record
```

## Context and status

Built for a specific practice with falsifiable success criteria (reminder→
session conversion, same-day miss visibility, zero widget-fiddling sessions).
The full decision record — principles, rejected alternatives, reminder-policy
lifecycle, measurement contract — is compiled in
[`docs/DESIGN.md`](docs/DESIGN.md).

**Personal config, published as reference.** The reminder copy and window
encode one writer's morning practice; fork and tune.

Deferred (decided against for v1, revisit at the week-1 review): surfacing
the writing ping in the stock reminders surface (Super+Ctrl+Alt+R + bell
indicator). Trade-off analysis in [`docs/DESIGN.md`](docs/DESIGN.md#deferred-revisit-at-the-week-1-review).
