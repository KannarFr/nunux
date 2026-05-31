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

## Applying on a new machine

```sh
git clone <this-repo> ~/git/kannar/nunux
cd ~/git/kannar/nunux
./apply.sh
```

`apply.sh` creates every symlink in its `MAP` table. It is **idempotent** and
safe to re-run any time:

- a path already pointing at this repo is left alone (`ok`),
- a stale or broken symlink is repointed,
- a pre-existing *real* file is renamed to `<path>.bak` before linking (`bak`).

Preview without touching anything:

```sh
./apply.sh --dry-run
```

After applying, a few things live outside the symlink model:

- **Secrets** load from `~/.local/share/secrets.env`, sourced by `zprofile` if
  present. Nothing secret is tracked here — create that file by hand.
- **Skip-worktree files.** `npmrc`, `wgetpaste.conf`, and `zprofile` are secret-prone
  templates pinned locally so accidental edits stay out of `git status`. The
  `--skip-worktree` flag is per-checkout, so re-pin after a fresh clone:
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
