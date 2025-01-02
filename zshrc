
autoload -Uz compinit colors vcs_info
compinit -u

# vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=(precmd_vcs_info)
zstyle ':vcs_info:*' actionformats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{3}|%F{1}%a%F{5}]%f '
zstyle ':vcs_info:*' formats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{5}]%f '
zstyle ':vcs_info:(sv[nk]|bzr):*' branchformat '%b%F{1}:%F{3}%r'
zstyle ':vcs_info:*' enable git hg bzr svn

## Reload vcs_info stuff on precmd and ensure gpg is running
precmd(){
    vcs_info
    [[ $(tty) = /dev/pts/* ]] && print -Pn "\e]0;%n@%M:%~\a"
}

# z conf
[[ -r "/usr/share/z/z.sh" ]] && source /usr/share/z/z.sh

source /etc/profile

stty start undef stop undef

# autosuggest
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Setup GPG env
unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"
fi
export GPG_TTY=$(tty)
gpg-connect-agent updatestartuptty /bye >/dev/null

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"

# Basic settings
HISTFILE=~/.histfile
HISTSIZE=16192
SAVEHIST=16192
export EDITOR=/usr/bin/vim
export PAGER=/usr/bin/less
umask 022

# Completions

## format all messages not formatted in bold prefixed with ----
zstyle ':completion:*' format '%B---- %d%b'
## format descriptions (notice the vt100 escapes)
zstyle ':completion:*:descriptions'    format $'%{\e[0;31m%}completing %B%d%b%{\e[0m%}'
## bold and underline normal messages
zstyle ':completion:*:messages' format '%B%U---- %d%u%b'
## format in bold red error messages
zstyle ':completion:*:warnings' format "%B$fg[red]%}---- no match for: $fg[white]%d%b"
## let's use the tag name as group name
zstyle ':completion:*' group-name ''
## activate menu selection
zstyle ':completion:*' menu select=long
## activate approximate completion, but only after regular completion (_complete), prefer expansion
zstyle ':completion:::::' completer _expand _complete _ignored _correct _approximate
## limit to 2 errors
zstyle ':completion:*:approximate:*' max-errors 2
## Better handling of long output
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more %s

# Drop completions cache
rm -f ~/.zcompdump

# Enable a few things
colors

setopt autocd appendhistory extendedglob nonomatch promptsubst notify
# Add commands to history as they are entered, don't wait for shell to exit
setopt INC_APPEND_HISTORY
# Also remember command start time and duration
setopt EXTENDED_HISTORY
# Do not keep duplicate commands in history
setopt HIST_IGNORE_ALL_DUPS
# Do not remember commands that start with a whitespace
setopt HIST_IGNORE_SPACE
# Correct spelling of all arguments in the command line
setopt CORRECT_ALL

# Aliases
alias j='z'
alias cat='bat'
alias gapa='git add -p'
alias gc='git commit'
alias gss='git status'
alias ls='ls --color=auto'
alias lo='ls -ogh'
alias grep='grep --colour=auto'
alias la='ls -A'
alias l='ls -CF'
alias ll='ls -alFh'

# No beep ever
unsetopt beep

# Do not accidentally overwrite files with >
setopt noclobber

# Prompts
PROMPT='%M %{${fg[blue]}%}%~ ${vcs_info_msg_0_}%# %{${reset_color}%}'
RPROMPT="%{${fg[blue]}%}[%{${fg[red]}%}%?%{${fg[blue]}%}][%{${fg[red]}%}%*%{${fg[blue]}%} - %{${fg[red]}%}%D{%d/%m/%Y}%{${fg[blue]}%}]%{${reset_color}%}"

if [ "$EUID" = "0" ] || [ "$USER" = "root" ] ; then
    PROMPT="%{${fg_bold[red]}%}${PROMPT}"
else
    PROMPT="%{${fg_bold[green]}%}%n@${PROMPT}"
fi

# Bindkeys
typeset -g -A key
bindkey '^I' complete-word # complete on tab, leave expansion to _expand
#WORDCHARS=${WORDCHARS//[&=\/;!#%{]}
#WORDCHARS=${WORDCHARS//[&=\  ;!#%{]}
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

#bindkey -v
bindkey -e
bindkey "\e[1~" beginning-of-line # Home
bindkey "\e[4~" end-of-line # End
bindkey "\e[5~" beginning-of-history # PageUp
bindkey "\e[6~" end-of-history # PageDown
bindkey "\e[2~" quoted-insert # Ins
bindkey "\e[3~" delete-char # Del
bindkey "\e[5C" forward-word
bindkey "\eOc" emacs-forward-word
bindkey "\e[5D" backward-word
bindkey "\eOd" emacs-backward-word
bindkey "\e\e[C" forward-word
bindkey "\e\e[D" backward-word
bindkey "\e[Z" reverse-menu-complete # Shift+Tab

# fzf
#[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
source <(fzf --zsh)

export BAT_CONFIG_PATH=$HOME/.bat.conf
export PATH=$PATH:$HOME/.config/composer/vendor/bin
export PATH=$PATH:$HOME/.npm-global/bin
#export PATH=$PATH:"$(ruby -e 'print Gem.user_dir')/bin"
export PATH=$PATH:$HOME/.cargo/bin
export SSH_KEY_PATH="~/.ssh/rsa_id"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH=${PATH}:${HOME}/.pulsarctl/plugins

eval "$(starship init zsh)"
eval "$(direnv hook zsh)"
