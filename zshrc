autoload -Uz compinit colors vcs_info

# autojump conf
[[ -s /home/kannar/.autojump/etc/profile.d/autojump.sh ]] && source /home/kannar/.autojump/etc/profile.d/autojump.sh
compinit -u

stty start undef stop undef

export GPG_TTY=$(tty)
# Setup GPG env
unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"
fi
gpg-connect-agent updatestartuptty /bye >/dev/null

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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

# Aliases
alias gapa='git add -p'
alias gc='git commit'
alias gss='git status'
alias ls='ls --color=auto'
alias lo='ls -ogh'
alias grep='grep --colour=auto'
alias la='ls -A'
alias l='ls -CF'
alias ll='ls -alFh'
alias slack="flatpak run com.slack.Slack &"
alias spotify="flatpak run com.spotify.Client &"
alias zoom="flatpak run us.zoom.Zoom &"

# VCS info
zstyle ':vcs_info:*' actionformats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{3}|%F{1}%a%F{5}]%f '
zstyle ':vcs_info:*' formats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{5}]%f '
zstyle ':vcs_info:(sv[nk]|bzr):*' branchformat '%b%F{1}:%F{3}%r'
zstyle ':vcs_info:*' enable git hg bzr svn

## Reload vcs_info stuff on precmd and ensure gpg is running
precmd(){
    vcs_info
    [[ $(tty) = /dev/pts/* ]] && print -Pn "\e]0;%n@%M:%~\a"
}

# No beep ever
unsetopt beep

# Prompts
PROMPT='%M %{${fg[blue]}%}%~ ${vcs_info_msg_0_}%# %{${reset_color}%}'
RPROMPT="%{${fg[blue]}%}[%{${fg[red]}%}%?%{${fg[blue]}%}][%{${fg[red]}%}%*%{${fg[blue]}%} - %{${fg[red]}%}%D{%d/%m/%Y}%{${fg[blue]}%}]%{${reset_color}%}"

if [ "$EUID" = "0" ] || [ "$USER" = "root" ] ; then
    PROMPT="%{${fg_bold[red]}%}${PROMPT}"
else
    PROMPT="%{${fg_bold[green]}%}%n@${PROMPT}"
fi
