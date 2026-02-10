# aliases.sh — Quality-of-life shell aliases
# Sourced via ~/.bashrc -> ~/.config/bashrc.d/*.sh

# Editor
alias n='nvim'

# Listing
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# System
alias sdn='sudo shutdown -h now'
alias reboot='sudo reboot'
