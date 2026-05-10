# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles and system configuration. There is **no build, no tests, no lint** — files here are checked-in copies of configs that live elsewhere on the machine. Most edits are one-line tweaks; the value is in the conventions below.

## Where each tracked file actually lives

The repo is not symlinked into place. Files are hand-synced between the live location and this directory (recent history shows "sync drifted dotfiles from $HOME" commits). When asked to edit, default to editing **here**, then mention to the user that the live copy needs the same change — unless the file is in the skip-worktree set (see below).

| Repo path | Live path |
|---|---|
| `bashrc`, `zshrc`, `zprofile`, `vimrc`, `tmux`, `gitconfig`, `psqlrc`, `bat`, `npmrc`, `wgetpaste.conf` | `$HOME/.<name>` (or `~/.bat.conf` for `bat`) |
| `sshconfig` | `$HOME/.ssh/config` |
| `gpg-agent.conf` | `$HOME/.gnupg/gpg-agent.conf` |
| `swayconfig` | `$HOME/.config/sway/config` |
| `waybar/*` | `$HOME/.config/waybar/` |
| `claude/statusline.sh` | referenced from `$HOME/.claude/settings.json` |
| `system-config/system/*` | `/etc/*` (root-owned) |
| `paludis-config/*` | `/etc/paludis/*` (Paludis is the Exherbo/Gentoo-style package manager — confirms this is/was an Exherbo box; current host is Arch per `uname`, so this dir may be archival) |
| `kernelconfig` | `/usr/src/linux/.config` (kernel build config snapshot) |

## Critical: the skip-worktree files

`npmrc`, `wgetpaste.conf`, and `zprofile` are tracked but pinned locally with `git update-index --skip-worktree` (verify with `git ls-files -v | grep '^S'`). The `.gitignore` header explains why: these contain or risk leaking secrets, so the **placeholder version stays in the repo** while the real values live in `$HOME`.

Implications:
- Do **not** edit these three files in this repo as part of normal work — Git ignores changes to them and the user will be confused.
- The user edits the `$HOME` copies directly.
- To deliberately update the in-repo placeholder (e.g., add a new non-secret line), use `git add -f <file>`.
- Secrets themselves load from `~/.local/share/secrets.env` via `zprofile`, never from anything tracked here.

## Conventions worth knowing before editing

- **Vim plugins use Vundle**, not vim-plug or lazy.nvim — adding a plugin means a `Plugin '...'` line inside the `vundle#begin/end` block in `vimrc`, then `:PluginInstall`. The `set nocompatible` at the very top is required for Vundle to parse the file (per a recent commit).
- **`gitconfig` is signed-commits-by-default** (`commit.gpgsign = true`) and rebases on pull. Don't suggest changes that assume merge-pull or unsigned commits.
- **`gitconfig` has URL rewrites**: `clever:foo/bar` → Clever Cloud GitLab, `github:foo/bar` → GitHub over SSH. Preserve these when editing.
- **`zshrc` is the source of truth for the interactive shell**, `bashrc` is minimal — most aliases/exports go in `zshrc`.
- **`mtmux`** (the only executable script besides `waybar/cpu.sh` and `claude/statusline.sh`) opens a tiled tmux window with synchronized SSH sessions to every host listed in its argument file, as **root**. Treat any change to it as security-sensitive.
- **`claude/statusline.sh`** reads JSON from stdin (Claude Code passes session info this way), uses `jq`, and emits ANSI-colored single-line output. The threshold logic (`<50` green, `<80` yellow, else red) is for the context-window bar.

## Commit style

Recent log uses lowercase, scoped, terse subjects: `vim: drop vim-be-good (nvim-only)`, `vim: silence coc.nvim startup warning`, `remove unused dunstrc and sbtconfig`. Match that. No body unless the *why* is non-obvious.
