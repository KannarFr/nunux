# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles and system configuration. There is **no build, no tests, no lint** — most files here are the *real* configs the live system reads, exposed via symlinks from `$HOME` (and a few archival snapshots from `/etc`). Most edits are one-line tweaks; the value is in the conventions below.

## Deployment model: symlinks, not copies

For most tracked files, the live path under `$HOME` (or `~/.config`) is a symlink pointing into this repo. Editing the file here **is** editing the live config — no separate sync step. Verify with `ls -la <live-path>` before assuming.

| Repo path | Live path (symlinked) |
|---|---|
| `bashrc`, `zshrc`, `zprofile`, `vimrc`, `gitconfig`, `psqlrc` | `~/.<name>` |
| `tmux` | `~/.tmux.conf` |
| `bat` | `~/.bat.conf` |
| `sshconfig` | `~/.ssh/config` |
| `gpg-agent.conf` | `~/.gnupg/gpg-agent.conf` |
| `swayconfig` | `~/.config/sway/config` |
| `waybar/` | `~/.config/waybar` |
| `starship.toml` | `~/.config/starship.toml` |
| `htoprc` | `~/.config/htop/htoprc` |
| `mimeapps.list` | `~/.config/mimeapps.list` |
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

## Critical: the skip-worktree files

`npmrc`, `wgetpaste.conf`, and `zprofile` are tracked but pinned locally with `git update-index --skip-worktree` (verify: `git ls-files -v | grep '^S'`). The `.gitignore` header explains why: these contain or risk leaking secrets. Note that `zprofile` is *also* symlinked from `~/.zprofile`, so edits to the symlink land in this repo's working tree — skip-worktree just hides them from `git status` so they aren't accidentally committed.

Rules:
- Don't edit these files here as part of normal work — drift is invisible to `git status`.
- To deliberately update the committed placeholder (non-secret line), use `git add -f <file>`.
- Secrets themselves load from `~/.local/share/secrets.env` via `zprofile` (sourced if present), never from anything tracked here.
- `npmrc` and `wgetpaste.conf` currently have **no** live `$HOME` copy on this machine — they're carried as templates for future use.

## Adding a new tracked dotfile

When the user asks to bring a config under version control:
1. `mv ~/.config/<thing> /home/kannar/git/kannar/nunux/<thing>`
2. `ln -s /home/kannar/git/kannar/nunux/<thing> ~/.config/<thing>`
3. `git add` + commit.

If the file may contain secrets, also `git update-index --skip-worktree <thing>` and add a note to `.gitignore` next to the existing entries.

## Conventions worth knowing before editing

- **Vim plugins use Vundle**, not vim-plug or lazy.nvim — adding a plugin means a `Plugin '...'` line inside the `vundle#begin/end` block in `vimrc`, then `:PluginInstall`. The `set nocompatible` at the very top is required for Vundle to parse the file.
- **`gitconfig` is signed-commits-by-default** (`commit.gpgsign = true`) and rebases on pull. Don't suggest changes that assume merge-pull or unsigned commits.
- **`gitconfig` has URL rewrites**: `clever:foo/bar` → Clever Cloud GitLab, `github:foo/bar` → GitHub over SSH. Preserve these when editing.
- **`zshrc` is the source of truth for the interactive shell**, `bashrc` is minimal — most aliases/exports go in `zshrc`. The prompt itself comes from `starship.toml` (zshrc only does `eval "$(starship init zsh)"`).
- **`mtmux`** opens a tiled tmux window with synchronized SSH sessions to every host listed in its argument file, **as root**. Treat changes as security-sensitive.
- **`claude/statusline.sh`** reads JSON from stdin (Claude Code passes session info this way), uses `jq`, emits ANSI single-line output. Context-bar thresholds: `<50` green, `<80` yellow, else red. It's wired in via `claude/settings.json` (`statusLine.command`).
- **`claude/commands/*.md`** are user-level slash commands (`/commit`, `/mr`, `/pr`, `/review`, etc.); **`claude/agents/*.md`** are user-level subagents. New ones can be added by dropping a markdown file in the right dir — the symlink makes it live immediately.

## Commit style

Recent log uses lowercase, scoped, terse subjects: `vim: drop vim-be-good (nvim-only)`, `vim: silence coc.nvim startup warning`, `remove unused dunstrc and sbtconfig`. Match that. No body unless the *why* is non-obvious.
