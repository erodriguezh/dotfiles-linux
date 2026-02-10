# starship.sh — Initialize Starship prompt
# Sourced via ~/.bashrc -> ~/.config/bashrc.d/*.sh
#
# Config lives at ~/.config/starship/starship.toml (symlinked from repo).
# Starship defaults to ~/.config/starship.toml, so we set STARSHIP_CONFIG.

if command -v starship &>/dev/null; then
    export STARSHIP_CONFIG="${HOME}/.config/starship/starship.toml"
    eval "$(starship init bash)"
fi
