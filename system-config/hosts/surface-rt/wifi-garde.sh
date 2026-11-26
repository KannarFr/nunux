#!/bin/bash
# Garde du Wi-Fi de la Surface RT, lancé chaque minute par wifi-garde.timer (root).
#
# Le 2026-11-26, le firmware Wi-Fi (mwifiex) a planté et son pilote est resté bloqué (tâche noyau en état D) :
# plus de réseau, rien à décharger, seul un redémarrage en sort. Ici : si le routeur ne répond plus,
# 3 minutes de suite -> on relance la connexion ; 6 minutes -> redémarrage forcé (sysrq : un reboot normal
# risque de rester coincé sur le pilote bloqué). Jamais dans les 10 premières minutes après le démarrage,
# et au plus un redémarrage forcé par heure (si c'est le routeur qui est en panne, inutile de boucler).
#
# WIFI_GARDE_ESSAI=1 : dit ce qu'il ferait, ne relance ni ne redémarre rien. WIFI_GARDE_CIBLE : adresse à
# pinguer à la place du routeur (essais). WIFI_GARDE_ETAT : compteur ailleurs que dans /run (essais).
set -uo pipefail
ETAT=${WIFI_GARDE_ETAT:-/run/wifi-garde.echecs}
DERNIER=/var/lib/wifi-garde/dernier-redemarrage
RELANCE_APRES=3
REDEMARRE_APRES=6
log() { echo "$*"; logger -t wifi-garde "$*"; }

passerelle=${WIFI_GARDE_CIBLE:-$(ip -4 route show default 2>/dev/null | awk '/default/ {print $3; exit}')}
if [ -n "$passerelle" ] && ping -c 2 -W 3 -q "$passerelle" >/dev/null 2>&1; then
  if [ -s "$ETAT" ] && [ "$(cat "$ETAT")" != 0 ]; then log "réseau revenu après $(cat "$ETAT") échec(s)"; fi
  echo 0 > "$ETAT"
  exit 0
fi

echecs=$(( $(cat "$ETAT" 2>/dev/null || echo 0) + 1 ))
echo "$echecs" > "$ETAT"
log "routeur ${passerelle:-(pas de route par défaut)} injoignable, échec $echecs"

if [ "$echecs" -eq "$RELANCE_APRES" ]; then
  log "relance de la connexion Wi-Fi"
  [ "${WIFI_GARDE_ESSAI:-0}" = 1 ] || timeout 30 nmcli device connect mlan0 >/dev/null 2>&1 || log "relance sans effet"
fi

if [ "$echecs" -ge "$REDEMARRE_APRES" ]; then
  demarre_depuis=$(cut -d. -f1 /proc/uptime)
  if [ "$demarre_depuis" -lt 600 ]; then
    log "pas de redémarrage : la tablette tourne depuis ${demarre_depuis} s seulement"; exit 0
  fi
  if [ -s "$DERNIER" ] && [ $(( $(date +%s) - $(cat "$DERNIER") )) -lt 3600 ]; then
    log "pas de redémarrage : déjà un redémarrage forcé il y a moins d'une heure"; exit 0
  fi
  dmesg | grep -E "mwifiex.*(FW is in bad state|cmd_timeout|Timeout cmd)" | tail -3 | while read -r l; do log "noyau : $l"; done
  log "redémarrage forcé"
  [ "${WIFI_GARDE_ESSAI:-0}" = 1 ] && exit 0
  mkdir -p "$(dirname "$DERNIER")"; date +%s > "$DERNIER"
  sync; sleep 2
  echo s > /proc/sysrq-trigger; sleep 1   # tout écrire sur l'eMMC
  echo u > /proc/sysrq-trigger; sleep 1   # remonter en lecture seule
  echo b > /proc/sysrq-trigger            # redémarrer tout de suite
fi
