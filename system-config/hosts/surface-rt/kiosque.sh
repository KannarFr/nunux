#!/bin/bash
# Kiosque de la Surface RT : Chromium plein écran sur le tableau HA, relancé s'il se ferme.
# Lancé par ~/.config/lxsession/LXDE-pi/autostart ; URL dans /etc/ecran-salon.url (posée par apply).
URL=$(cat /etc/ecran-salon.url 2>/dev/null || echo "http://10.0.0.151:8123/wallscreen-salon")
PREFS="$HOME/.config/chromium/Default/Preferences"
while true; do
  # pas de bulle « Chromium ne s'est pas fermé correctement » après un plantage ou une coupure
  if [ -f "$PREFS" ]; then
    sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/; s/"exited_cleanly":false/"exited_cleanly":true/' "$PREFS"
  fi
  chromium --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
    --disable-translate --password-store=basic --check-for-update-interval=31536000 \
    --disk-cache-size=52428800 --autoplay-policy=no-user-gesture-required \
    --overscroll-history-navigation=0 --disable-pinch --hide-scrollbars \
    --force-device-scale-factor=1.6 "$URL"
  sleep 5
done
