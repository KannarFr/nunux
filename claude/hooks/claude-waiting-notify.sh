#!/usr/bin/env bash
# Helper for claude-waiting.sh, run detached (setsid). Shows ONE notification
# (replacing this pane's previous one), records its id so claude-dismiss.sh can
# close it, and — only if the notification is actually CLICKED — focuses the
# terminal window and selects the tmux pane.
# Inputs via env: CLAUDE_CON CLAUDE_PANE CLAUDE_DIR CLAUDE_PREV CLAUDE_STATE.
set -u

here="$(dirname "$(readlink -f "$0")")"
. "$here/claude-focus-lib.sh"

# Kept to ONE line on purpose: no icon, no body, no action button — each of
# those adds a row (the icon alone is ~64px tall). Clicking the notification
# still fires the invisible "default" action, and $mod+g still focuses.
args=(
  --app-name=claude
  --urgency=critical
  --expire-time=0
  --print-id
  --action="default=Focus pane"
)
[ -n "${CLAUDE_PREV:-}" ] && args+=(--replace-id "$CLAUDE_PREV")

# --print-id makes notify-send emit the notification id IMMEDIATELY, then block
# until the notification closes (--action implies --wait), emitting the chosen
# action name last. So: read the id first and stash it for the dismiss hook,
# then read the action. If there is no notification server the reads hit EOF and
# we fall straight through — no loop, no spin.
exec 3< <(notify-send "${args[@]}" \
  "Claude — ${CLAUDE_DIR:-claude}" 2>/dev/null)
id=""; read -r id <&3
# State file is 3 lines: notification id, sway con_id, tmux pane. The id lets
# claude-dismiss.sh close it; con+pane let claude-focus.sh ($mod+g) jump here
# without going through swaync (whose -a only ever acts on the *latest* noti).
[ -n "$id" ] && [ -n "${CLAUDE_STATE:-}" ] && \
  printf '%s\n%s\n%s\n' "$id" "${CLAUDE_CON:-}" "${CLAUDE_PANE:-}" > "$CLAUDE_STATE"
action=""; read -r action <&3   # blocks until the notification closes
exec 3<&-

# An invoked action focuses: a click fires "default".
# ($mod+g no longer comes through here — claude-focus.sh focuses directly.)
# Replace / dismiss / expire leave the action empty.
[ -n "$action" ] || exit 0

# Raise the terminal window + select the tmux pane.
focus_pane "${CLAUDE_CON:-}" "${CLAUDE_PANE:-}"

exit 0
