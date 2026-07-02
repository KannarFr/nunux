#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FIVEH_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
FIVEH_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
WEEK_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
WEEK_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

PROJECT=$(basename "$DIR")

BRANCH=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null \
  || git -C "$DIR" rev-parse --short HEAD 2>/dev/null \
  || echo "no-git")

COST_FMT=$(printf '$%.2f' "$COST")

# ANSI colors
RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'

# Pick a color for the context bar based on usage
if   [ "$CTX" -lt 50 ]; then CTX_COLOR=$GREEN
elif [ "$CTX" -lt 80 ]; then CTX_COLOR=$YELLOW
else                          CTX_COLOR=$RED
fi

BAR_WIDTH=10
FILLED=$(( CTX * BAR_WIDTH / 100 ))
[ "$FILLED" -gt "$BAR_WIDTH" ] && FILLED=$BAR_WIDTH
[ "$FILLED" -lt 0 ] && FILLED=0
EMPTY=$(( BAR_WIDTH - FILLED ))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
DOTS=""
for ((i=0; i<EMPTY; i++)); do DOTS+="░"; done

# format a unix timestamp as a short "resets in" countdown
fmt_reset() {
  local ts="$1" now diff
  [ -z "$ts" ] && return
  now=$(date +%s)
  diff=$(( ts - now ))
  if   [ "$diff" -le 0 ];     then echo "now"
  elif [ "$diff" -lt 3600 ];  then echo "$(( diff / 60 ))m"
  elif [ "$diff" -lt 86400 ]; then echo "$(( diff / 3600 ))h"
  else                             echo "$(( diff / 86400 ))d"
  fi
}

# color for a usage percentage: <50 green, <80 yellow, else red
usage_color() {
  local pct="$1"
  if   [ "$pct" -lt 50 ]; then echo "$GREEN"
  elif [ "$pct" -lt 80 ]; then echo "$YELLOW"
  else                          echo "$RED"
  fi
}

USAGE_SEG=""
if [ -n "$FIVEH_PCT" ]; then
  FIVEH_COLOR=$(usage_color "$FIVEH_PCT")
  FIVEH_RESET_FMT=$(fmt_reset "$FIVEH_RESET")
  USAGE_SEG+=$(printf ' %s|%s session %s%s%%%s' "$DIM" "$RESET" "$FIVEH_COLOR" "$FIVEH_PCT" "$RESET")
  [ -n "$FIVEH_RESET_FMT" ] && USAGE_SEG+=$(printf '%s (resets in %s)%s' "$DIM" "$FIVEH_RESET_FMT" "$RESET")
fi
if [ -n "$WEEK_PCT" ]; then
  WEEK_COLOR=$(usage_color "$WEEK_PCT")
  WEEK_RESET_FMT=$(fmt_reset "$WEEK_RESET")
  USAGE_SEG+=$(printf ' %s|%s week %s%s%%%s' "$DIM" "$RESET" "$WEEK_COLOR" "$WEEK_PCT" "$RESET")
  [ -n "$WEEK_RESET_FMT" ] && USAGE_SEG+=$(printf '%s (resets in %s)%s' "$DIM" "$WEEK_RESET_FMT" "$RESET")
fi

printf '%s[%s]%s %s%s%s %s@%s %s%s%s %s|%s %s%s%s %s|%s ctx %s[%s%s%s%s]%s %s%s%%%s%s' \
  "$CYAN"    "$MODEL"   "$RESET" \
  "$GREEN"   "$PROJECT" "$RESET" \
  "$DIM"     "$RESET" \
  "$YELLOW"  "$BRANCH"  "$RESET" \
  "$DIM"     "$RESET" \
  "$MAGENTA" "$COST_FMT" "$RESET" \
  "$DIM"     "$RESET" \
  "$CTX_COLOR" "$BAR" "$RESET" "$DIM" "$DOTS" "$RESET" \
  "$CTX_COLOR" "$CTX" "$RESET" \
  "$USAGE_SEG"
