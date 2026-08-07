#!/usr/bin/env bash
# Detached by codex-notify.sh. It waits for an interaction with the persistent
# notification without holding up Codex, and records enough state for $mod+g.
set -u

args=(
  --app-name=codex
  --icon=utilities-terminal
  --urgency=critical
  --expire-time=0
  --print-id
  --action="default=Focus pane"
  --action="focus=Focus pane"
)
[ -n "${CODEX_PREV:-}" ] && args+=(--replace-id "$CODEX_PREV")

exec 3< <(notify-send "${args[@]}" \
  "Codex · ${CODEX_DIR:-codex}" "${CODEX_MSG:-Finished — waiting for your next message}" 2>/dev/null)
id=""; read -r id <&3
# State lines: notification id, Sway container id, tmux pane. claude-focus.sh
# reads both Claude and Codex state files newest-first for the $mod+g jump.
[ -n "$id" ] && [ -n "${CODEX_STATE:-}" ] && \
  printf '%s\n%s\n%s\n' "$id" "${CODEX_CON:-}" "${CODEX_PANE:-}" > "$CODEX_STATE"
action=""; read -r action <&3
exec 3<&-

[ -n "$action" ] || exit 0

# This helper blocks on the notification until you interact with it, which can
# be hours -- easily long enough for sway to restart underneath it and leave the
# inherited $SWAYSOCK pointing at a dead socket, so the focus below would
# silently do nothing. Re-derive it at the moment of use.
if [ -r "$HOME/.claude/hooks/claude-focus-lib.sh" ]; then
  . "$HOME/.claude/hooks/claude-focus-lib.sh"
  focus_pane "${CODEX_CON:-}" "${CODEX_PANE:-}"
else
  [ -n "${CODEX_CON:-}" ] && timeout 4 swaymsg "[con_id=${CODEX_CON}] focus" >/dev/null 2>&1
  if [ -n "${CODEX_PANE:-}" ]; then
    tmux select-window -t "$CODEX_PANE" >/dev/null 2>&1
    tmux select-pane -t "$CODEX_PANE" >/dev/null 2>&1
  fi
fi
[ -n "${CODEX_STATE:-}" ] && rm -f "$CODEX_STATE"
