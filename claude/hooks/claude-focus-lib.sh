#!/usr/bin/env bash
# Shared helpers for the Claude-waiting notification hooks. SOURCED (not exec'd)
# by claude-focus.sh, claude-waiting-notify.sh, and claude-dismiss.sh so the
# pane-focus and notification-close incantations live in exactly one place.

# ensure_swaysock — make $SWAYSOCK point at the *live* sway, or unset it.
#
# Hooks inherit their environment from the tmux server, which was started under
# whichever sway was running at the time. Restart sway (or survive one of this
# host's freezes) and every pane keeps exporting the dead socket — and because a
# crashed sway leaves its socket *file* behind, `[ -n "$SWAYSOCK" ]` is not proof
# that it answers. That is how state files end up with an empty con_id, which
# claude-focus.sh then skips, so $mod+g does nothing at all.
# Cheap enough to call unconditionally: one IPC round-trip on the happy path.
#
# Probes are wrapped in `timeout` as a backstop. Against a *hung* (not crashed)
# sway the socket still accepts connect(), so the request goes out and the reply
# never comes; swaymsg does self-bound that wait at ~3s ("Unable to receive IPC
# response", measured), so this is not the difference between hanging and not.
# What it does buy: a cap on the TOTAL when the fallback loop below probes
# several candidate sockets in turn, and an explicit, tunable bound instead of
# an undocumented internal one. Keep it just above swaymsg's own 3s -- tighter
# would cut off a healthy-but-slow compositor and report it as dead. Same value
# as bin/sway-watchdog's per-probe TIMEOUT, for the same reason.
SWAY_PROBE_TIMEOUT=${SWAY_PROBE_TIMEOUT:-4}
ensure_swaysock() {
  timeout "$SWAY_PROBE_TIMEOUT" swaymsg -t get_version >/dev/null 2>&1 && return 0
  local uid s pid
  uid="$(id -u)"
  for pid in $(pgrep -x sway 2>/dev/null); do
    s="${XDG_RUNTIME_DIR:-/run/user/$uid}/sway-ipc.$uid.$pid.sock"
    [ -S "$s" ] || continue
    if SWAYSOCK="$s" timeout "$SWAY_PROBE_TIMEOUT" swaymsg -t get_version >/dev/null 2>&1; then
      export SWAYSOCK="$s"
      return 0
    fi
  done
  unset SWAYSOCK   # no sway at all: let callers' [ -n "$SWAYSOCK" ] guards fire
  return 1
}

# pane_con PANE [TREE] — print the con_id of the sway window whose terminal
# hosts tmux pane PANE's client. Walk from the client's pid up the process tree;
# the first ancestor whose pid appears in get_tree is the terminal-emulator
# window (works for any terminal, not just one named binary). Pass TREE to reuse
# an already-fetched get_tree. Prints nothing if the pane has no client.
pane_con() {
  local pane="$1" tree="${2:-}" p con=""
  [ -n "$pane" ] || return 0
  [ -n "$tree" ] || tree="$(timeout "$SWAY_PROBE_TIMEOUT" swaymsg -t get_tree 2>/dev/null)"
  p="$(tmux display-message -p -t "$pane" '#{client_pid}' 2>/dev/null)"
  while [ -n "$p" ] && [ "$p" != "1" ]; do
    con="$(printf '%s' "$tree" | jq -r --argjson pid "$p" \
      'first(.. | objects | select(.pid? == $pid) | .id) // empty' 2>/dev/null)"
    [ -n "$con" ] && break
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
  printf '%s' "$con"
}

# focus_pane CON PANE — raise the sway window hosting tmux pane PANE, then
# select tmux window+pane PANE. The window is re-derived from the pane first:
# the CON recorded when the notification fired dies with the terminal (close and
# reopen it, and every pending notification points at a con_id that is gone),
# while the tmux pane survives. CON is only the fallback. Each step is a silent
# no-op if its target is empty or already gone.
focus_pane() {
  local con="$1" pane="$2" live
  ensure_swaysock
  live="$(pane_con "$pane")"
  [ -n "$live" ] && con="$live"
  [ -n "$con" ] && timeout "$SWAY_PROBE_TIMEOUT" swaymsg "[con_id=$con] focus" >/dev/null 2>&1
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
