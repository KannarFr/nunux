#!/usr/bin/env bash
#
# bootstrap.sh — turn a bare Arch install into this desktop.
#
# apply.sh only symlinks dotfiles; this does everything else needed to
# reproduce the running environment: installs packages, links the dotfiles
# (via apply.sh), sets the login shell, enables services, and bootstraps Vim
# plugins. It is idempotent — safe to re-run; finished steps are skipped.
#
# Things it deliberately does NOT automate (host-/secret-specific — it prints
# them as a checklist at the end instead):
#   - copying system-config/system/* into /etc (fstab & crypttab are disk-specific)
#   - importing GPG / SSH keys (git here signs commits and pushes over SSH)
#   - creating ~/.local/share/secrets.env
#   - coursier / JVM setup
#
#   ./bootstrap.sh             run every step
#   ./bootstrap.sh --no-aur    skip AUR (yay bootstrap + foreign packages)
#   ./bootstrap.sh --help
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC="$REPO/system-config"
WITH_AUR=1

for arg in "$@"; do
  case "$arg" in
    --no-aur)     WITH_AUR=0 ;;
    -h|--help)    sed -n '2,/^set -euo/{/^set -euo/!p}' "$0" | sed 's/^# \{0,1\}//; s/^#//'; exit 0 ;;
    *) printf 'usage: %s [--no-aur]\n' "${0##*/}" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
ask()  { local r; read -r -p "  $1 [y/N] " r; [ "$r" = y ] || [ "$r" = Y ]; }

[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root (it will sudo when needed)" >&2; exit 1; }
command -v pacman >/dev/null || { echo "this script targets Arch (pacman not found)" >&2; exit 1; }

# 1. dotfile symlinks -------------------------------------------------------
say "Linking dotfiles (apply.sh)"
"$REPO/apply.sh"

# 2. re-pin skip-worktree templates (the flag is per-checkout) --------------
say "Pinning skip-worktree files"
git -C "$REPO" update-index --skip-worktree npmrc wgetpaste.conf zprofile 2>/dev/null \
  && echo "  pinned: npmrc wgetpaste.conf zprofile" \
  || warn "could not pin skip-worktree files (already pinned, or not a checkout?)"

# 3. official packages ------------------------------------------------------
say "Installing official packages (pkglist-pacman.txt)"
sudo pacman -S --needed - < "$SC/pkglist-pacman.txt" \
  || warn "pacman reported failures (a dropped/renamed package?) — continuing; re-run after fixing the list"

# 4. AUR helper + foreign packages ------------------------------------------
if [ "$WITH_AUR" -eq 1 ]; then
  if ! command -v yay >/dev/null; then
    say "Bootstrapping yay (AUR helper)"
    sudo pacman -S --needed --noconfirm git base-devel
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    ( cd "$tmp/yay" && makepkg -si --noconfirm )
    rm -rf "$tmp"
  fi
  say "Installing AUR packages (pkglist-aur.txt)"
  yay -S --needed - < "$SC/pkglist-aur.txt"

  if [ -s "$SC/pkglist-aur-hardware.txt" ]; then
    echo
    cat "$SC/pkglist-aur-hardware.txt" | sed 's/^/    /'
    if ask "Install the hardware-specific packages above (Tuxedo drivers)? Only on Tuxedo hardware —"; then
      yay -S --needed - < "$SC/pkglist-aur-hardware.txt"
      HW_INSTALLED=1
    else
      warn "skipped hardware packages — install the right drivers for this machine by hand"
    fi
  fi
else
  warn "--no-aur: skipping yay + AUR packages (claude-code, germinal, handy, vban, … not installed)"
fi

# 5. login shell ------------------------------------------------------------
say "Login shell"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]; then
  chsh -s /usr/bin/zsh && echo "  set to /usr/bin/zsh (re-login to take effect)" \
    || warn "chsh failed — set it by hand: chsh -s /usr/bin/zsh"
else
  echo "  already /usr/bin/zsh"
fi

# 6. services ---------------------------------------------------------------
unit_exists() { systemctl cat "$1" >/dev/null 2>&1; }
enable_sys() {
  for u in "$@"; do
    if unit_exists "$u"; then sudo systemctl enable "$u" || warn "could not enable $u"; else warn "skip $u (not installed)"; fi
  done
}
enable_usr() {
  for u in "$@"; do
    if systemctl --user cat "$u" >/dev/null 2>&1; then systemctl --user enable "$u" || warn "could not enable --user $u"; else warn "skip --user $u (not installed)"; fi
  done
}

