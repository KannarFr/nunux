#!/usr/bin/env bash
# $mod+g target: jump to the tmux pane of the most-recently-waiting Claude.
#
# Reads the per-pane state files claude-waiting-notify.sh writes (3 lines:
# notification id, sway con_id, tmux pane), one per pane that currently has a
# pending "Claude is waiting" notification — claude-dismiss.sh removes a pane's
# file the moment you answer it. We walk them newest-first and focus the first
# whose sway con_id still exists, so a session killed mid-wait (stale file) or a
# pre-upgrade 1-line file (empty con) is skipped instead of focusing nothing.
#
# Why not `swaync-client -a 0` (the old binding)? That flag only ever fires an
# action on the *latest* notification, so a Slack/etc. noti stacked on top stole
# the jump. Focusing from our own state is immune to notification ordering.
set -u

dir="${XDG_RUNTIME_DIR:-/tmp}"
. "$(dirname "$(readlink -f "$0")")/claude-focus-lib.sh"

tree="$(swaymsg -t get_tree 2>/dev/null)"

state="" id="" con="" pane=""
for f in $(ls -t "$dir"/claude-notify-*.id 2>/dev/null); do
  { read -r fid; read -r fcon; read -r fpane; } < "$f"
  [ -n "$fcon" ] || continue   # legacy 1-line file: no con to focus
  # con_id still present in the live tree? (skips panes killed while waiting)
  if printf '%s' "$tree" | jq -e --argjson c "$fcon" \
       'any(.. | objects; .id? == $c)' >/dev/null 2>&1; then
    state="$f" id="$fid" con="$fcon" pane="$fpane"
    break
  fi
done
[ -n "$state" ] || exit 0

focus_pane "$con" "$pane"
# Clear the notification + its state, just as clicking it would.
close_noti "$id"
rm -f "$state"

exit 0
