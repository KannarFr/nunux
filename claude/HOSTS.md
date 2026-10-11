# Home LAN machines: ocean and pacific

Two machines on the home LAN, reachable from this laptop as `ssh ocean` and `ssh pacific` (key-only). Addresses and user live in `~/.ssh/config` (the nunux `sshconfig`): always go through the alias, never a hardcoded IP. They are only reachable from the home network: away from it, assume they are not there. `ws1` is a different thing, see `WS1.md`.

**"Pacific" is also a Ceph release** (16.2.x, vs Reef 18.2.x). In Clever Cloud repos (axo, ovd, testcontainers-ceph), "Pacific" almost always means the Ceph track, not this Mac.

## ocean

Desktop PC, dual boot: Windows on its own disk, Arch Linux on a second disk (installed from WSL with `bin/wsl-install-arch` in the nunux repo, no LUKS so it comes back after a power cut). When it is booted on Arch, ssh works; when it is on Windows, it does not answer. As of 2026-10-11: 16 cores, 31G RAM, docker and claude installed, a copy of nunux in `~/git/kannar/nunux`. Re-check before relying on it (`ssh ocean 'nproc; free -g; command -v docker claude'`).

It is the user's own desktop, not a build server: do not start long jobs on it without asking. For offloaded work, `ws1` is the default.

## pacific

Mac mini M2 (8 cores, 8G RAM, as of 2026-10-11), the iOS build machine for myle-mobile (`eas build --local`, Xcode, fastlane, CocoaPods). Known traps:

- Homebrew tools live in `/opt/homebrew/bin`, which a non-interactive ssh does not have on `PATH`: prefix remote commands with `export PATH=/opt/homebrew/bin:$PATH`, or everything looks uninstalled.
- Export `LANG=en_US.UTF-8` and `LC_ALL` in build commands, or CocoaPods exits 1.
- It has no GitHub key and cannot `git pull`: code is sent over with tar + scp.
- The disk is small (228G) and fills with builds; check free space (`ssh pacific 'df -h /'`) before an iOS build.

The full procedure is in the myle repo's `eas-local-deploy` skill and memory.
