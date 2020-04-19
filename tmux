# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

#set -g status off

# enable tmux session autosaving
set -g @continuum-restore 'on'
set -g @continuum-boot 'on'
set -g @continuum-save-interval '2'

# auto rerun program after tmux ressurect
set -g @resurrect-processes 'ssh psql'
set -g @resurrect-capture-pane-contents 'on'

# Other examples:
# set -g @plugin 'github_username/plugin_name'
# set -g @plugin 'git@github.com/user/plugin'
# set -g @plugin 'git@bitbucket.com/user/plugin'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'

set -g default-command "${SHELL}"
set -g base-index 1
set-option -ga terminal-overrides ",xterm-256color:Tc"
set-option -sg escape-time 10
set-option -g status-keys vi
set-option -g visual-bell off
set-option -g set-titles on
set-option -g set-titles-string '#H:#S.#I.#P #W #T' # window number,program name,active (or not)
set-option -g status-justify left
set-option -g status-style fg=green
set-option -g status-left-length 40
set-option -g status-position top
set-option -g pane-active-border-style bg=yellow,fg=black
set-option -g pane-border-style fg=green
set-option -g message-style fg=yellow
#set-window-option -g mode-keys emacs

## Start the background colors for interface
### Here is the dark theme
#set-option -g pane-border-bg black
#set-option -g status-bg black
#set-option -g message-bg black
#setw -g window-status-bg black
### Here is the light theme
set-option -g pane-border-style bg=white
set-option -g status-style bg=white
set-option -g message-style bg=white
setw -g window-status-style bg=white
setw -g window-status-current-style fg=green

## Dark theme
#set -g status-left '#[fg=red]#H#[fg=green]:#[fg=white]#S #[fg=green] [#[default]'
## Light theme
set -g status-left '#[fg=red]#H#[fg=green]:#[fg=blue]#S #[fg=green] continuum: #{continuum_status} [#[default]'

## Dark theme
#set -g status-right '#[fg=green]][ (#T) #[fg=blue]%Y-%m-%d #[fg=white]%H:%M#[default]'
## Light theme
set -g status-right '#[fg=green]][ (#T) #[fg=blue]%Y-%m-%d #[fg=black]%H:%M#[default]'

set -g status-right-length 100
set -g history-limit 165536

# Bindings
bind n next-window
bind p previous-window
bind h split-window -h -c "#{pane_current_path}"
bind v split-window -v -c "#{pane_current_path}"
bind g choose-tree
bind-key C-m set-window-option synchronize-panes
# set-option -g prefix C-a
# unbind-key C-b
unbind-key C-n
# Log output to a text file on demand
bind P pipe-pane -o "cat >>~/tmux-#W.log" \; display "Toggled logging to ~/tmux-#W.log"
