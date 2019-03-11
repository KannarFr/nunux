ZSH_THEME="kafeitu"

plugins=(git archlinux autojump github history yarn npm sbt)

source $ZSH/oh-my-zsh.sh

# autojump conf
[[ -s /home/kannar/.autojump/etc/profile.d/autojump.sh ]] && source /home/kannar/.autojump/etc/profile.d/autojump.sh
autoload -U compinit && compinit -u

stty start undef stop undef

#eval $(keychain --eval --agents ssh -Q --quiet id_rsa)

# Setup GPG env
export GPG_TTY=$(tty)
unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"
fi
gpg-connect-agent updatestartuptty /bye >/dev/null

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"
