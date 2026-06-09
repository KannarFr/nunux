# nunux

Personal dotfiles and system configuration for an Arch Linux + Sway (Wayland)
setup. The tracked files **are** the live configs: each one is symlinked into
`$HOME` from this repo, so editing a file here edits the running config — no
copy or sync step.

There is no build, no test, no lint. Most changes are one-line tweaks.

## Layout

| Region | What lives there |
|---|---|
| repo root | home dotfiles under their bare names — `bashrc`, `zshrc`, `vimrc`, `gitconfig`, `tmux`, `bat`, … |
| `config/` | everything bound to `~/.config`, mirroring the destination path — `config/sway/config`, `config/swaylock/config`, `config/waybar/`, `config/starship.toml`, … |
| `claude/` | user-level Claude Code config → `~/.claude` (`settings.json`, `statusline.sh`, `commands/`, `agents/`, `hooks/`) |
| `bin/` | helper scripts (`osd`, `battery-watch`, `powermenu`) called by absolute path from `config/sway/config` — not symlinked, not on `$PATH` |
| `system-config/`, `paludis-config/`, `kernelconfig`, `doc/` | read-only snapshots / notes — **not** symlinked; edits here do not propagate |

The full repo-path → live-path mapping is the `MAP` table in
[`apply.sh`](apply.sh), which is the source of truth for what gets linked.

## Reproducing on a new machine

Two entry points:

- **`bootstrap.sh`** — full setup on a bare Arch install: installs packages,
  links dotfiles (calls `apply.sh`), sets the login shell, enables services,
  bootstraps Vim plugins. Idempotent; re-runnable. This is what you want on a
  new laptop.
- **`apply.sh`** — just the dotfile symlinks (a subset of the above), for when
  the system is already set up and you only want the configs.

```sh
git clone <this-repo> ~/git/kannar/nunux
cd ~/git/kannar/nunux
./bootstrap.sh            # full machine setup  (./bootstrap.sh --help for flags)
# — or, dotfiles only —
./apply.sh               # ./apply.sh --dry-run to preview
```

`apply.sh` creates every symlink in its `MAP` table. It is **idempotent** and
safe to re-run any time: a path already pointing at this repo is left alone
(`ok`), a stale/broken symlink is repointed, and a pre-existing *real* file is
renamed to `<path>.bak` before linking (`bak`).

### New-machine checklist

`bootstrap.sh` automates the safe, host-agnostic steps and prints the rest as a
checklist when it finishes. The parts that **cannot** be automated (they are
disk-, hardware-, or secret-specific) and that you must do by hand:

- **Hardware packages.** Core lists are hardware-agnostic; machine-specific AUR
  packages (currently the Tuxedo drivers + control center) live in
  `system-config/pkglist-aur-hardware.txt`. `bootstrap.sh` prompts before
  installing them — only accept on Tuxedo hardware, otherwise install the right
  drivers for the new machine instead.
- **`/etc` files.** `system-config/system/*` are read-only snapshots, never
  symlinked. Copy them into place by hand — but **regenerate `fstab` and
  `crypttab`** for the new disk (their UUIDs/LUKS setup differ). Fix the
  hardcoded username + repo path in `pacman.d/hooks/pkglist-refresh.hook` before
  copying it to `/etc/pacman.d/hooks/`.
- **Secrets.** Create `~/.local/share/secrets.env` (sourced by `zprofile` if
  present). Nothing secret is tracked here.
- **GPG key.** `gitconfig` signs commits by default — import your secret key or
  commits fail.
- **SSH keys.** Restore `~/.ssh/` keys; git pushes over SSH (`github:`/`clever:`
  URL rewrites).
- **Coursier/JVM.** Run `cs setup` — `zprofile` expects a coursier-installed JDK
  on `PATH`.

Other things to know, handled automatically by `bootstrap.sh` but listed for the
dotfiles-only path:

- **Skip-worktree files.** `npmrc`, `wgetpaste.conf`, and `zprofile` are
  secret-prone templates pinned locally so accidental edits stay out of
  `git status`. The `--skip-worktree` flag is per-checkout, so re-pin after a
  fresh clone:
  ```sh
  git update-index --skip-worktree npmrc wgetpaste.conf zprofile
  ```
- **Vim plugins** use Vundle: open `vim` and run `:PluginInstall`.

## Adding a config to the repo

1. Move it to its mirrored location — under `config/` for a `~/.config` file,
   or bare at the repo root for a home dotfile.
2. Add a `"repo/path  $HOME/live/path"` line to the `MAP` table in `apply.sh`.
3. `./apply.sh` to link it, then `git add` + commit.

Secret-prone files additionally get `git update-index --skip-worktree <path>`
and a note in `.gitignore`.

## More

See [`CLAUDE.md`](CLAUDE.md) for the per-file conventions worth knowing before
editing (Vundle, signed-commits-by-default git, the `mtmux` SSH-as-root caveat,
the statusline contract, commit style, …).
