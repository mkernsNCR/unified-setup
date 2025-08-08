#!/bin/bash

# Roll back changes made by the unified setup script.  This script
# attempts to restore configuration files from the most recent backup
# directory and remove installed tools and applications.  Use with
# caution: it may remove other Homebrew packages if not run carefully.

set -euo pipefail

BACKUP_ROOT="$HOME/.setup_backups"
STATE_FILE="$HOME/.setup_state"
LOG_FILE="$HOME/unified_setup.log"

FORCE=false

# Parse command line options
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# Simple prompt function.  Returns 0 (yes) or 1 (no).
prompt() {
    local message="$1"
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    read -rp "$message [y/N]: " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

echo "🧨 Starting rollback of unified dev environment setup..."
echo "All actions will be logged to $LOG_FILE"

# Restore backups of configuration files
restore_backups() {
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        echo "No backup directory found at $BACKUP_ROOT; nothing to restore."
        return
    fi
    # Find the most recent backup directory (lexicographically last)
    local latest_backup
    latest_backup=$(ls -1d "$BACKUP_ROOT"/* 2>/dev/null | sort | tail -n1 || true)
    if [[ -z "$latest_backup" ]]; then
        echo "No backup directories found in $BACKUP_ROOT; nothing to restore."
        return
    fi
    echo "Restoring configuration files from $latest_backup..."
    find "$latest_backup" -type f | while read -r backup_file; do
        local rel="${backup_file#$latest_backup/}"
        local dest="$HOME/$rel"
        # Ensure destination directory exists
        mkdir -p "$(dirname "$dest")"
        if prompt "Restore $(basename "$dest")?"; then
            cp -a "$backup_file" "$dest"
            echo "  Restored $dest"
        else
            echo "  Skipped restoring $dest"
        fi
    done
}

# Remove Homebrew packages and Homebrew itself
remove_homebrew() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is not installed. Skipping Homebrew removal."
        return
    fi
    echo "Removing Homebrew packages and Homebrew itself..."
    if prompt "Remove ALL Homebrew packages and Homebrew? (This affects all brew packages)"; then
        # Attempt to uninstall all Homebrew packages
        brew list -1 | while read -r pkg; do
            brew uninstall --force "$pkg" || true
        done
        # Run official uninstall script
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" || true
        echo "  Homebrew removal complete."
    else
        echo "  Skipped Homebrew removal."
    fi
}

# Remove dotfiles and symlinks
remove_dotfiles() {
    echo "Removing dotfiles and symlinks..."
    if prompt "Remove cloned dotfiles repository ($HOME/dotfiles)?"; then
        rm -rf "$HOME/dotfiles"
        echo "  Removed dotfiles directory."
    fi
    for file in .zshrc .gitconfig .zprofile; do
        if [[ -L "$HOME/$file" ]]; then
            if prompt "Remove symlink $HOME/$file?"; then
                rm -f "$HOME/$file"
                echo "  Removed symlink $file"
            fi
        fi
    done
}

# Remove SSH keys
remove_ssh_keys() {
    echo "Removing SSH keys..."
    if prompt "Remove SSH key (~/.ssh/id_ed25519)?"; then
        rm -f "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
        # Remove IdentityFile line from ssh config
        if [[ -f "$HOME/.ssh/config" ]]; then
            sed -i.bak '/IdentityFile ~/.ssh\/id_ed25519/d' "$HOME/.ssh/config" || true
        fi
        echo "  SSH keys removed."
    fi
}

# Remove GUI applications
remove_applications() {
    echo "Removing GUI applications..."
    local apps=("PyCharm.app" "ChatGPT.app" "Google Chrome.app")
    for app in "${apps[@]}"; do
        if [[ -d "/Applications/$app" ]]; then
            if prompt "Remove $app from /Applications?"; then
                sudo rm -rf "/Applications/$app"
                echo "  Removed $app"
            fi
        fi
    done
}

# Remove development environments
remove_dev_envs() {
    echo "Removing development environment directories (NVM, pyenv)..."
    if prompt "Remove NVM directory (~/.nvm)?"; then
        rm -rf "$HOME/.nvm"
        echo "  Removed ~/.nvm"
    fi
    if prompt "Remove pyenv directory (~/.pyenv)?"; then
        rm -rf "$HOME/.pyenv"
        echo "  Removed ~/.pyenv"
    fi
}

# Remove Oh My Zsh and revert default shell
cleanup_shell() {
    echo "Cleaning up shell configuration..."
    if prompt "Remove Oh My Zsh (~/.oh-my-zsh)?"; then
        rm -rf "$HOME/.oh-my-zsh"
        echo "  Removed ~/.oh-my-zsh"
    fi
    if prompt "Change default shell back to /bin/bash?"; then
        chsh -s /bin/bash "$USER" || true
        echo "  Default shell changed to /bin/bash"
    fi
}

# Remove state file and log
cleanup_state_and_logs() {
    if [[ -f "$STATE_FILE" ]]; then
        if prompt "Remove installation state file ($STATE_FILE)?"; then
            rm -f "$STATE_FILE"
            echo "  Removed $STATE_FILE"
        fi
    fi
    if [[ -f "$LOG_FILE" ]]; then
        if prompt "Remove log file ($LOG_FILE)?"; then
            rm -f "$LOG_FILE"
            echo "  Removed $LOG_FILE"
        fi
    fi
}

# Execute rollback steps
restore_backups
remove_dotfiles
remove_ssh_keys
remove_dev_envs
cleanup_shell
remove_applications
remove_homebrew
cleanup_state_and_logs

echo "✅ Rollback complete.  Please restart your terminal session."