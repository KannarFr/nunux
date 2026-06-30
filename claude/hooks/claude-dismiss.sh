#!/usr/bin/env bash
# Claude Code hook (UserPromptSubmit): the user just sent a message, so the
# pending "Claude is waiting" notification for this tmux pane is stale — close
# it. Closing it via the freedesktop API also unblocks the detached helper
# (claude-waiting-notify.sh) that is waiting on it. Wired in claude/settings.json.
set -u
. "$(dirname "$(readlink -f "$0")")/claude-focus-lib.sh"
cat >/dev/null   # drain the hook JSON on stdin; we don't need it

key="${TMUX_PANE:-default}"; key="${key//[^A-Za-z0-9]/_}"
state="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-${key}.id"

id=""; [ -f "$state" ] && read -r id < "$state"   # first line of id/con/pane
[ -n "$id" ] || exit 0
rm -f "$state"

close_noti "$id"

exit 0
