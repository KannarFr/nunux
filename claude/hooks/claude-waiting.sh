#!/usr/bin/env bash
# Claude Code hook (Notification + Stop): when Claude wants attention, show ONE
# Sway notification (via swaync). Clicking it focuses the terminal window + the
# tmux pane Claude runs in. Behaviour:
#   - skipped when that window is already focused (no spam while you're looking),
#   - only ONE notification per tmux pane is kept alive (--replace-id),
#   - claude-dismiss.sh closes it on the next UserPromptSubmit, so it goes away
#     the moment you respond — by any means, not just by clicking it.
# Wired to the Notification and Stop hooks in claude/settings.json.

# --- read hook JSON from stdin (may be empty); one jq pass, line per field -----
# Newline-separated (not @tsv): with a tab IFS, read collapses a leading empty
# field, so an empty .message would swallow the event name into msg.
input="$(cat)"
{ read -r msg; read -r event; } < <(
  printf '%s' "$input" \
    | jq -r '.message // "", .hook_event_name // ""' 2>/dev/null
)
if [ -z "$msg" ]; then
  case "$event" in
    Stop) msg="Claude finished — waiting for your next message" ;;
    *)    msg="Claude is waiting for your input" ;;
  esac
fi

# --- which tmux pane is Claude in? --------------------------------------------
pane="${TMUX_PANE:-}"

# --- find the Sway window that hosts this pane's tmux client ------------------
# Walk from the tmux client's pid up the process tree; the first ancestor whose
# pid appears in get_tree is the terminal-emulator window (works for any
# terminal, not just one named binary). Fetch the tree once and reuse it.
con=""
if [ -n "$pane" ] && [ -n "$SWAYSOCK" ]; then
  client_pid="$(tmux display-message -p -t "$pane" '#{client_pid}' 2>/dev/null)"
  tree="$(swaymsg -t get_tree 2>/dev/null)"
  p="$client_pid"
  while [ -n "$p" ] && [ "$p" != "1" ]; do
    con="$(printf '%s' "$tree" | jq -r --argjson pid "$p" \
      'first(.. | objects | select(.pid? == $pid) | .id) // empty')"
    [ -n "$con" ] && break
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done

  # Already looking at this exact pane? Don't bother notifying. We skip only when
  # the host window is focused AND Claude's tmux pane is the active/visible one —
  # so a sibling pane in the same window (or a background window) still pings.
  if [ -n "$con" ]; then
    focused="$(printf '%s' "$tree" \
      | jq -r 'first(.. | objects | select(.focused? == true) | .id) // empty')"
    if [ "$focused" = "$con" ]; then
      active="$(tmux display-message -p -t "$pane" \
        '#{&&:#{window_active},#{pane_active}}' 2>/dev/null)"
      [ "$active" = "1" ] && exit 0
    fi
  fi
fi

# --- audible ping, same skip-when-focused logic as the notification -----------
# Random Henri voice line (edge-tts fr-FR-HenriNeural) from a per-event pool, so
# the repeated ping doesn't get samey. Stop draws from sounds/done/, everything
# else from sounds/wait/. Edit phrases + regenerate via ~/.claude/hooks/sounds/gen.sh.
case "$event" in
  Stop) snddir="$HOME/.claude/hooks/sounds/done" ;;
  *)    snddir="$HOME/.claude/hooks/sounds/wait" ;;
esac
snd="$(find "$snddir" -name '*.wav' 2>/dev/null | shuf -n1)"
[ -n "$snd" ] && paplay "$snd" >/dev/null 2>&1 &

# --- project dir for a useful title -------------------------------------------
dir="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"

# --- per-pane notification id, so we replace (not stack) and can dismiss later -
key="${TMUX_PANE:-default}"; key="${key//[^A-Za-z0-9]/_}"
state="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-${key}.id"
prev="$(cat "$state" 2>/dev/null)"

# --- fire the clickable notification, fully detached so the hook returns now ---
# The helper blocks until the notification closes (clicked, replaced, or closed
# by claude-dismiss.sh), so we run it in its own session and return immediately.
CLAUDE_CON="$con" CLAUDE_PANE="$pane" CLAUDE_MSG="$msg" CLAUDE_DIR="$dir" \
CLAUDE_PREV="$prev" CLAUDE_STATE="$state" \
  setsid -f "$HOME/.claude/hooks/claude-waiting-notify.sh" >/dev/null 2>&1

exit 0
