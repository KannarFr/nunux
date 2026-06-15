#!/usr/bin/env bash
# Waybar custom module: battery power flow as a single signed wattage.
#   charging    → +W into the battery (class: charging)
#   discharging → −W out of the battery, i.e. live system draw (class: discharging)
# Computed from BAT0 voltage_now × current_now (the only reliable live reading;
# true wall-input wattage isn't exposed over USB-C PD).

B=/sys/class/power_supply/BAT0
read -r v < "$B/voltage_now" 2>/dev/null || exit 0
read -r i < "$B/current_now" 2>/dev/null || exit 0
read -r status < "$B/status"  2>/dev/null || status=Unknown

# µV × µA = pW → W, magnitude only (status decides the sign below; some
# firmwares report current_now negative while discharging).
watts=$(awk -v v="$v" -v i="$i" 'BEGIN { w = v * i / 1e12; printf "%.0f", (w < 0 ? -w : w) }')

case "$status" in
    Charging)    icon=""; sign="+"; class=charging   ;;
    Discharging) icon=""; sign="−"; class=discharging ;;
    *)           icon=""; sign="";  class=idle; watts=0 ;;
esac

printf '{"text":"%s%dW %s","tooltip":"%s: %s%dW","class":"%s"}\n' \
    "$sign" "$watts" "$icon" "$status" "$sign" "$watts" "$class"
