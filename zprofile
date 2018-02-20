[[ $HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
export PATH="$HOME/.cargo/bin:$PATH"

if [ $(tty) = "/dev/tty1" ]; then
  startx
fi
