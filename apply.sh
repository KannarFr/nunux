#!/usr/bin/env bash
#
# apply.sh — link every tracked dotfile in this repo to its live path.
#
# Idempotent: paths already pointing at this repo are left alone. A pre-existing
# *real* file is renamed to <path>.bak before linking; a stale symlink is just
# repointed. Run it after cloning on a new machine, or after adding an entry to
# the MAP table below.
#
#   ./apply.sh            link everything
#   ./apply.sh --dry-run  show what would happen, change nothing
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
case "${1:-}" in
  "")                 ;;
  --dry-run|-n)       DRY=1 ;;
  *) printf 'usage: %s [--dry-run|-n]\n' "${0##*/}" >&2; exit 2 ;;
esac

# repo-relative path  ->  live path. The config/ subtree mirrors ~/.config;
# the rest are home dotfiles with irregular names, so the mapping is explicit.
# Add a line here when you bring a new dotfile under version control.
#
# Not listed on purpose:
#   npmrc, wgetpaste.conf  — skip-worktree templates, no live copy (see .gitignore)
#   bin/, mtmux            — referenced by absolute path, never symlinked
#   system-config/, paludis-config/, kernelconfig, doc/  — read-only snapshots
MAP=(
  "bashrc                  $HOME/.bashrc"
  "zshrc                   $HOME/.zshrc"
  "zprofile                $HOME/.zprofile"
  "vimrc                   $HOME/.vimrc"
  "gitconfig               $HOME/.gitconfig"
  "psqlrc                  $HOME/.psqlrc"
  "tmux                    $HOME/.tmux.conf"
  "bat                     $HOME/.bat.conf"
  "sshconfig               $HOME/.ssh/config"
  "gpg-agent.conf          $HOME/.gnupg/gpg-agent.conf"
  "config/sway/config      $HOME/.config/sway/config"
  "config/swaylock/config  $HOME/.config/swaylock/config"
  "config/waybar           $HOME/.config/waybar"
  "config/starship.toml    $HOME/.config/starship.toml"
  "config/htop/htoprc      $HOME/.config/htop/htoprc"
  "config/mimeapps.list    $HOME/.config/mimeapps.list"
  "claude/statusline.sh    $HOME/.claude/statusline.sh"
  "claude/settings.json    $HOME/.claude/settings.json"
  "claude/commands         $HOME/.claude/commands"
  "claude/agents           $HOME/.claude/agents"
)

link() {
  local src="$REPO/$1" dst="$2"

  if [ ! -e "$src" ]; then
    printf '  MISS  %s (not in repo)\n' "$1"
    return
  fi
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    printf '  ok    %s\n' "${dst/#$HOME/\~}"
    return
  fi

  local parent; parent="$(dirname "$dst")"
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$parent"
    # gpg/ssh refuse a homedir more permissive than 700; mkdir honors umask (755)
    case "$parent" in "$HOME/.gnupg"|"$HOME/.ssh") chmod 700 "$parent" ;; esac
  fi

  if [ -L "$dst" ]; then
    # stale/broken symlink — not precious, just replace it
    [ "$DRY" -eq 0 ] && rm "$dst"
  elif [ -e "$dst" ]; then
    local bak="$dst.bak"
    [ -e "$bak" ] && bak="$dst.bak.$(date +%s)"
    printf '  bak   %s -> %s\n' "${dst/#$HOME/\~}" "${bak/#$HOME/\~}"
    [ "$DRY" -eq 0 ] && mv "$dst" "$bak"
  fi

  printf '  link  %s\n' "${dst/#$HOME/\~}"
  [ "$DRY" -eq 0 ] && ln -s "$src" "$dst"
  return 0
}

printf 'Linking dotfiles from %s%s\n' "$REPO" "$([ "$DRY" -eq 1 ] && echo '  (dry run)')"
for entry in "${MAP[@]}"; do
  read -r repo_path live_path <<< "$entry"
  link "$repo_path" "$live_path"
done
printf 'done.\n'
