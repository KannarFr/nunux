#!/usr/bin/env bash
# One-shot waybar custom/cpu module: emits a single JSON line and exits.

CPU_LABEL='CPU'
DEG=$'°'

find_pkg_temp() {
    local h lbl name label
    for h in /sys/class/hwmon/hwmon*; do
        read -r name < "$h/name" 2>/dev/null || continue
        [ "$name" = coretemp ] || continue
        for lbl in "$h"/temp*_label; do
            read -r label < "$lbl" 2>/dev/null || continue
            [ "$label" = "Package id 0" ] || continue
            echo "${lbl%_label}_input"; return 0
        done
    done
}

load_color() {
    # ratio = load1 / cores: <0.5 idle, <0.75 ok, <1.0 busy, >=1.0 saturated
    awk -v l="$1" -v c="$2" 'BEGIN {
        if (c <= 0) { print "#3a8a3a"; exit }
        r = l / c
        if      (r < 0.50) print "#3a8a3a"
        else if (r < 0.75) print "#b8a020"
        else if (r < 1.00) print "#cc6a1a"
        else               print "#c83232"
    }'
}

TEMP_FILE=$(find_pkg_temp)
if [ -n "$TEMP_FILE" ] && read -r t < "$TEMP_FILE" 2>/dev/null; then
    temp=$((t / 1000))
else
    temp=0
fi

read -r l1 l5 l15 _ < /proc/loadavg
cores=$(nproc 2>/dev/null || echo 1)

lc=$(load_color "$l1" "$cores")
if   (( temp < 50 )); then tclass=t-cool
elif (( temp < 70 )); then tclass=t-mild
elif (( temp < 85 )); then tclass=t-warm
elif (( temp < 95 )); then tclass=t-hot
else                       tclass=t-crit
fi
temp_str=$(printf '%3d%sC' "$temp" "$DEG")
SPAN_ATTRS="line_height='1.4' foreground='#ffffff'"
# Temp has no inline bg — the widget's CSS background paints it instead, so
# border-radius clips it cleanly on the rounded right edge.
text="<span ${SPAN_ATTRS} background='${lc}'>  ${CPU_LABEL} ${l1}/${cores}c </span><span ${SPAN_ATTRS}> ${temp_str}  </span>"
tooltip="Load ${l1} ${l5} ${l15} over ${cores} cores   Temp ${temp}${DEG}C"
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$tclass"
