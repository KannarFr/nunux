#!/usr/bin/env bash
# Helper for claude-waiting.sh, run detached (setsid). Shows ONE notification
# (replacing this pane's previous one), records its id so claude-dismiss.sh can
# close it, and — only if the notification is actually CLICKED — focuses the
# terminal window and selects the tmux pane.
# Inputs via env: CLAUDE_CON CLAUDE_PANE CLAUDE_MSG CLAUDE_DIR CLAUDE_PREV CLAUDE_STATE.
set -u

# Henri emblem shipped alongside this script in the repo.
icon="$(dirname "$(readlink -f "$0")")/henri.png"
[ -f "$icon" ] || icon=utilities-terminal

args=(
  --app-name=claude
  --icon="$icon"
  --urgency=critical
  --expire-time=0
  --print-id
  --action="default=Focus pane"
  --action="focus=Focus pane"
)
[ -n "${CLAUDE_PREV:-}" ] && args+=(--replace-id "$CLAUDE_PREV")

# --print-id makes notify-send emit the notification id IMMEDIATELY, then block
# until the notification closes (--action implies --wait), emitting the chosen
# action name last. So: read the id first and stash it for the dismiss hook,
# then read the action. If there is no notification server the reads hit EOF and
# we fall straight through — no loop, no spin.
exec 3< <(notify-send "${args[@]}" \
  "Claude · ${CLAUDE_DIR:-claude}" "${CLAUDE_MSG:-waiting for your input}" 2>/dev/null)
id=""; read -r id <&3
[ -n "$id" ] && [ -n "${CLAUDE_STATE:-}" ] && printf '%s\n' "$id" > "$CLAUDE_STATE"
action=""; read -r action <&3   # blocks until the notification closes
exec 3<&-

# Any invoked action focuses: body-click ("default"), the "Focus pane" button,
# or the $mod+g keybind (swaync-client -a 0, which fires the "focus" button).
# Replace / dismiss / expire leave the action empty.
[ -n "$action" ] || exit 0

# Raise/focus the terminal window in Sway.
[ -n "${CLAUDE_CON:-}" ] && swaymsg "[con_id=$CLAUDE_CON] focus" >/dev/null 2>&1

# Select the right tmux window + pane.
if [ -n "${CLAUDE_PANE:-}" ]; then
  tmux select-window -t "$CLAUDE_PANE" >/dev/null 2>&1
  tmux select-pane   -t "$CLAUDE_PANE" >/dev/null 2>&1
fi

exit 0
