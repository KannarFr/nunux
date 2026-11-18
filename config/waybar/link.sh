#!/usr/bin/env bash
# Waybar custom/link tile (desktop): the wired interface's IPv4 and negotiated
# speed. class: link-ok (>= 1 Gb/s), link-slow (below), link-down (no carrier
# or no IPv4).
#
# Why the speed: on ocean in Nov 2026 a failing cable downshifted the link to
# 100 then 10 Mb/s and flapped thousands of times a day for a week before the
# box dropped off the LAN; the kernel logged "Downshift ... check cabling!"
# and nothing on screen said a word. A red tile does.

# The interface of the IPv4 default route; without one, the first physical
# ethernet interface (en*), not docker bridges or veths.
dev=$(ip -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
if [ -z "$dev" ]; then
    for d in /sys/class/net/en*; do
        [ -e "$d/device" ] || continue
        dev=${d##*/}; break
    done
fi
[ -n "$dev" ] || { echo '{"text":"no NIC","class":"link-down"}'; exit 0; }

read -r carrier < "/sys/class/net/$dev/carrier" 2>/dev/null || carrier=0
read -r speed   < "/sys/class/net/$dev/speed"   2>/dev/null || speed=-1
ip4=$(ip -4 -o addr show dev "$dev" scope global 2>/dev/null | awk '{print $4; exit}')

ICON='󰈀'   # nf-md-ethernet

if [ "$carrier" != 1 ]; then
    text="$ICON down"; class=link-down; tip="$dev: no carrier"
elif [ -z "$ip4" ]; then
    text="$ICON no IPv4"; class=link-down; tip="$dev: link up at ${speed} Mb/s, no IPv4 address (DHCP?)"
else
    # speed is -1 (unknown) on bridges, wifi and virtual links: no verdict.
    if [ "$speed" -ge 1000 ] 2>/dev/null; then
        sp=$(awk -v s="$speed" 'BEGIN { printf "%gG", s / 1000 }'); class=link-ok
    elif [ "$speed" -gt 0 ] 2>/dev/null; then
        sp="${speed}M"; class=link-slow
    else
        sp=""; class=link-ok
    fi
    text="${ip4%/*} $ICON${sp:+ $sp}"
    tip="$dev $ip4"; [ "$speed" -gt 0 ] 2>/dev/null && tip+=" at ${speed} Mb/s"
    [ "$class" = link-slow ] && tip="$tip"$'\n'"below 1 Gb/s: check the cable (journalctl -k | grep -i downshift)"
fi

jq -cn --arg text "$text" --arg tooltip "$tip" --arg class "$class" \
    '{text:$text,tooltip:$tooltip,class:$class}'
