#!/usr/bin/env bash
# Waybar custom modules: dispatches on $1 to emit one JSON line per call.
#   $0 load  → load1/cores tile (class: l-idle | l-ok | l-busy | l-sat)
#   $0 temp  → package temp tile (class: t-cool | t-mild | t-warm | t-hot | t-crit)
# Split into two widgets so each has its own GTK background — no Pango bleed.

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

case "$1" in
    load)
        read -r l1 l5 l15 _ < /proc/loadavg
        cores=$(nproc 2>/dev/null || echo 1)
        lclass=$(awk -v l="$l1" -v c="$cores" 'BEGIN {
            if (c <= 0) { print "l-idle"; exit }
            r = l / c
            if      (r < 0.50) print "l-idle"
            else if (r < 0.75) print "l-ok"
            else if (r < 1.00) print "l-busy"
            else               print "l-sat"
        }')
        text="CPU ${l1}/${cores}c"
        tooltip="Load ${l1} ${l5} ${l15} over ${cores} cores"
        printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$lclass"
        ;;
    temp)
        TEMP_FILE=$(find_pkg_temp)
        if [ -n "$TEMP_FILE" ] && read -r t < "$TEMP_FILE" 2>/dev/null; then
            temp=$((t / 1000))
        else
            temp=0
        fi
        if   (( temp < 50 )); then tclass=t-cool
        elif (( temp < 70 )); then tclass=t-mild
        elif (( temp < 85 )); then tclass=t-warm
        elif (( temp < 95 )); then tclass=t-hot
        else                       tclass=t-crit
        fi
        printf -v text '%3d%sC' "$temp" "$DEG"
        tooltip="Package temp ${temp}${DEG}C"
        printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$tclass"
        ;;
    *)
        echo "usage: $0 {load|temp}" >&2
        exit 1
        ;;
esac
