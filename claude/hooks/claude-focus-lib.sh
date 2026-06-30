#!/usr/bin/env bash
# Shared helpers for the Claude-waiting notification hooks. SOURCED (not exec'd)
# by claude-focus.sh, claude-waiting-notify.sh, and claude-dismiss.sh so the
# pane-focus and notification-close incantations live in exactly one place.

# focus_pane CON PANE — raise the sway window holding con_id CON, then select
# tmux window+pane PANE. Each step is a silent no-op if its arg is empty or the
# target is already gone.
focus_pane() {
  local con="$1" pane="$2"
  [ -n "$con" ] && swaymsg "[con_id=$con] focus" >/dev/null 2>&1
  if [ -n "$pane" ]; then
    tmux select-window -t "$pane" >/dev/null 2>&1
    tmux select-pane   -t "$pane" >/dev/null 2>&1
  fi
}

# close_noti ID — close notification ID via the freedesktop API. Closing it also
# unblocks the detached claude-waiting-notify.sh helper that is waiting on it.
close_noti() {
  [ -n "$1" ] || return 0
  gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1
}
