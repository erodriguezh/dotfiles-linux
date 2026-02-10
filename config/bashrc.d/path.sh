# path.sh — Ensure ~/.local/bin is in PATH
# Sourced via ~/.bashrc -> ~/.config/bashrc.d/*.sh

if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi
