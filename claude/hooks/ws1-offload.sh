#!/usr/bin/env bash
# Claude Code hook (PreToolUse on Bash and Agent): enforce claude/WS1.md. When
# the ws1 VM is free, a heavy command or a subagent that may write is refused
# with a message telling Claude to run it there through bin/ws1 instead. When
# ws1 is busy or unreachable, or the session is not in a git repo (bin/ws1 can
# only sync git trees), everything runs locally as before.
#
# Escape hatches, for work that must stay on the laptop (a phone on adb, a
# local-only service, the Mac build slave): a Bash command containing
# WS1_LOCAL=1, or an Agent prompt containing [ws1:local].
#
# Refusal is exit 2 with the reason on stderr, which Claude Code hands back to
# the model. Any failure of the hook itself lets the call through.

WS1=/home/kannar/git/kannar/nunux/bin/ws1
CACHE="${XDG_RUNTIME_DIR:-/tmp}/ws1-load"
CACHE_SECS=60

input=$(cat)
{ read -r tool; read -r cwd; read -r agent_type; } < <(
	printf '%s' "$input" | jq -r '.tool_name // "", .cwd // "", .tool_input.subagent_type // ""' 2>/dev/null
)
case "$tool" in
	Bash)
		cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
		[[ "$cmd" == *WS1_LOCAL=1* ]] && exit 0
		# Already going there.
		[[ "$cmd" =~ (bin/ws1|ssh[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(kannar@)?ws1) ]] && exit 0
		heavy='(^|[;&|(`[:space:]])(cargo[[:space:]]+(build|b|test|t|check|c|clippy|bench|nextest|run|r|doc|install)|sbt|mvn|gradle|\./gradlew|docker[[:space:]]+(build|buildx|compose|run)|(npm|pnpm|yarn)[[:space:]]+(run[[:space:]]+)?(build|test)|make|ninja|pytest|go[[:space:]]+(build|test))([[:space:]]|$)'
		[[ "$cmd" =~ $heavy ]] || exit 0
		what="this command"
		how="run $WS1 sync, then $WS1 exec '<the command>'"
		;;
	Agent|Task)
		# Read-only agents cost the laptop next to nothing.
		case "$agent_type" in Explore|Plan|claude-code-guide|statusline-setup) exit 0 ;; esac
		[[ "$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""')" == *'[ws1:local]'* ]] && exit 0
		what="this subagent"
		how="run $WS1 run --wait - <<'EOF' (the same brief) EOF as a background Bash command, then review $WS1 diff and apply it with $WS1 diff | git apply"
		;;
	*) exit 0 ;;
esac

git -C "${cwd:-.}" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# One ssh round-trip per minute at most, so a burst of tool calls stays fast.
if [[ -f "$CACHE" ]] && (($(date +%s) - $(stat -c %Y "$CACHE") < CACHE_SECS)); then
	status=$(<"$CACHE")
else
	status=$(timeout 8 "$WS1" load 2>/dev/null) || status="ws1 not free"
	printf '%s\n' "$status" >"$CACHE"
fi
[[ "$status" == "ws1 free:"* ]] || exit 0

if [[ "$status" == *"home LOCKED"* ]]; then
	echo "ws1 is free but its encrypted home is locked: run $WS1 unlock, then retry $what on ws1 ($how)." >&2
else
	echo "ws1 is free ($status), so per ~/.claude/WS1.md $what runs there, not on the laptop: $how. If it truly must run locally (device, local-only service), retry with WS1_LOCAL=1 in the command or [ws1:local] in the agent prompt, and say why." >&2
fi
exit 2
