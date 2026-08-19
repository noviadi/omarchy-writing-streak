# Design Decisions

The decision record for this widget, compiled from its requirements, solution
design, and build log. Each decision carries its rationale; where an
alternative was rejected, the reason is kept — that is most of the design.

Origin: a daily pen-and-paper writing practice failed for five consecutive
days through *forgetting, not avoidance* — a long weekend broke the routine,
nothing in the environment represented the practice's existence, and the miss
went unnoticed for five days. The widget's purpose: **a reminder prevents the
miss; a visible streak makes any miss that still happens noticeable the same
day.**

## Principles (in priority order)

1. **The event log is the only truth.** Every derived number is recomputed
   from `events.jsonl` on demand. The widget is a viewer; the CLI is the only
   writer. Nothing caches authority.
2. **Data, never verdict.** State is presented as information ("no session
   logged"), never accusation ("you broke your streak"). A missed day ends a
   run; the interface then foregrounds the next opportunity, not the failure.
3. **The widget is scaffolding, not the practice.** The page is primary; the
   workspace is secondary; the widget is tertiary. If the widget starts
   consuming writing-adjacent time, it has failed (success criterion M4).
4. **Boring beats clever.** Known failure mode of the owner: abandoning
   committed practice for novel-feeling work. Automation here is deliberately
   minimal; anything cleverer must argue its way in.

## Architecture: three dumb parts, one smart file

```
systemd user timer                     CLI (bash + jq)
OnCalendar=*-*-* 06..17:00:00   ───▶   check | mark | undo | toggle | status
Persistent=true                                 │ appends events
        │                                       ▼
        └── fires hourly, policy filters   events.jsonl (append-only)
                                                       ▲ (read + watch)
                                    QML plugin (bar token + panel)
```

- **A1 — systemd calendar timer, not a QML timer.** The reminder must
  survive shell crashes, sleep, and powered-off machines. `Persistent=true`
  fires a missed run at next boot — the exact "long weekend" failure mode.
  A QML timer inside the shell process fails all three.
- **A2 — dumb timer, smart CLI.** The timer fires hourly 06:00–17:00 no
  matter what; *which fires ping* is policy in `~/.config/omarchy/`, read by
  the CLI at each fire. Switching reminder cadence is a config edit with no
  systemd interaction.
- **A3 — bash + jq only.** No runtime dependencies beyond `jq`; the whole
  state machine is inspectable and testable with shell commands.
- **A4 — viewer-only QML.** The plugin shells out to `status`, parses JSON,
  renders. No streak math in QML: it would be untestable and would invite
  fiddling. Refresh triggers: `FileView` watch on the event log (reacts to
  any append) + a 60 s timer (catches day rollover with no file write).

## Data model

Append-only, one JSON object per line:
`{"type":"completed","date":"YYYY-MM-DD","ts":<epoch-seconds>}`.

- **Deciding vs non-deciding events.** `seed`, `completed`, `undone` decide a
  day's state; **last deciding event per date wins**. `reminder` events never
  change day state — they are measurement records.
- **Epoch seconds, not ISO strings.** jq's `fromdateiso8601` demands
  Z-suffixed strings; epochs avoid the whole class of parsing bugs. Dates in
  `date` are local time (a morning practice makes the midnight boundary safe).
- **Undo is an event, today-only.** Undo exists for accidental marks, and
  accidents are same-day. Allowing retroactive edits would make the log
  negotiable and corrupt the measurement record.
- **No `suppress` events.** Days completed before any check simply have no
  reminder events; metrics denominators are "days with ≥1 reminder," which
  needs nothing else.
- **`seed` is one-shot** (refuses a non-empty log): backfilling pre-widget
  days must never run twice and race with live events.
- **Idempotent marking.** `mark` on a done day is a no-op — frictionless
  marking paths must not create duplicate events.

## Display (the anti-shaming contract, encoded)

The number 0 is never a display value. Exactly four states:

| State | Bar token | Panel line |
|---|---|---|
| Today complete | `✒ N` | "Today: done" |
| Today open, run alive (yesterday done) | `✒ N°` | "Today: open" |
| Today open, yesterday missed | `✒ ↻1` | "Today is day 1 of a new run" |
| Past day missed (grid) | — | dim/blank cell |

- **Grid and number, both.** The grid is truth (gaps cannot hide); the number
  is momentum. A miss renders as a faint outline — never ✗, never red, never
  any alert color.
- **The open-loop token is the miss-detector.** An unmarked *today* is not a
  miss yet, but `✒ 3°` sitting in the bar all day is the "the day is not over
  until your day is over" signal — visible without being sought.
- **Neutral notification copy, always.** The reminder is load-bearing, not
  the message. No restart-framed or guilt variants in notifications; restart
  framing lives in the bar/panel where it is data, not a poke.
- **Grid is the current month**, Monday-first, with anchor numbering (the 1st
  and every 7th day) — orientation without clutter.

## Completion semantics

- **Binary and binary only.** A 5-minute "dose-down" session counts the same
  as 20 minutes: lowering the bar on bad days protects the run, which is the
  point — and the widget cannot see duration anyway, which conveniently
  enforces the right semantics.
- **Transcription is invisible to the widget.** Completion means the
  pen-and-paper session happened. Detecting `drafts/sessions/*.md` as
  completion was **rejected**: transcription is optional and lags by design;
  it would measure the wrong thing.
- **Notification action buttons rejected.** A "mark complete" button on the
  ping would reward marking *before* writing, corrupting the data the system
  exists to keep honest.
- **Marking and reminding are decoupled.** A day completed at 22:00 (after
  the last ping) still counts. The widget demands nothing at completion time.

## Reminder policy

The timer fires hourly 06:00–17:00. Each fire, the CLI decides:

1. Day complete → silent, nothing logged.
2. Hour in `pingHours` → ping (unless one fired < 55 min ago — absorbs
   systemd catch-up stacking).
3. Hour inside the window but not a ping hour → silent (policy filter).
4. Hour *outside* the window (boot/wake catch-up fire) → ping only if today
  has had zero reminders. Missed morning pings reach the writer once, not
  as a burst.

**Lifecycle (phased, pre-agreed):** `every-2h` (06 08 10 12 14 16) for week
1 as instrumentation — the log records actual time-to-comply per day — then
`bounded` with hours chosen from `metrics` output at the week-1 review.
Maximum 6 pings on a bad day, ~1 on a good one; frequent enough to catch the
owner's "just after an intensive activity" window, sparse enough not to train
an ignore-reflex. Deciding the step-down rule *before* week 1 prevents the
nag from becoming permanent by inertia.

### Rejected alternatives

- **Riding `omarchy-reminder` units** (the stock reminders surface): its
  timers are transient (lost on reboot), fire a fixed command (no chaining,
  no "skip if day done", no fire-time logging → reminder-conversion metrics
  die), and `clear` is global. Using the display stack would require
  reimplementing the setter anyway.
- **Idle-aware deferral** ("ping only between activities"): would time pings
  better and is exactly the clever automation the owner keeps warning
  themselves about. Hourly checks are the dumb proxy.

### Deferred (revisit at the week-1 review)

Arming one *display-only* transient unit in the `omarchy-reminder-*` namespace
(while keeping this timer as trigger of record) so the writing ping appears in
the bell indicator and Super+Ctrl+Alt+R reminder list. Gains: one surface for
all time obligations. Costs: an undocumented naming/message-file contract with
stock tooling, ~60–80 lines of arm/cancel choreography, self-healing-only
resilience to `clear`. Viable shape, deliberately not taken during the
instrumentation week — one variable at a time.

## System invariants (learned the hard way)

- `windowStart`/`windowEnd` in the config **mirror the systemd timer span**;
  they exist only to distinguish in-window fires from catch-up fires. Deriving
  them from policy hours once shipped as a bug: pre-anchor hours became
  "catch-ups" and pinged.
- A jq file argument on the line *after* a closing quote is executed by bash
  as a command while jq silently reads empty stdin — plausible empty output,
  no error. Line-continuation discipline or `bash -x`.
- Tests must run through the CLI's env overrides
  (`WRITING_STREAK_STATE_HOME|CONFIG|NOTIFY|FAKE_NOW`) so they can never
  touch real state or send real notifications.

## Measurement contract

The widget is itself an experiment with falsifiable success criteria; the
event log is the instrument.

| # | Observable | How this system measures it |
|---|---|---|
| M1 | Miss noticed same day | open-loop token + grid by construction |
| M2 | Complete days per week ≥ 6 | completion coverage from the log |
| M3 | Reminder → session conversion | `metrics`: converted reminder-days ÷ reminder-days |
| M4 | Zero sessions lost to widget fiddling | by design (no fiddling surface); self-report |
| M5 | Restart latency ≤ 1 day after a miss | `✒ ↻1` framing; restart dates from the log |

**Review gates:** week 1 — step `every-2h` down to `bounded` hours chosen
from `timeToComplyByHour`; end of the 30-day commitment — if M1 and M2 hold,
keep the widget; if it changes nothing (or M4 fires), remove it and treat
that as signal about structural fixes, not about the owner.
