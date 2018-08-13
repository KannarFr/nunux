ZSH_THEME="aussiegeek"

plugins=(git archlinux autojump github history yarn npm sbt)

source $ZSH/oh-my-zsh.sh

# autojump conf
[[ -s /home/kannar/.autojump/etc/profile.d/autojump.sh ]] && source /home/kannar/.autojump/etc/profile.d/autojump.sh
autoload -U compinit && compinit -u

stty start undef stop undef

eval $(keychain --eval --agents ssh -Q --quiet id_rsa)
