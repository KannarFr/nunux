#!/usr/bin/env bash
# Codex's root-level `notify` command. It is called with a JSON payload on
# stdin when a turn ends. Keep one persistent Sway notification per tmux pane,
# and make it focusable with a click or the shared $mod+g binding.
set -u

payload="$(cat)"
msg="$({ printf '%s' "$payload" | jq -r '."last-assistant-message" // empty' 2>/dev/null; } | tr '\n' ' ' | cut -c1-280)"
[ -n "$msg" ] || msg="Finished — waiting for your next message"

pane="${TMUX_PANE:-}"
con=""
if [ -n "$pane" ] && [ -n "${SWAYSOCK:-}" ]; then
  client_pid="$(tmux display-message -p -t "$pane" '#{client_pid}' 2>/dev/null)"
  tree="$(swaymsg -t get_tree 2>/dev/null)"
  p="$client_pid"
  while [ -n "$p" ] && [ "$p" != 1 ]; do
    con="$(printf '%s' "$tree" | jq -r --argjson pid "$p" \
      'first(.. | objects | select(.pid? == $pid) | .id) // empty')"
    [ -n "$con" ] && break
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done

  if [ -n "$con" ]; then
    focused="$(printf '%s' "$tree" | jq -r \
      'first(.. | objects | select(.focused? == true) | .id) // empty')"
    if [ "$focused" = "$con" ]; then
      active="$(tmux display-message -p -t "$pane" \
        '#{&&:#{window_active},#{pane_active}}' 2>/dev/null)"
      [ "$active" = 1 ] && exit 0
    fi
  fi
fi

# Match the Claude completion cue when the optional sound files are present.
sound="$(find "$HOME/.claude/hooks/sounds/done" -name '*.wav' 2>/dev/null | shuf -n1)"
[ -n "$sound" ] && paplay "$sound" >/dev/null 2>&1 &

dir="$(basename "$PWD")"
key="${pane:-default}"; key="${key//[^A-Za-z0-9]/_}"
state="${XDG_RUNTIME_DIR:-/tmp}/codex-notify-${key}.id"
prev=""; [ -f "$state" ] && read -r prev < "$state"

CODEX_CON="$con" CODEX_PANE="$pane" CODEX_MSG="$msg" CODEX_DIR="$dir" \
CODEX_PREV="$prev" CODEX_STATE="$state" \
  setsid -f "$HOME/.codex/hooks/codex-notify-action.sh" >/dev/null 2>&1
