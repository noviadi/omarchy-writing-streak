#!/bin/bash
# tests/run.sh — sandboxed test suite for omarchy-writing-streak.
#
# Runs the repo's CLI against throwaway state. Never touches real state,
# config, or notifications. Exit 0 = pass; output is one line per assertion.
#
# Seams (the CLI's env overrides — this is ALL the mocking there is):
#   WRITING_STREAK_FAKE_NOW   time itself (reminder gating is time-dependent)
#   WRITING_STREAK_NOTIFY     a spy script recording notification calls
#   WRITING_STREAK_STATE_HOME / _CONFIG   throwaway dirs
# Deliberately NOT mocked: the event log (real files — jq parsing real bytes
# is part of what is tested) and the CLI as a subprocess (real exit codes).
#
# What this suite does NOT cover (see docs/TESTING.md): QML rendering, the
# systemd integration, notification delivery. Those get manual recipes.

set -uo pipefail   # NOT -e: a test suite counts failures, it doesn't die on one

CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/omarchy-writing-streak"
fails=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# notification spy: records every argument line, never sends anything
printf '#!/bin/sh\necho "$@" >> "%s/notify.log"\n' "$tmp" > "$tmp/spy"
chmod +x "$tmp/spy"

export WRITING_STREAK_STATE_HOME="$tmp" WRITING_STREAK_CONFIG="$tmp/config.json" \
       WRITING_STREAK_NOTIFY="$tmp/spy" WRITING_STREAK_FAKE_NOW="2026-08-19 09:00"

t() { # <expected> <actual> <description>
  if [[ $1 == "$2" ]]; then echo "ok - $3"; else echo "FAIL - $3: expected [$1] got [$2]"; fails=$((fails+1)); fi
}
t_prefix() { # <prefix> <actual> <description> — for messages embedding varying paths
  if [[ $2 == "$1"* ]]; then echo "ok - $3"; else echo "FAIL - $3: expected prefix [$1] got [$2]"; fails=$((fails+1)); fi
}
fails_with() { # <description> — runs "$@" expecting a nonzero exit
  if "$@" >/dev/null 2>&1; then echo "FAIL - $1: expected failure, got success"; fails=$((fails+1)); else echo "ok - $1"; fi
}
section() { echo; echo "== $1 =="; }

# ---------------------------------------------------------------- seed input
section "seed: dates as arguments, one-shot, semantically validated"

fails_with "seed without dates errors" "$CLI" seed
t "seeded: 2026-08-10 2026-08-11 2026-08-12 (complete)" \
  "$("$CLI" seed 2026-08-10 2026-08-11 2026-08-12 2>&1)" "seed accepts dates and reports them"
t "3" "$(wc -l < "$tmp/events.jsonl")" "one event per date"
t_prefix "refusing" "$("$CLI" seed 2026-08-10 2>&1 || true)" "seed refuses a non-empty log"
rm -f "$tmp/events.jsonl"
fails_with "seed rejects bad format (2026-8-1)" "$CLI" seed 2026-8-1
fails_with "seed rejects impossible month (2026-13-45)" "$CLI" seed 2026-13-45 2026-01-01
t "absent" "$([[ -e $tmp/events.jsonl ]] && echo present || echo absent)" "rejected seed writes nothing"
fails_with "seed rejects impossible day (2026-02-30)" "$CLI" seed 2026-02-30
t "seeded: 2026-08-10 (complete)" "$("$CLI" seed 2026-08-10 2>&1)" "seed usable right after a rejection"

# ------------------------------------------------------------------- fixture
section "state machine: gap, restart, best across gap"

rm -f "$tmp/events.jsonl"
for d in 2026-08-11 2026-08-12 2026-08-13 2026-08-17; do
  jq -cn --arg d "$d" --argjson ts "$(date -d "$d 12:00" +%s)" '{type:"seed",date:$d,ts:$ts}' >> "$tmp/events.jsonl"
done
st=$("$CLI" status)
t "restart" "$(jq -r .state <<<"$st")" "today open + yesterday missed = restart state"
t "3" "$(jq -r .best <<<"$st")" "longest run spans the gap (11-13)"
t "0" "$(jq -r .streak <<<"$st")" "streak 0 (token renders ↻1 — zero is never displayed)"

section "state machine: mark / undo / toggle"

"$CLI" mark >/dev/null
st=$("$CLI" status)
t "done" "$(jq -r .state <<<"$st")" "mark completes today"
t "1" "$(jq -r .streak <<<"$st")" "streak counts today"
"$CLI" mark >/dev/null
t "5" "$(wc -l < "$tmp/events.jsonl")" "mark is idempotent (no duplicate events)"
"$CLI" undo >/dev/null
t "restart" "$("$CLI" status | jq -r .state)" "undo returns to open-restart"
fails_with "undo without a mark errors" "$CLI" undo
"$CLI" toggle >/dev/null
t "done" "$("$CLI" status | jq -r .state)" "toggle from open marks done"

section "state machine: open with a live run"

jq -cn --arg d 2026-08-18 --argjson ts "$(date -d "2026-08-18 12:00" +%s)" '{type:"seed",date:$d,ts:$ts}' >> "$tmp/events.jsonl"
"$CLI" undo >/dev/null
st=$("$CLI" status)
t "open" "$(jq -r .state <<<"$st")" "yesterday done + today unmarked = open"
t "2" "$(jq -r .streak <<<"$st")" "open streak is the run ending yesterday"

# ------------------------------------------------------------ reminder gating
section "reminder policy: gating, dedup, catch-up (notifications are spied)"

rm -f "$tmp/notify.log"
"$CLI" check
t "absent" "$([[ -e $tmp/notify.log ]] && echo present || echo absent)" "09:00 is not a ping hour (every-2h) — silent"

export WRITING_STREAK_FAKE_NOW="2026-08-19 10:00"
"$CLI" check
t "1" "$(wc -l < "$tmp/notify.log")" "ping hour fires exactly one notification"
"$CLI" check
t "1" "$(wc -l < "$tmp/notify.log" 2>/dev/null || echo 0)" "dedup: no second ping within 55 min"
t "1" "$("$CLI" status | jq -r .remindersToday)" "reminder event recorded in the log"

"$CLI" mark >/dev/null
export WRITING_STREAK_FAKE_NOW="2026-08-19 12:00"
"$CLI" check
t "1" "$(wc -l < "$tmp/notify.log")" "completed day never pings"

jq -cn --arg d 2026-08-20 --argjson ts "$(date -d "2026-08-20 19:30" +%s)" '{type:"completed",date:$d,ts:$ts}' >> "$tmp/events.jsonl"
export WRITING_STREAK_FAKE_NOW="2026-08-21 19:30"
"$CLI" check
t "2" "$(wc -l < "$tmp/notify.log")" "outside-window fire with zero reminders = catch-up ping"
"$CLI" check
t "2" "$(wc -l < "$tmp/notify.log")" "catch-up pings once per day only"

# ------------------------------------------------------------------- metrics
section "metrics: M3 conversion and time-to-comply"

m=$("$CLI" metrics)
t "2" "$(jq -r '.totals.reminderDays' <<<"$m")" "reminder days counted"
t "1" "$(jq -r '.totals.convertedDays' <<<"$m")" "converted days counted"
t "50" "$(jq -r '.totals.conversion' <<<"$m")" "conversion percent"

# -------------------------------------------------------------------- policy
section "policy switching"

"$CLI" set-policy bounded 8 13 16 >/dev/null
t "bounded" "$(jq -r .policy "$tmp/config.json")" "policy written to config"
t "8 13 16" "$(jq -r '.pingHours | join(" ")' "$tmp/config.json")" "ping hours written"

# ---------------------------------------------------------------------- grid
section "grid shape (current month)"

st=$("$CLI" status)
t "31" "$(jq -r '.grid | length' <<<"$st")" "August 2026 has 31 grid cells"
t "6" "$(jq -r .firstWeekday <<<"$st")" "Aug 1 2026 is a Saturday (0=Sunday)"

# --------------------------------------------------------------------- total
echo
if (( fails == 0 )); then echo "PASS (all assertions)"; exit 0
else echo "FAIL ($fails assertion(s))"; exit 1; fi
