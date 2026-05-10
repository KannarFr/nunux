#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

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

printf '%s[%s]%s %s%s%s %s@%s %s%s%s %s|%s %s%s%s %s|%s ctx %s[%s%s%s%s]%s %s%s%%%s' \
  "$CYAN"    "$MODEL"   "$RESET" \
  "$GREEN"   "$PROJECT" "$RESET" \
  "$DIM"     "$RESET" \
  "$YELLOW"  "$BRANCH"  "$RESET" \
  "$DIM"     "$RESET" \
  "$MAGENTA" "$COST_FMT" "$RESET" \
  "$DIM"     "$RESET" \
  "$CTX_COLOR" "$BAR" "$RESET" "$DIM" "$DOTS" "$RESET" \
  "$CTX_COLOR" "$CTX" "$RESET"
