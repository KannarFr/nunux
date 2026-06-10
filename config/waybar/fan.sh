#!/usr/bin/env bash
# Waybar custom/fan tile — current fan DUTY (percent), not RPM.
#
# This hardware (TUXEDO via tuxedo-io) exposes fan speed only as a 0-100 duty
# cycle; there is no tachometer / RPM anywhere in sysfs or the driver. tccd also
# only reports the duty when its sensor-data collection is enabled — and that
# flag is runtime-only (resets to off on every tccd restart), so we make sure it
# is on, then read GetFanDataJSON. Emits {text, tooltip, class}; CSS colors by
# loudness. Right after a tccd restart the first sample reads -1 ("not ready");
# we show "--" and the next interval self-heals.

bus="com.tuxedocomputers.tccd"
obj="/com/tuxedocomputers/tccd"
ICON=$'\U000F0210'   # nerd-font fan (nf-md-fan)

call() {
    busctl --system call "$bus" "$obj" "$bus" "$1" 2>/dev/null \
        | sed 's/^s //' | jq -r '.'
}

# Active TUXEDO Control Center profile → glyph. The tile's on-click opens the
# tcc-profile picker, so leading with the active profile's icon shows what is
# applied right now. Matched by profile name (see tcc-profile / GetCustomProfilesJSON).
prof=$(call GetActiveProfileJSON | jq -r '.name // empty')
case "$prof" in
    Performance) PICON=$'\U000F04C5' ;;  # nf-md-speedometer
    Balanced)    PICON=$'\U000F05D1' ;;  # nf-md-scale_balance
    Silent)      PICON=$'\U000F06DA' ;;  # nf-md-feather
    Powersave)   PICON=$'\U000F032A' ;;  # nf-md-leaf
    *)           PICON=$'\U000F0210' ;;  # unknown profile → fan glyph
esac

unknown() { jq -cn --arg t "$PICON --" --arg tt "$1" '{text:$t,tooltip:$tt,class:"fan-unknown"}'; exit 0; }

# Make sure tccd is actually sampling the fans (no-op if already on).
if [ "$(busctl --system call "$bus" "$obj" "$bus" GetSensorDataCollectionStatus 2>/dev/null)" != "b true" ]; then
    busctl --system call "$bus" "$obj" "$bus" SetSensorDataCollectionStatus b true >/dev/null 2>&1
fi

data=$(call GetFanDataJSON)
[ -n "$data" ] || unknown "tccd unreachable"

IFS=$'\t' read -r cpu_spd cpu_t fan2_spd fan2_t < <(printf '%s' "$data" \
    | jq -r '[.cpu.speed.data, .cpu.temp.data, .gpu1.speed.data, .gpu1.temp.data] | @tsv')

# -1 means "not sampled yet" (first tick right after enabling collection).
[ "${cpu_spd:--1}" -ge 0 ] 2>/dev/null || unknown "fan speed not available yet"

# Loudness class from the louder of the two fans.
top=$cpu_spd
[ "${fan2_spd:-0}" -gt "$top" ] 2>/dev/null && top=$fan2_spd
if   [ "$top" -lt 35 ]; then class=fan-quiet
elif [ "$top" -lt 70 ]; then class=fan-mid
else                         class=fan-loud
fi

text="${PICON} ${ICON} ${cpu_spd}%"
# Real newlines here; jq escapes them to \n in the JSON it emits. Profile names
# are user-authored, so let jq escape every field instead of hand-quoting.
tooltip="${prof:-?} profile"$'\n'"CPU fan ${cpu_spd}%"
[ "${cpu_t:-0}" -gt 0 ] 2>/dev/null && tooltip="${tooltip} · ${cpu_t}°C"
if [ "${fan2_spd:--1}" -ge 0 ] 2>/dev/null; then
    tooltip="${tooltip}"$'\n'"2nd fan ${fan2_spd}%"
    [ "${fan2_t:-0}" -gt 0 ] 2>/dev/null && tooltip="${tooltip} · ${fan2_t}°C"
fi

jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text:$text,tooltip:$tooltip,class:$class}'
