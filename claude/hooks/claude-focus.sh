#!/usr/bin/env bash
# $mod+g target: jump to the tmux pane of the most-recently-waiting Claude or
# most-recently-finished Codex turn.
#
# Reads the per-pane state files Claude and Codex notification hooks write (3 lines:
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
ensure_swaysock   # sway's own bindsym env is fine; a manual run's may be stale

tree="$(timeout "$SWAY_PROBE_TIMEOUT" swaymsg -t get_tree 2>/dev/null)"

state="" id="" con="" pane=""
for f in $(ls -t "$dir"/claude-notify-*.id "$dir"/codex-notify-*.id 2>/dev/null); do
  { read -r fid; read -r fcon; read -r fpane; } < "$f"
  # Still focusable? Either the pane still has a window (survives a terminal
  # restart, which changes the con_id), or the recorded con_id is still in the
  # live tree. Skips panes killed while waiting and legacy 1-line files.
  if [ -n "$(pane_con "$fpane" "$tree")" ] || { [ -n "$fcon" ] &&
       printf '%s' "$tree" | jq -e --argjson c "$fcon" \
         'any(.. | objects; .id? == $c)' >/dev/null 2>&1; }; then
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
