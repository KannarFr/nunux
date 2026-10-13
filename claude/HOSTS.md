# Home LAN machines: ocean and pacific

Two machines on the home LAN, reachable from this laptop as `ssh ocean` and `ssh pacific` (key-only). Addresses and user live in `~/.ssh/config` (the nunux `sshconfig`): always go through the alias, never a hardcoded IP. They are only reachable from the home network: away from it, assume they are not there. `ws1` is a different thing, see `WS1.md`.

**"Pacific" is also a Ceph release** (16.2.x, vs Reef 18.2.x). In Clever Cloud repos (axo, ovd, testcontainers-ceph), "Pacific" almost always means the Ceph track, not this Mac.

## ocean

Desktop PC, dual boot: Windows on its own disk, Arch Linux on a second disk (installed from WSL with `bin/wsl-install-arch` in the nunux repo, no LUKS so it comes back after a power cut). When it is booted on Arch, ssh works; when it is on Windows, it does not answer. As of 2026-10-11: 16 cores, 31G RAM, docker and claude installed, a copy of nunux in `~/git/kannar/nunux`. Re-check before relying on it (`ssh ocean 'nproc; free -g; command -v docker claude'`).

It is the user's own desktop, not a build server: do not start long jobs on it without asking. For offloaded work, `ws1` is the default.

**It also serves production**: `ai.myleapp.fr`, the LLM behind Myle's MyleAI assistant (Ollama in a docker container named `ollama` on the RTX 3080 Ti, behind nginx; setup in the myle repo's `local-ai/`). So rebooting it, booting it into Windows, restarting docker or nginx, or loading anything else onto its GPU takes MyleAI down or slows it, for real customers. Ask first. The model needs 7.6 of the card's 12 GB; past the rest, Ollama puts part of the model on the CPU and answers much more slowly.

It also runs **Home Assistant** (`~/homeassistant/compose.yaml`, container `homeassistant`, host networking, `http://ocean:8123`, or `http://ha.home` through the NAS's LAN proxy). Its LAN-only firewall rules are the `homeassistant:` lines in ocean's `/etc/nftables.conf` (8123/tcp, 1883/tcp MQTT, SSDP replies, Shelly CoIoT 5683/udp). It goes down with ocean. What to know before touching it:

- The site is a farm: HA floors are used as buildings (Maison, Ferme, Chez Louise, the sister's house next door, on the same UniFi network). The main dashboard is `/dashboard-ferme`. Electricity is EDF Tempo 18 kVA three-phase (6 kVA per phase); `config/packages/tempo.yaml` holds the Tempo colour, HC/HP period and kWh price sensors, and the prices are `input_number.tempo_prix_*` helpers.
- The water heater (Shelly Pro 4PM in the cellier, output O3) is driven by a script on the Shelly itself ("Tempo + heures creuses"), which reapplies its state every 5 minutes: switching it from HA does not stick.
- Batteries: `config/packages/batteries.yaml` finds every battery sensor by device_class (counters, a "Batteries faibles" alert to `notify.foyer`); what to do per model is in `config/custom_templates/batteries.jinja`. The dashboard's Batteries view lists entities explicitly, so after adding a battery device re-run it: `docker exec -i -e HA_TOKEN="$(cat ~/homeassistant/claude.token)" homeassistant python - < ~/homeassistant/.ha-batteries-view.py` (the script lives on ocean's host, outside the container's `/config` mount, hence stdin). The `hors_ha_*_batterie` sensors are frozen Shelly-cloud readings (2026-10-12) for radiators HA could not reach: delete each one when its real device joins. The two BLU gateways have HA's Bluetooth scanner on, which is how BTHome devices (BLU TRVs, weather station, BLU H&T) arrive.
- Household alerts (Tempo colour, low batteries, washing machine done, close to tripping) go to `notify.foyer`, a notify group in `config/packages/foyer.yaml`; add a phone there by its `mobile_app_*` service. A new notify group only appears after an HA restart, not a reload. Users: the owner (admin) and `camille` (Camille Godefroy, non-admin, created 2026-10-13).
- **The `http:` block in `configuration.yaml` is ignored** since HA 2026: HTTP settings (reverse-proxy trust for the NAS, 10.0.0.165) live in `config/.storage/http`. Edit that with HA stopped.
- API access: a long-lived token in `~/homeassistant/claude.token` (mode 600; never print it, or `unifi.cred`, `unifi-protect.key`, `backup.key`, `mosquitto/*.password` next to it). The websocket API is reached with a small aiohttp script run inside the container (`docker exec -i -e HA_TOKEN=... homeassistant python -`).
- Backups: HA makes an encrypted backup daily at 04:15 (keeps 7, key in `backup.key`), and the user timer `ha-backup-copy.timer` rsyncs them at 05:00 to the NAS (`/share/homes/kannar/ha-backups/`) with `~/.ssh/ha-backup`, a key the NAS only accepts from ocean for that one rsync.

## pacific

Mac mini M2 (8 cores, 8G RAM, as of 2026-10-11), the iOS build machine for myle-mobile (`eas build --local`, Xcode, fastlane, CocoaPods). Known traps:

- Homebrew tools live in `/opt/homebrew/bin`, which a non-interactive ssh does not have on `PATH`: prefix remote commands with `export PATH=/opt/homebrew/bin:$PATH`, or everything looks uninstalled.
- Export `LANG=en_US.UTF-8` and `LC_ALL` in build commands, or CocoaPods exits 1.
- It has no GitHub key and cannot `git pull`: code is sent over with tar + scp.
- The disk is small (228G) and fills with builds; check free space (`ssh pacific 'df -h /'`) before an iOS build.

The full procedure is in the myle repo's `eas-local-deploy` skill and memory.