say "Enabling system services"
# seat/login/desktop, networking, ssh, then security & container extras
enable_sys seatd.service gdm.service bluetooth.service iwd.service sshd.service \
           docker.service pcscd.socket osqueryd.service \
           clamav-freshclam.service clamav-daemon.service clamav-clamonacc.service
if [ "${HW_INSTALLED:-0}" -eq 1 ]; then
  enable_sys tccd.service tccd-sleep.service
fi

say "Enabling user services"
enable_usr swaync.service vban-emitter.service vban-receptor.service \
           wireplumber.service pipewire.socket pipewire-pulse.socket gnome-keyring-daemon.socket

# 7. default GDM session ----------------------------------------------------
# gdm depends on gnome-shell, so a gnome.desktop session exists and GDM
# defaults to it. Pin sway as this user's session in AccountsService so login
# lands in sway instead of GNOME. (Host-local state under /var/lib; the gear
# menu at the greeter writes the same file.)
say "Default session (sway)"
asf="/var/lib/AccountsService/users/$USER"
# /var/lib/AccountsService/users is 0700 root, so read/test it via sudo — and
# never blindly overwrite an existing file (GDM stores Language/Icon/etc there).
if sudo grep -q '^Session=sway$' "$asf" 2>/dev/null; then
  echo "  already sway"
elif sudo test -f "$asf"; then
  sudo sed -i -E '/^\[User\]/,$ { /^Session=/d }; /^\[User\]/a Session=sway' "$asf" \
    && echo "  set Session=sway in existing file" \
    || warn "could not patch $asf — pick Sway from the GDM gear menu instead"
else
  sudo install -Dm644 /dev/stdin "$asf" <<EOF && echo "  pinned sway for $USER" \
    || warn "could not write $asf — pick Sway from the GDM gear menu instead"
[User]
Session=sway
XSession=
SystemAccount=false
EOF
fi

# 8. Vim / Vundle -----------------------------------------------------------
say "Vim plugins (Vundle)"
vundle="$HOME/.vim/bundle/Vundle.vim"
[ -d "$vundle" ] || git clone https://github.com/VundleVim/Vundle.vim.git "$vundle"
# coc.nvim is pinned in vimrc (Vundle skips it), so clone its release branch
# by hand — it ships a prebuilt build/index.js, no npm build needed.
coc="$HOME/.vim/bundle/coc.nvim"
[ -d "$coc" ] || git clone --depth 1 --branch release \
  https://github.com/neoclide/coc.nvim.git "$coc"
vim +PluginInstall +qall </dev/null >/dev/null 2>&1 && echo "  plugins installed" \
  || warn "run ':PluginInstall' inside vim by hand"

# 9. tmux / tpm -------------------------------------------------------------
say "tmux plugins (tpm)"
tpm="$HOME/.tmux/plugins/tpm"
[ -d "$tpm" ] || git clone https://github.com/tmux-plugins/tpm.git "$tpm"
"$tpm/bin/install_plugins" >/dev/null 2>&1 && echo "  plugins installed" \
  || warn "open tmux and press 'prefix + I' to install plugins by hand"

# 10. manual checklist ------------------------------------------------------
say "Done — remaining MANUAL steps (host-/secret-specific, not automated):"
cat <<'EOF'

  [ ] /etc files: copy system-config/system/* into place, but REGENERATE
      fstab & crypttab for THIS disk (UUIDs/LUKS differ). Safe to copy as-is:
      hostname, hosts, locale.conf, vconsole.conf, nsswitch.conf,
      systemd/zram-generator.conf, dracut.conf.d/*.
      Fix the username + repo path in pacman.d/hooks/pkglist-refresh.hook,
      then: sudo cp .../pkglist-refresh.hook /etc/pacman.d/hooks/

  [ ] Secrets: create ~/.local/share/secrets.env (sourced by zprofile).

  [ ] GPG key: import your secret key (git signs commits by default), e.g.
      gpg --import < key.asc

  [ ] SSH keys: restore ~/.ssh/ keys — git pushes over SSH (github:/clever: rewrites).

  [ ] Coursier/JVM: run 'cs setup' (zprofile expects a coursier-installed JDK).

  [ ] Reboot into the gdm → sway session.
EOF
