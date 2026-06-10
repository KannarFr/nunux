#!/usr/bin/env bash
# Waybar custom/backlight tile — brightness % + icon, fully HIDDEN at 100%.
#
# Why a script instead of the native "backlight" module: that module does not
# hide its widget on empty output in this waybar version, so `format-full: ""`
# only blanks the label and leaves a 1px sliver. The battery module DOES hide on
# empty (that's its format-full support). A custom module collapses on empty
# output the same way — so we emit nothing at 100% and the tile disappears.

# nerd-font brightness ramp (the old backlight format-icons), low -> high.
ICONS=($'' $'' $'' $'' $'' $'' $'' $'' $'')

pct=$(brightnessctl -m 2>/dev/null | head -1 | cut -d, -f4 | tr -d '%')
[ -n "$pct" ] || exit 0                 # no backlight / parse failure -> show nothing
[ "$pct" -ge 100 ] 2>/dev/null && exit 0  # 100% -> empty output -> tile hidden

n=${#ICONS[@]}
idx=$(( pct * n / 100 ))
[ "$idx" -ge "$n" ] && idx=$((n - 1))
printf '%s%% %s\n' "$pct" "${ICONS[$idx]}"
