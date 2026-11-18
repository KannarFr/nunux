#!/usr/bin/env bash
# Waybar custom/fans tile (desktop): motherboard fans in RPM from the Super I/O
# hwmon. The laptop's fan.sh is TUXEDO-only (duty % from tccd); this one reads
# plain hwmon. The GPU fan is shown by custom/gpu (one nvidia-smi call a tick).
#
# Needs the Super I/O driver loaded. On ocean (MSI MPG B550 GAMING PLUS) the
# chip is a Nuvoton NCT6687D, driven by mainline `nct6683` (read-only), which
# is not autoloaded: system-config/hosts/ocean/modules-load.d/nct6683.conf.
# `nct6775` is the wrong driver for it ("No such device").
#
# The driver gives no labels. On MSI boards the NCT6687D order is CPU, pump,
# then system fans 1-6 (same order as the out-of-tree nct6687d driver's
# labels); a fanN_label file, when a driver provides one, wins.
#
# Text: CPU fan RPM. Tooltip: CPU and pump always (0 rpm included), system
# fans when they spin (empty headers read 0). class by the CPU fan:
# fan-quiet / fan-mid / fan-loud, and fan-stopped (red) when the CPU fan or
# the pump reads 0: a dead fan must not look calm.

ICON='󰈐'   # nf-md-fan

hw=
for h in /sys/class/hwmon/hwmon*; do
    read -r n < "$h/name" 2>/dev/null || continue
    case "$n" in nct*|it87*|it86*|w83*|f71*|asus*) hw=$h; chip=$n; break ;; esac
done

if [ -z "$hw" ]; then
    jq -cn --arg text "$ICON ?" --arg tooltip "no Super I/O hwmon (on ocean: sudo modprobe nct6683)" \
        '{text:$text,tooltip:$tooltip,class:"fan-unknown"}'
    exit 0
fi

label() {  # $1 = fan index
    local f="$hw/fan$1_label" l
    if [ -r "$f" ] && read -r l < "$f"; then echo "$l"; return; fi
    case "$chip:$1" in
        nct6687:1) echo CPU ;;
        nct6687:2) echo Pump ;;
        nct6687:*) echo "Sys $(( $1 - 2 ))" ;;
        *)         echo "fan$1" ;;
    esac
}

cpu_rpm=
stopped=
tip=
for f in "$hw"/fan*_input; do
    [ -e "$f" ] || continue
    read -r rpm < "$f" 2>/dev/null || continue
    [[ $rpm =~ ^[0-9]+$ ]] || continue
    i=${f##*/fan}; i=${i%_input}
    l=$(label "$i")
    case "$l" in
        CPU|Pump|*[Cc][Pp][Uu]*|*[Pp]ump*)
            [ "$rpm" -eq 0 ] && stopped+="$l "
            [ -z "$cpu_rpm" ] && [ "$l" = CPU ] && cpu_rpm=$rpm ;;
        *)  [ "$rpm" -gt 0 ] || continue ;;
    esac
    tip+="$l ${rpm} rpm"$'\n'
done
tip=${tip%$'\n'}
# Unlabelled chip: take fan1 as the CPU fan.
[ -z "$cpu_rpm" ] && [ -r "$hw/fan1_input" ] && read -r cpu_rpm < "$hw/fan1_input"

if [ -n "$stopped" ];                          then class=fan-stopped; tip="stopped: ${stopped% }"$'\n'"$tip"
elif ! [[ $cpu_rpm =~ ^[0-9]+$ ]];             then class=fan-unknown
elif [ "$cpu_rpm" -lt 1000 ];                  then class=fan-quiet
elif [ "$cpu_rpm" -lt 1600 ];                  then class=fan-mid
else                                                class=fan-loud
fi

jq -cn --arg text "$ICON ${cpu_rpm:-?}" --arg tooltip "$tip" --arg class "$class" \
    '{text:$text,tooltip:$tooltip,class:$class}'
