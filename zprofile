if [ $(tty) = "/dev/tty1" ]; then
  startx
fi

xhost +

alias la='ls -A'
alias l='ls -CF'
alias ll='ls -alF'
alias ohmyzsh="vim ~/.oh-my-zsh"
alias slack="flatpak run com.slack.Slack &"
alias spotify="flatpak run com.spotify.Client &"
alias trans="/opt/translator/trans"
alias zoom="flatpak run us.zoom.Zoom &"
alias zshconfig="vim ~/.zshrc"

feh --bg-scale /home/kannar/Pictures/V4.png
