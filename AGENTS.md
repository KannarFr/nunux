# Repository Guidelines

## Project Structure & Module Organization

This is a personal Arch Linux + Sway dotfiles repository. Most tracked files
are the live configuration through symlinks from `$HOME`.

- Root files such as `zshrc`, `vimrc`, `gitconfig`, and `tmux` map to home
  dotfiles.
- `config/` mirrors `~/.config/` (for example, `config/sway/config`).
- `claude/` contains the config linked to `~/.claude`; `bin/` contains helper
  scripts invoked by absolute path.
- `system-config/`, `paludis-config/`, `kernelconfig`, and `doc/` are
  snapshots or notes, not live symlinks. Update their live `/etc` counterparts
  separately when appropriate.

`apply.sh`'s `MAP` array is the source of truth for repo-path-to-live-path
links. Add an entry there whenever adding a tracked dotfile.

## Build, Test, and Development Commands

There is no build system, test suite, formatter, or linter. Validate changes
against the program that consumes the configuration.

- `./apply.sh --dry-run` previews symlink changes safely.
- `./apply.sh` creates or repairs the configured symlinks; real destination
  files are backed up as `<path>.bak`.
- `./bootstrap.sh --help` shows options for provisioning a fresh Arch machine.
- `./bootstrap.sh --no-aur` runs setup while skipping AUR packages.

Use `bash -n apply.sh bootstrap.sh bin/<script>` after editing Bash. Reload or
restart the affected user service/application to check configuration changes.

## Coding Style & Naming Conventions

Preserve each file format and existing local style. Shell scripts use Bash with
`set -euo pipefail`, two-space indentation, lowercase variables/functions, and
clear `kebab-case` script names in `bin/`. Keep changes narrow: many files are
live configs, so a one-line edit can affect the current session immediately.

Do not commit secrets. `npmrc`, `wgetpaste.conf`, and `zprofile` are
skip-worktree templates; deliberately update a non-secret placeholder with
`git add -f <file>`.

## Commit & Pull Request Guidelines

Use terse, lowercase subjects, usually scoped: `sway: adjust output scale` or
`chore(pkglist): add package`. Add a body only when the reason is not obvious.
Before submitting, review `git diff`, state affected live paths/services, and
include screenshots for visible Sway, Waybar, or notification changes. Call out
any manual `/etc`, secret, hardware, or service-restart steps.
