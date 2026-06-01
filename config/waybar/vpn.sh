#!/usr/bin/env bash
# Waybar custom/vpn tile — the "tunnel" half of the network section.
#
# The WireGuard tunnel terminates on the UniFi gateway, not on this host, so
# there is no local wg/tun interface to inspect. We detect VPN state by public
# egress: ask ipinfo.io what AS/org the internet sees us coming from.
#
# Setup here: VPN exits through Clever Cloud (AS213394), bare ISP is Orange FR.
# So a positive match on Clever Cloud means tunneled — anything else (Orange at
# home, or some other network on the road) is treated as off.
#
# Emits one JSON line: {text, tooltip, class}. CSS colors by class:
#   vpn-on      → green   (egress AS is Clever Cloud)
#   vpn-off     → red     (egress is some other AS — not tunneled)
#   vpn-unknown → grey    (endpoint unreachable / no network)

VPN_AS="AS213394"          # Clever Cloud SAS — the VPN exit
ICON_ON=$''          # nerd-font lock      (on VPN)
ICON_OFF=$''         # nerd-font unlock    (not on VPN)
ICON_UNK=$''         # nerd-font question  (unknown)

json=$(curl -s --max-time 4 https://ipinfo.io/json 2>/dev/null)

if [ -z "$json" ]; then
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
        "$ICON_UNK" "VPN check failed (no network?)" "vpn-unknown"
    exit 0
fi

org=$(printf '%s' "$json" | jq -r '.org // "?"')
ip=$(printf '%s' "$json"  | jq -r '.ip // "?"')
city=$(printf '%s' "$json" | jq -r '.city // "?"')
country=$(printf '%s' "$json" | jq -r '.country // "?"')

if printf '%s' "$org" | grep -qiE "${VPN_AS}|clever cloud"; then
    icon="$ICON_ON"
    tooltip="On VPN — ${ip} (${org}, ${city} ${country})"
    class="vpn-on"
else
    icon="$ICON_OFF"
    tooltip="NOT on VPN — ${ip} (${org}, ${city} ${country})"
    class="vpn-off"
fi
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$icon" "$tooltip" "$class"
