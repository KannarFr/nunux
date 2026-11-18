#!/usr/bin/env bash
# Waybar custom/gpu tile (desktop, NVIDIA): load %, temperature, VRAM used, and
# the GPU fan when it spins. class: the same t-* temperature classes as
# custom/cpu-temp, or gpu-error when nvidia-smi fails.
#
# The only nvidia-smi call per tick (~50 ms); custom/fans leaves the GPU to
# this tile. No nvidia-smi installed: no output, the tile disappears. nvidia-smi
# installed but failing (driver not loaded, or upgraded without a reboot): it
# prints its error on stdout, so the exit status and every number are checked,
# and the tile says "GPU ?" in red instead of showing the error text.

command -v nvidia-smi >/dev/null || exit 0

ICON='󰢮'   # nf-md-expansion_card
DEG=$'°'

fail() {
    jq -cn --arg text "$ICON ?" --arg tooltip "nvidia-smi: $1" '{text:$text,tooltip:$tooltip,class:"gpu-error"}'
    exit 0
}

out=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,fan.speed,name \
    --format=csv,noheader,nounits 2>&1) || fail "$(head -1 <<<"$out")"
# Comma-separated; fields can hold spaces ("[N/A]", "[Not Supported]", the name).
IFS=',' read -r util temp mem_used mem_total power fan name <<<"$(head -1 <<<"$out")"
trim() { local v=$1; v=${v#"${v%%[![:space:]]*}"}; printf '%s' "${v%"${v##*[![:space:]]}"}"; }
util=$(trim "$util"); temp=$(trim "$temp"); mem_used=$(trim "$mem_used")
mem_total=$(trim "$mem_total"); power=$(trim "$power"); fan=$(trim "$fan"); name=$(trim "$name")

isnum() { [[ $1 =~ ^[0-9]+$ ]]; }
isnum "$util" && isnum "$temp" && isnum "$mem_used" && isnum "$mem_total" \
    || fail "unexpected output: $(head -1 <<<"$out")"

if   (( temp < 50 )); then class=t-cool
elif (( temp < 70 )); then class=t-mild
elif (( temp < 80 )); then class=t-warm
elif (( temp < 90 )); then class=t-hot
else                       class=t-crit
fi

used_g=$(awk -v m="$mem_used" 'BEGIN { printf "%.1f", m / 1024 }')
total_g=$(awk -v m="$mem_total" 'BEGIN { printf "%.0f", m / 1024 }')
text="$ICON ${util}% ${temp}${DEG}C ${used_g}G"
isnum "$fan" && (( fan > 0 )) && text+=" 󰈐 ${fan}%"

tip="$name"$'\n'"load ${util}% · ${temp}${DEG}C"
[[ $power =~ ^[0-9.]+$ ]] && tip+=" · ${power} W"
isnum "$fan" && tip+=" · fan ${fan}%"
tip+=$'\n'"VRAM ${used_g} / ${total_g} GiB"

jq -cn --arg text "$text" --arg tooltip "$tip" --arg class "$class" \
    '{text:$text,tooltip:$tooltip,class:$class}'
