#!/bin/bash

# Perform non‑destructive updates of installed components created by
# the unified setup script.  This includes updating Homebrew and its
# packages, updating Node.js to the latest LTS via NVM, updating the
# installed Python version via pyenv (within the same minor series),
# pulling the latest dotfiles repository and upgrading Oh My Zsh.

set -euo pipefail

echo "🔄 Starting update of dev environment components..."

# Update Homebrew and installed packages
if command -v brew &>/dev/null; then
    echo "Updating Homebrew..."
    brew update
    echo "Upgrading Homebrew packages..."
    brew upgrade
    echo "Cleaning up Homebrew..."
    brew cleanup
else
    echo "Homebrew not found; skipping brew updates."
fi

# Update Node.js via NVM
if command -v nvm &>/dev/null; then
    echo "Updating Node.js to the latest LTS via NVM..."
    # Install latest LTS version and set default
    nvm install --lts
    nvm alias default node
    echo "Upgrading global npm packages (yarn, typescript, nodemon, create-react-app)..."
    npm update -g yarn typescript nodemon create-react-app || true
else
    echo "NVM not detected; skipping Node.js update."
fi

# Update Python via pyenv
if command -v pyenv &>/dev/null; then
    # Determine current global Python version
    current_py="$(pyenv global 2>/dev/null || true)"
    if [[ -n "$current_py" ]]; then
        echo "Checking for newer patch version of Python $current_py..."
        # Extract major.minor (e.g. 3.12) and find highest available patch
        base_version="${current_py%.*}"
        latest_patch=$(pyenv install --list | grep -E "^\s*$base_version\.[0-9]+$" | tail -1 | xargs || true)
        if [[ -n "$latest_patch" && "$latest_patch" != "$current_py" ]]; then
            echo "Installing newer Python version $latest_patch via pyenv..."
            pyenv install "$latest_patch" && pyenv global "$latest_patch"
        fi
    fi
    echo "Upgrading pip and installed Python packages..."
    pip install --upgrade pip virtualenv black flake8 pytest requests || true
else
    echo "pyenv not detected; skipping Python update."
fi

# Update dotfiles repository
if [[ -d "$HOME/dotfiles/.git" ]]; then
    echo "Pulling latest changes in dotfiles repository..."
    git -C "$HOME/dotfiles" pull --ff-only || true
fi

# Update Oh My Zsh
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "Updating Oh My Zsh..."
    git -C "$HOME/.oh-my-zsh" pull --ff-only || true
fi

echo "✅ Update complete.  You may need to restart your terminal for all changes to take effect."