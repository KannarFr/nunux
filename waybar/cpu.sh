#!/usr/bin/env bash
# One-shot waybar custom/cpu module: emits a single JSON line and exits.
# State (last /proc/stat counters) is persisted in /tmp so usage delta works.

CPU_LABEL='CPU'
DEG=$'°'
STATE=/tmp/waybar-cpu.state

find_pkg_temp() {
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = coretemp ] || continue
        for lbl in "$h"/temp*_label; do
            [ "$(cat "$lbl" 2>/dev/null)" = "Package id 0" ] || continue
            echo "${lbl%_label}_input"; return 0
        done
    done
}

read_cpu_now() {
    read -r _ u n s i io ir sq st _ < /proc/stat
    total=$((u+n+s+i+io+ir+sq+st))
    idle=$((i+io))
}

usage_color() {
    local v=$1
    if   (( v < 30 )); then echo "#3a8a3a"
    elif (( v < 60 )); then echo "#b8a020"
    elif (( v < 85 )); then echo "#cc6a1a"
    else                    echo "#c83232"; fi
}
temp_color() {
    local v=$1
    if   (( v < 50 )); then echo "#3a6ea5"
    elif (( v < 70 )); then echo "#3a8a3a"
    elif (( v < 85 )); then echo "#b8a020"
    elif (( v < 95 )); then echo "#cc6a1a"
    else                    echo "#c83232"; fi
}

read_cpu_now

if [ -r "$STATE" ]; then
    read -r ptotal pidle < "$STATE"
    dt=$((total - ptotal)); di=$((idle - pidle))
    if (( dt > 0 )); then
        usage=$(( (100 * (dt - di) + dt/2) / dt ))
    else
        usage=0
    fi
else
    usage=0
fi
echo "$total $idle" > "$STATE"

TEMP_FILE=$(find_pkg_temp)
if [ -n "$TEMP_FILE" ] && t=$(cat "$TEMP_FILE" 2>/dev/null); then
    temp=$((t / 1000))
else
    temp=0
fi

uc=$(usage_color "$usage")
tclass=$(_tclass="$temp"; \
  if   (( _tclass < 50 )); then echo t-cool;
  elif (( _tclass < 70 )); then echo t-mild;
  elif (( _tclass < 85 )); then echo t-warm;
  elif (( _tclass < 95 )); then echo t-hot;
  else                          echo t-crit; fi)
# fixed-width fields so 9% and 100% take the same horizontal space
usage_str=$(printf '%3d%%' "$usage")
temp_str=$(printf  '%3d%sC' "$temp" "$DEG")
SPAN_ATTRS="line_height='1.4' foreground='#ffffff'"
NEUTRAL_BG="#2d3436"
# CPU label and usage chunk are explicit spans (their bgs are flat rectangles).
# Temp area has no span: the widget background carries the temp color, so the
# rounded right border-radius clips it nicely.
text="<span ${SPAN_ATTRS} background='${NEUTRAL_BG}'>  ${CPU_LABEL}  </span><span ${SPAN_ATTRS} background='${uc}'>  ${usage_str}  </span><span ${SPAN_ATTRS}>  ${temp_str}  </span>"
tooltip="CPU ${usage}%   Temp ${temp}${DEG}C"
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$tclass"
