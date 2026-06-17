# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles and system configuration. There is **no build, no tests, no lint** — most files here are the *real* configs the live system reads, exposed via symlinks from `$HOME` (and a few archival snapshots from `/etc`). Most edits are one-line tweaks; the value is in the conventions below.

## Deployment model: symlinks, not copies

For most tracked files, the live path under `$HOME` (or `~/.config`) is a symlink pointing into this repo. Editing the file here **is** editing the live config — no separate sync step. Verify with `ls -la <live-path>` before assuming. `./apply.sh` creates every symlink in the table below (idempotent; see README); the mapping it uses is the source of truth.

For a **full new-machine setup** (packages, services, login shell, Vim plugins, then `apply.sh`) use `./bootstrap.sh` — it automates the host-agnostic steps and prints the disk-/key-/secret-specific ones as a closing checklist. `apply.sh` is the dotfiles-only subset.

Two repo regions: home dotfiles keep their bare names at the repo root, and everything bound to `~/.config` lives under `config/` mirroring the destination path.

| Repo path | Live path (symlinked) |
|---|---|
| `bashrc`, `zshrc`, `zprofile`, `vimrc`, `gitconfig`, `psqlrc` | `~/.<name>` |
| `tmux` | `~/.tmux.conf` |
| `bat` | `~/.bat.conf` |
| `sshconfig` | `~/.ssh/config` |
| `gpg-agent.conf` | `~/.gnupg/gpg-agent.conf` |
| `config/sway/config` | `~/.config/sway/config` |
| `config/gammastep/config.ini` | `~/.config/gammastep/config.ini` |
| `config/swaylock/config` | `~/.config/swaylock/config` |
| `config/swaync/config.json` | `~/.config/swaync/config.json` |
| `config/waybar/` | `~/.config/waybar` |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/htop/htoprc` | `~/.config/htop/htoprc` |
| `config/mimeapps.list` | `~/.config/mimeapps.list` |
| `config/wireplumber/wireplumber.conf.d/51-bluez.conf` | `~/.config/wireplumber/wireplumber.conf.d/51-bluez.conf` |
| `config/systemd/user/restic-backup.{service,timer}` | `~/.config/systemd/user/restic-backup.{service,timer}` |
| `config/systemd/user/tcc-snapshot.{service,path}` | `~/.config/systemd/user/tcc-snapshot.{service,path}` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |
| `claude/settings.json` | `~/.claude/settings.json` (user-level Claude Code config) |
| `claude/commands/` | `~/.claude/commands` (user-defined slash commands) |
| `claude/agents/` | `~/.claude/agents` (user-defined subagents) |

Snapshots / not symlinked (read-only references; do not assume edits here propagate):

| Repo path | Source |
|---|---|
| `system-config/system/*` | `/etc/*` (root-owned originals; copy by hand if changed) |
| `paludis-config/*` | `/etc/paludis/*` — Paludis is the Exherbo package manager. Current host is Arch, so this dir is likely archival from a prior install. |
| `kernelconfig` | `/usr/src/linux/.config` — kernel build snapshot |
| `mtmux`, `doc/` | utility script + ad-hoc notes; live where they are |
| `bin/*` | helper scripts (`osd`, `battery-watch`, `powermenu`, `restic-backup`, `migrate-home`, `pkglist-refresh`, `tcc-profile`, `charge-profile`, `tcc-snapshot`, `yubikey-glow`) referenced by absolute path (sway's `set $bin`, systemd units, pacman hooks, waybar `on-click`) — not symlinked, not on `$PATH` |
| `system-config/pkglist-pacman.txt`, `system-config/pkglist-aur.txt` | `pacman -Qqen` / `pacman -Qqem` — explicit packages (official / AUR), for rebuilding a machine |
| `system-config/system/pacman.d/hooks/*` | `/etc/pacman.d/hooks/*` — pacman hooks: `pkglist-refresh.hook` (auto-refresh the package lists) and `tcc-snapshot.hook` (re-copy `/etc/tcc/*` into the repo via `bin/tcc-snapshot`). Both run PostTransaction as root and `su` to kannar; they only rewrite working-tree files — commit by hand. Snapshotting `/etc/tcc` on a *package* transaction is opportunistic: TCC config actually drifts from GUI edits, so this just sweeps it up next time you run pacman. For *real-time* capture there is also the `tcc-snapshot.path` user unit (inotify on `/etc/tcc/{settings,profiles}`) which runs the same `bin/tcc-snapshot` the instant either file changes — the pacman hook is the fallback for when the path unit isn't running. Both only rewrite the working tree; you still commit. |

Snapshots are one-way copies — there is no sync. Editing the live source (e.g. `/etc/...`) leaves the repo stale and `git status` clean, so drift is invisible. To update one: re-copy the source over the repo path by hand (`sudo cp /etc/systemd/zram-generator.conf system-config/system/systemd/zram-generator.conf`), preserving the mirrored layout (`/etc/foo/bar` → `system-config/system/foo/bar`), then `git add` + commit. If you edit the repo copy instead, remember to `sudo cp` it back to the live path — the running system reads the original, not the snapshot.

## Package lists (rebuilding a machine)

`system-config/pkglist-*.txt` track explicitly-installed packages so a new install loses nothing. They are snapshots like the rest — `bin/pkglist-refresh` regenerates them, then commit the diff (only *explicit* packages are listed; dependencies pulled in automatically are intentionally omitted and will be re-resolved on restore).

The three lists: `pkglist-pacman.txt` (official, `-Qqen`), `pkglist-aur.txt` (foreign, `-Qqem`), and `pkglist-aur-hardware.txt` — a **hand-curated** list of hardware-/host-specific AUR packages (currently the Tuxedo drivers + control center). `pkglist-refresh` **subtracts** the hardware list from the auto-generated `pkglist-aur.txt` so the main AUR list stays hardware-agnostic and safe to restore on a different machine. Add/remove hardware packages by editing `pkglist-aur-hardware.txt` directly (plain package names, no comments — it's fed to `yay -S - <file>`); the refresh keeps the main list in sync. Files must contain only package names (no `#` comments), since they're piped into pacman/yay stdin.

The refresh runs **automatically** via a pacman PostTransaction hook (`system-config/system/pacman.d/hooks/pkglist-refresh.hook`, live at `/etc/pacman.d/hooks/`). The hook runs as root, so it `su`s to `kannar` to keep the repo files user-owned — the hardcoded username and repo path make it host-specific; fix both when restoring on a new box. It only rewrites the working-tree files; **you still commit the diff by hand.**

Restore on a fresh box (AUR list needs `yay`/`paru` bootstrapped first):
```
sudo pacman -S --needed - < system-config/pkglist-pacman.txt
yay  -S --needed - < system-config/pkglist-aur.txt
```

## Critical: the skip-worktree files

`npmrc`, `wgetpaste.conf`, and `zprofile` are tracked but pinned locally with `git update-index --skip-worktree` (verify: `git ls-files -v | grep '^S'`). The `.gitignore` header explains why: these contain or risk leaking secrets. Note that `zprofile` is *also* symlinked from `~/.zprofile`, so edits to the symlink land in this repo's working tree — skip-worktree just hides them from `git status` so they aren't accidentally committed.

Rules:
- Don't edit these files here as part of normal work — drift is invisible to `git status`.
- To deliberately update the committed placeholder (non-secret line), use `git add -f <file>`.
- Secrets themselves load from `~/.local/share/secrets.env` via `zprofile` (sourced if present), never from anything tracked here.
- `npmrc` and `wgetpaste.conf` currently have **no** live `$HOME` copy on this machine — they're carried as templates for future use.

## Adding a new tracked dotfile

When the user asks to bring a config under version control:
1. Move it into the repo at its mirrored location — under `config/` for `~/.config` files (e.g. `mv ~/.config/foo/bar config/foo/bar`), or bare at the repo root for a home dotfile.
2. Add a `"repo/path  $HOME/live/path"` line to the `MAP` table in `apply.sh`.
3. Run `./apply.sh` to create the symlink (it backs up any existing real file to `<path>.bak` first).
4. `git add` + commit.

If the file may contain secrets, also `git update-index --skip-worktree <path>` and add a note to `.gitignore` next to the existing entries.

## Conventions worth knowing before editing

- **Vim plugins use Vundle**, not vim-plug or lazy.nvim — adding a plugin means a `Plugin '...'` line inside the `vundle#begin/end` block in `vimrc`, then `:PluginInstall`. The `set nocompatible` at the very top is required for Vundle to parse the file.
- **`gitconfig` is signed-commits-by-default** (`commit.gpgsign = true`) and rebases on pull. Don't suggest changes that assume merge-pull or unsigned commits.
- **`gitconfig` has URL rewrites**: `clever:foo/bar` → Clever Cloud GitLab, `github:foo/bar` → GitHub over SSH. Preserve these when editing.
- **`zshrc` is the source of truth for the interactive shell**, `bashrc` is minimal — most aliases/exports go in `zshrc`. The prompt itself comes from `starship.toml` (zshrc only does `eval "$(starship init zsh)"`).
- **`mtmux`** opens a tiled tmux window with synchronized SSH sessions to every host listed in its argument file, **as root**. Treat changes as security-sensitive.
- **TUXEDO control: two `bemenu` pickers, two waybar tiles.** `bin/tcc-profile` switches the *perf/fan* profile (a live temp override via tccd's `SetTempProfileById`, reverts on reboot/AC change) and is the **fan** tile's `on-click`; `bin/charge-profile` switches the *battery charge* profile (`SetChargingProfile`, persisted by tccd in `/etc/tcc/settings`) and is the **battery** tile's `on-click`. Both talk to `tccd` over the system bus (no root). The charge profiles are **named presets, not a numeric %** — this hardware (InfinityBook Pro AMD Gen10) exposes only `high_capacity`/`balanced`/`stationary` (≈100/80/60%); `balanced` is the longevity setting. The perf-profile *names* are hardcoded in three places that must stay in sync: `tcc-profile`'s `icons`, `fan.sh`'s `case`, and the live `/etc/tcc/profiles` (renaming a profile in the TCC GUI means updating both scripts **and** re-snapshotting `system-config/system/tcc/profiles`).
- **`claude/statusline.sh`** reads JSON from stdin (Claude Code passes session info this way), uses `jq`, emits ANSI single-line output. Context-bar thresholds: `<50` green, `<80` yellow, else red. It's wired in via `claude/settings.json` (`statusLine.command`).
- **`claude/commands/*.md`** are user-level slash commands (`/commit`, `/mr`, `/pr`, `/review`, etc.); **`claude/agents/*.md`** are user-level subagents. New ones can be added by dropping a markdown file in the right dir — the symlink makes it live immediately.

## Commit style

Recent log uses lowercase, scoped, terse subjects: `vim: drop vim-be-good (nvim-only)`, `vim: silence coc.nvim startup warning`, `remove unused dunstrc and sbtconfig`. Match that. No body unless the *why* is non-obvious.
