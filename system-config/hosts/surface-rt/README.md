# Surface RT : écran mural Home Assistant

Une Surface RT (2012, Tegra 3, 2 Go) sous Raspberry Pi OS Bookworm armhf (image Open Surface RT, noyau 6.4
d'Open RT sur l'eMMC), en kiosque sur un tableau Home Assistant. Ce dossier n'est **pas** relié par
`apply.sh` : il est copié sur la tablette et installé par `apply`.

| Fichier | Rôle | Sur la tablette |
|---|---|---|
| `apply` | installe tout, idempotent (root) | lancé depuis `/tmp/surface-rt/` |
| `kiosque.sh` | Chromium `--kiosk` sur l'URL, relancé 5 s après sa sortie | `/usr/local/lib/ecran-salon/` |
| `autostart` | session X11 : pas d'économiseur ni de DPMS auto, curseur caché, kiosque | `~/.config/lxsession/LXDE-pi/autostart` |
| `ecran_mqtt.py`, `ecran-mqtt.service` | écran allumé / éteint par HA en MQTT, toucher, sons d'alerte | `/usr/local/lib/ecran-salon/`, `/etc/systemd/system/` |
| `journald.conf` | journal plafonné à 50 Mo (eMMC) | `/etc/systemd/journald.conf.d/50-ecran-salon.conf` |
| `test_ecran_mqtt.py` | tests de la logique (`python -m pytest -q`) | — |

## Déployer

```sh
scp -r system-config/hosts/surface-rt ecran-salon:/tmp/
scp ~/git/kannar/kannar/ha/alertes/sons/*.mp3 ecran-salon:/tmp/surface-rt/sons/   # clips d'alerte (repo privé)
ssh ecran-salon 'sudo bash /tmp/surface-rt/apply'
```

`URL_TABLEAU` (défaut `http://10.0.0.151:8123/wallscreen-salon`) et `UTILISATEUR` (défaut `kannar`) se
changent par l'environnement de `apply`.

## À la main, hors du repo

- `/etc/ecran-salon.env` (root, mode 600) : `MQTT_HOTE`, `MQTT_PORT`, `MQTT_UTILISATEUR`,
  `MQTT_MOT_DE_PASSE`, `TACTILE=/dev/input/by-path/platform-7000c400.i2c-event`. Sans lui, `ecran-mqtt`
  ne démarre pas.
- Le Wi‑Fi (NetworkManager) : son mot de passe ne va jamais dans ce repo.

## Pièges

- **Session** : lightdm est forcé sur `LXDE-pi-x` (X11). L'image livrait `autologin-session=LXDE-pi-wayfire`,
  absent, qui retombait sur X ; une mise à jour qui installe wayfire ou labwc ferait basculer la session et
  casserait `xset` (extinction de l'écran) : `apply` l'impose.
- **Noyau** : le noyau d'Open RT (`/boot/firmware/zImage`, `tegra30-microsoft-surface-rt-efi.dtb`,
  `startup.nsh`, `efi/boot/bootarm.efi`) n'est pas un paquet. Les paquets noyau et firmware de
  Raspberry Pi sont gelés (`apt-mark hold`), ne servent à rien ici et ne doivent pas être dégelés.
- **ssh** : l'agent du laptop présente 7 clés et la tablette coupe à 6 essais : l'alias `ecran-salon` de
  `sshconfig` force une seule clé.
- **Veille** : jamais. Le Wi‑Fi (mwifiex) ne revient pas après une mise en veille (vu le 2026-11-24 : plus aucun
  réseau visible au réveil, il faut redémarrer). `apply` masque les cibles de veille et fait ignorer le capot et
  le bouton Power par logind (un appui involontaire n'éteint pas l'écran mural) ; on éteint par le menu ou ssh.
- **Toucher** : X rallume l'écran tout seul au premier toucher ; `ecran-mqtt` suit l'état et le rééteint 60 s
  après si HA dit la pièce vide et sans alerte.
