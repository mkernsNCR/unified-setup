#!/bin/bash

# Validate the integrity of the unified development environment setup.  This
# script inspects the system to determine whether critical tools and
# configuration files are present and correctly configured.  It does not
# modify the system.

set -euo pipefail

missing() {
    echo "❌ $1 is missing."
}
present() {
    echo "✅ $1 detected."
}

echo "🔍 Validating unified dev environment installation..."

# Check Xcode CLI tools
if xcode-select -p &>/dev/null; then
    present "Xcode Command Line Tools"
else
    missing "Xcode Command Line Tools (run xcode-select --install)"
fi

# Check Homebrew
if command -v brew &>/dev/null; then
    present "Homebrew"
else
    missing "Homebrew package manager"
fi

# Verify packages from Brewfile
brewfile="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Brewfile"
if [[ -f "$brewfile" ]] && command -v brew >/dev/null 2>&1; then
    echo "Checking installed Homebrew packages..."
    # Check formulae
    while read -r pkg; do
        if brew list --formula | grep -Fxq "$pkg"; then
            present "Homebrew package $pkg"
        else
            missing "Homebrew package $pkg"
        fi
    done < <(awk '/^[[:space:]]*brew[[:space:]]+"[^"]+"/ {
        match($0, /"[^"]+"/);
        pkg=substr($0, RSTART+1, RLENGTH-2);
        print pkg
    }' "$brewfile")
    # Check casks
    while read -r cask_name; do
        if brew list --cask | grep -Fxq "$cask_name"; then
            present "Homebrew cask $cask_name"
        else
            missing "Homebrew cask $cask_name"
        fi
    done < <(awk '/^[[:space:]]*cask[[:space:]]+"[^"]+"/ {
        match($0, /"[^"]+"/);
        c=substr($0, RSTART+1, RLENGTH-2);
        print c
    }' "$brewfile")
fi

# Check Git configuration
if git config --global user.name &>/dev/null; then
    present "Git user.name ($(git config --global user.name))"
else
    missing "Git user.name"
fi
if git config --global user.email &>/dev/null; then
    present "Git user.email ($(git config --global user.email))"
else
    missing "Git user.email"
fi

# Check SSH key
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    present "SSH key (~/.ssh/id_ed25519)"
else
    missing "SSH key (~/.ssh/id_ed25519)"
fi

# Check Oh My Zsh and .zshrc
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    present "Oh My Zsh installation"
else
    missing "Oh My Zsh (directory ~/.oh-my-zsh)"
fi
if [[ -f "$HOME/.zshrc" ]]; then
    present ".zshrc file"
else
    missing ".zshrc file"
fi

# Check Node and NVM
if command -v node &>/dev/null; then
    present "Node.js ($(node --version))"
else
    missing "Node.js"
fi
if [[ -d "$HOME/.nvm" ]]; then
    present "NVM directory (~/.nvm)"
else
    missing "NVM directory (~/.nvm)"
fi

# Check Python and pyenv
if command -v python3 &>/dev/null; then
    present "Python ($(python3 --version))"
else
    missing "Python interpreter"
fi
if [[ -d "$HOME/.pyenv" ]]; then
    present "pyenv directory (~/.pyenv)"
else
    missing "pyenv directory (~/.pyenv)"
fi

# Check GUI applications in /Applications
for app in "PyCharm.app" "Google Chrome.app" "ChatGPT.app"; do
    if [[ -d "/Applications/$app" ]]; then
        present "$app"
    else
        missing "$app"
    fi
done

echo "🔎 Validation complete."