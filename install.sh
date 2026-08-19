#!/bin/bash

# Install the writing-streak widget: CLI to ~/.local/bin, systemd units to
# ~/.config/systemd/user, plugin to ~/.config/omarchy/plugins. Re-run after
# any edit; the shell hot-reloads plugin files on save, but a restart is
# forced at the end anyway (rescan alone doesn't reliably swap replaced QML).
#
# Idempotent: bar entry and policy config are only created when missing.
# NEVER touches the event log (~/.local/state/omarchy/writing-streak/) —
# it is the practice's measurement record, not a config file.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ID="$(id -un).writing-streak"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
USER_BIN="$HOME/.local/bin"
USER_UNITS="$HOME/.config/systemd/user"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
CONFIG="$HOME/.config/omarchy/writing-streak.json"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/writing-streak"

# --- CLI ---------------------------------------------------------------------
mkdir -p "$USER_BIN"
install -Dm755 "$REPO_DIR/bin/omarchy-writing-streak" "$USER_BIN/omarchy-writing-streak"

# --- systemd -----------------------------------------------------------------
mkdir -p "$USER_UNITS"
install -Dm644 "$REPO_DIR/systemd/omarchy-writing-streak.service" "$USER_UNITS/"
install -Dm644 "$REPO_DIR/systemd/omarchy-writing-streak.timer" "$USER_UNITS/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-writing-streak.timer

# --- plugin ------------------------------------------------------------------
mkdir -p "$PLUGIN_DEST"
rm -rf "${PLUGIN_DEST:?}"/*
cp "$REPO_DIR/manifest.json" "$REPO_DIR/Panel.qml" "$PLUGIN_DEST/"

# --- bar entry (only when missing) -------------------------------------------
if ! grep -q "\"$PLUGIN_ID\"" "$SHELL_JSON" 2>/dev/null; then
  cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
  tmp=$(mktemp)
  # Center section, after the weather widget when present, else appended.
  jq --arg id "$PLUGIN_ID" '
    .bar.layout.center |= (if any(.[]; .id == $id) then .
      elif any(.[]; .id == "omarchy.weather") then
        (reduce .[] as $e ([]; . + (if $e.id == "omarchy.weather" then [$e, {id: $id}] else [$e] end)))
      else . + [{id: $id}] end)
  ' "$SHELL_JSON" > "$tmp"
  mv "$tmp" "$SHELL_JSON"
  echo "bar entry added: center/$PLUGIN_ID (shell.json backed up)"
fi

# --- policy config default (only when missing; never overwrite a step-down) --
if [[ ! -s $CONFIG ]]; then
  mkdir -p "$(dirname "$CONFIG")"
  cat > "$CONFIG" <<'EOF'
{
  "policy": "every-2h",
  "pingHours": [6, 8, 10, 12, 14, 16],
  "windowStart": 6,
  "windowEnd": 17,
  "title": "Free writing",
  "body": "No session logged today yet.",
  "glyph": "✒"
}
EOF
  echo "config created: $CONFIG (every-2h — step down with set-policy bounded <hours>)"
fi

# --- reload ------------------------------------------------------------------
omarchy restart shell

if [[ ! -s $STATE_HOME/events.jsonl ]]; then
  echo "Note: event log is empty. Backfill pre-widget days with:"
  echo "  omarchy-writing-streak seed"
fi
echo "Installed $PLUGIN_ID (timer active: $(systemctl --user is-active omarchy-writing-streak.timer))."
