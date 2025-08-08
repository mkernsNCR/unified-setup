#!/bin/bash

# Unified Mac Development Environment Setup
#
# This script combines the functionality of the original
# mac‑dev‑environment install wizard and the custom dotfiles repository
# into a single, cohesive installer.  It emphasises safety, idempotency
# and user experience.  Run with --dry‑run to preview actions without
# modifying the system.

set -euo pipefail

# -----------------------------------------------------------------------------
#  Global configuration
# -----------------------------------------------------------------------------

readonly SCRIPT_VERSION="1.0.0"

# Repository containing personal dotfiles.  You can override this by
# exporting DOTFILES_REPO before running the script.  The dotfiles
# repository should contain at least a `.zshrc` and `.gitconfig`.  If
# unset or empty then dotfiles installation is skipped.
readonly DOTFILES_REPO_DEFAULT="https://github.com/mkernsNCR/my-dotfiles.git"
DOTFILES_REPO="${DOTFILES_REPO:-$DOTFILES_REPO_DEFAULT}"

# Locations for logging and state tracking
readonly LOG_FILE="$HOME/unified_setup.log"
readonly STATE_FILE="$HOME/.setup_state"
readonly BACKUP_ROOT="$HOME/.setup_backups"
BACKUP_DIR=""

# Command line flags
DRY_RUN=false

# -----------------------------------------------------------------------------
#  Helper functions
# -----------------------------------------------------------------------------

# Print a timestamped log message.  All logs go to both stdout and
# LOG_FILE when not in dry‑run mode.  Levels: INFO, WARN, ERROR.
log() {
    local level="$1"; shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
    # Also echo to terminal for user visibility
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Output a command and execute it unless in dry‑run mode.  All
# commands should be passed as a single string argument to ensure
# proper quoting.
safe_execute() {
    local cmd="$1"
    log_info "Executing: $cmd"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY‑RUN] Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Create a timestamped backup of a file if it exists.  Backup
# directory is created on first invocation.  The backup preserves the
# relative path structure under BACKUP_ROOT.  Returns 0 even if the
# file does not exist.
backup_file() {
    local src="$1"
    if [[ ! -e "$src" ]]; then
        return 0
    fi
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
    fi
    local rel
    rel="${src#$HOME/}"
    local dest="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    log_info "Backed up $src to $dest"
}

# Validate that we're running on macOS.  Exits with error if not.
validate_system_state() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is intended to run on macOS. Exiting."
        exit 1
    fi
    # Check for approximate free disk space (>= 5 GB).  This is a
    # conservative threshold; you can adjust as necessary.
    local free_space
    free_space=$(df -Pk / | tail -1 | awk '{print $4}')
    # free_space is in kilobytes; require >5,000,000 (≈5GB)
    if [[ "$free_space" -lt 5000000 ]]; then
        log_warn "Less than 5 GB of free space available; installation may fail."
    fi
}

# Initialise logging: create or truncate LOG_FILE and redirect
# subsequent script output to it.  In dry‑run mode we still create
# LOG_FILE for consistency but we avoid redirecting output.
init_logging() {
    # Ensure log file exists and is truncated
    : > "$LOG_FILE"
    if [[ "$DRY_RUN" != "true" ]]; then
        # Redirect stdout and stderr to tee which writes to LOG_FILE and
        # passes through to terminal
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    log_info "Starting unified dev environment setup v$SCRIPT_VERSION"
    log_info "Log will be saved to $LOG_FILE"
}

# Load the installation state from STATE_FILE into an associative array
# called INSTALL_STATE.  Each line in STATE_FILE should have the form
# phase_name=complete.  If the file does not exist then the array is
# initialised empty.  Bash associative arrays require bash 4+.
declare -A INSTALL_STATE
load_installation_state() {
    if [[ -f "$STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                INSTALL_STATE["$key"]="$value"
            fi
        done < "$STATE_FILE"
        log_info "Loaded installation state from $STATE_FILE"
    fi
}

# Write a phase completion flag to STATE_FILE.  Existing state is
# preserved; the new key overwrites any previous entry for the phase.
save_phase_complete() {
    local phase="$1"
    INSTALL_STATE["$phase"]="complete"
    # Rewrite state file
    : > "$STATE_FILE"
    for key in "${!INSTALL_STATE[@]}"; do
        echo "$key=${INSTALL_STATE[$key]}" >> "$STATE_FILE"
    done
    log_info "Recorded completion of phase '$phase' in $STATE_FILE"
}

# Determine whether a phase has already completed.  Returns 0 (true) if
# the phase is marked complete; otherwise returns 1.
is_phase_complete() {
    local phase="$1"
    if [[ "${INSTALL_STATE[$phase]:-}" == "complete" ]]; then
        return 0
    fi
    return 1
}

# Execute a phase.  If the phase is already complete then a message is
# printed and the phase is skipped.  Otherwise the corresponding
# function is invoked.  On success the phase is marked complete.  On
# error the script aborts (and the global trap will perform cleanup).
execute_phase() {
    local phase_name="$1"
    local phase_func="$2"
    if is_phase_complete "$phase_name"; then
        log_info "Skipping phase '$phase_name' (already completed)"
        return 0
    fi
    log_info "Starting phase: $phase_name"
    "$phase_func"
    save_phase_complete "$phase_name"
    log_info "Completed phase: $phase_name"
}

# Add a directory to PATH in the specified shell config file (e.g.,
# ~/.zprofile or ~/.zshrc).  This helper checks whether the directory
# exists and is not already present in PATH.  It also verifies that
# the export line does not already appear in the file.  A backup of
# the file is taken before modification.
add_to_path_file() {
    local dir="$1"; shift
    local rc_file="$1"
    local export_line="export PATH=\"$dir:\$PATH\""
    if [[ ! -d "$dir" ]]; then
        log_warn "Skipping addition of $dir to PATH – directory does not exist"
        return 0
    fi
    # Check if dir already in PATH
    if echo "$PATH" | tr ':' '\n' | grep -Fxq "$dir"; then
        log_info "$dir is already in PATH"
    else
        # Check if export_line already present in file
        if [[ -f "$rc_file" ]] && grep -Fq "$export_line" "$rc_file"; then
            log_info "$dir PATH export already present in $rc_file"
        else
            backup_file "$rc_file"
            echo "$export_line" >> "$rc_file"
            log_info "Added $dir to PATH in $rc_file"
        fi
    fi
}

# Global cleanup handler.  This function is called on any error or
# interrupt.  It performs necessary unmounts and temporary file
# deletions and logs the outcome.  The first argument specifies the
# exit code; default is 1.  It does not call exit if running in
# subshell; instead the caller should exit.
cleanup_and_exit() {
    local exit_code="${1:-1}"
    log_info "Performing cleanup..."
    # Unmount any DMG volumes that match known patterns
    for volume in $(mount | grep -o '/Volumes/[^[:space:]]*' 2>/dev/null || true); do
        if [[ "$volume" =~ ^/Volumes/(ChatGPT|PyCharm|GoogleChrome) ]]; then
            log_info "Unmounting $volume"
            hdiutil detach "$volume" -quiet 2>/dev/null || true
        fi
    done
    # Remove temporary files created by download/installation
    rm -f /tmp/setup_temp_* 2>/dev/null || true
    if [[ $exit_code -eq 0 ]]; then
        log_info "Setup completed successfully!"
    else
        log_error "Setup failed with exit code $exit_code"
    fi
    exit "$exit_code"
}

# Register global trap for ERR, INT and TERM
trap 'cleanup_and_exit 1' ERR INT TERM

# -----------------------------------------------------------------------------
#  Phase functions
# -----------------------------------------------------------------------------

# Phase: system_prerequisites
# Install Xcode Command Line Tools and Homebrew.  Create the default
# Brewfile if not present and install packages.  Apple Silicon PATH
# modifications are handled via .zprofile.
install_system_prerequisites() {
    # Install Xcode CLI if not installed
    if xcode-select -p &>/dev/null; then
        log_info "Xcode Command Line Tools already installed."
    else
        echo "📥 Installing Xcode Command Line Tools..."
        echo "⚠️  A dialog may appear – please click 'Install' to continue."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would run: xcode-select --install"
        else
            xcode-select --install || true
            # Wait for installation to finish (up to 10 minutes)
            local timeout=600
            local elapsed=0
            while ! xcode-select -p &>/dev/null; do
                if [[ $elapsed -ge $timeout ]]; then
                    log_error "Xcode CLI tools installation timed out."
                    return 1
                fi
                sleep 5
                elapsed=$((elapsed + 5))
            done
        fi
        log_info "Xcode Command Line Tools installation complete!"
    fi

    # Install Homebrew if not installed
    if command -v brew &>/dev/null; then
        log_info "Homebrew already installed."
    else
        echo "📥 Installing Homebrew..."
        echo "⚠️  You may be prompted for your password during installation."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would run: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        else
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # For Apple Silicon machines ensure Homebrew is available on PATH
            if [[ "$(uname -m)" == "arm64" ]]; then
                # Append to .zprofile so it persists
                add_to_path_file "/opt/homebrew/bin" "$HOME/.zprofile"
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
        log_info "Homebrew installation complete!"
    fi

    # Update brew and install from Brewfile
    log_info "Updating Homebrew..."
    safe_execute "brew update"
    # Determine Brewfile path: prefer repository Brewfile, fallback to
    # script directory
    local brewfile
    brewfile="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Brewfile"
    if [[ -f "$brewfile" ]]; then
        log_info "Using Brewfile at $brewfile"
    else
        log_warn "Brewfile not found; creating a default Brewfile."
        if [[ "$DRY_RUN" != "true" ]]; then
            cat > "$brewfile" <<'BREWEOF'
# Basic Brewfile generated by setup script
brew "git"
brew "node"
brew "python@3.12"
brew "pyenv"
brew "nvm"
brew "wget"
brew "curl"
brew "tree"
brew "jq"
brew "defaultbrowser"

cask "visual-studio-code"
cask "iterm2"
cask "docker"
BREWEOF
        fi
    fi
    # Install packages defined in Brewfile
    safe_execute "brew bundle --file=\"$brewfile\""
}

# Phase: git_and_ssh
# Configure Git user information and generate an SSH key.  If the
# information already exists or the key exists, skip those steps.
configure_git_and_ssh() {
    # Prompt for Git user name and email if not configured.  Use
    # simple validation similar to the original script【318608987082410†L95-L99】.
    local git_name git_email
    if [[ -z "$(git config --global user.name 2>/dev/null || true)" ]]; then
        # Define a regular expression for a valid name.  Enclose the regex in
        # double quotes so that apostrophes do not break the surrounding
        # script syntax.
        local name_regex="^[a-zA-Z0-9 .'-]{1,100}$"
        while true; do
            read -rp "👤 Please enter your full name for Git commits: " git_name
            if [[ -n "$git_name" && "$git_name" =~ $name_regex ]]; then
                break
            fi
            echo "Invalid name. Use letters, numbers, spaces, dots, apostrophes and hyphens (max 100 characters)."
        done
        safe_execute "git config --global user.name \"$git_name\""
        log_info "Git user name set to $git_name"
    else
        log_info "Git user name already configured: $(git config --global user.name)"
    fi
    if [[ -z "$(git config --global user.email 2>/dev/null || true)" ]]; then
        while true; do
            read -rp "📧 Please enter your email address for Git commits: " git_email
            if [[ "$git_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            fi
            echo "Invalid email format. Please try again."
        done
        safe_execute "git config --global user.email \"$git_email\""
        log_info "Git email set to $git_email"
    else
        log_info "Git email already configured: $(git config --global user.email)"
    fi
    # Set sensible Git defaults
    safe_execute "git config --global init.defaultBranch main"
    safe_execute "git config --global pull.rebase false"

    # Generate or display SSH key
    local ssh_key_path="$HOME/.ssh/id_ed25519"
    if [[ -f "$ssh_key_path" ]]; then
        log_info "SSH key already exists at $ssh_key_path"
        echo "Your existing SSH public key:"; cat "$ssh_key_path.pub"
    else
        echo "🔐 Generating new ED25519 SSH key..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would generate SSH key at $ssh_key_path"
        else
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            ssh-keygen -t ed25519 -C "${git_email}" -f "$ssh_key_path" -N ""
            # Start ssh-agent
            eval "$(ssh-agent -s)"
            # Configure macOS keychain integration
            local ssh_config="$HOME/.ssh/config"
            if [[ ! -f "$ssh_config" ]] || ! grep -q "UseKeychain yes" "$ssh_config"; then
                cat <<'EOF' >> "$ssh_config"

# macOS keychain integration
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
                chmod 600 "$ssh_config"
            fi
            sleep 1
            ssh-add --apple-use-keychain "$ssh_key_path"
        fi
        log_info "SSH key created successfully."
        echo "🔑 Your new public key (add this to GitHub/GitLab):"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would display SSH public key"
        else
            cat "$ssh_key_path.pub"
        fi
        echo ""
        # Ask whether to upload to GitHub automatically
        read -rp "🌐 Upload this key to GitHub automatically? (y/N): " upload_choice
        if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
            upload_ssh_key_to_github
        fi
    fi
}

# Upload SSH public key to GitHub using a personal access token.  The
# function prompts for the token and a key title.  The token is
# validated with a basic regex (alphanumeric and underscore, 20–100
# characters).  If the upload fails, the user is advised to add the
# key manually.  Tokens are not stored on disk.
upload_ssh_key_to_github() {
    local token=""
    while true; do
        read -srp "Enter your GitHub personal access token (scope write:public_key): " token
        echo
        if [[ -z "$token" ]]; then
            echo "No token entered. Skipping upload."
            return
        fi
        if [[ ${#token} -ge 20 && ${#token} -le 100 && "$token" =~ ^[A-Za-z0-9_]+$ ]]; then
            break
        fi
        echo "Invalid token format. Tokens should be 20–100 characters of letters, numbers or underscores."
    done
    read -rp "Enter a descriptive name for this SSH key (e.g. '$(hostname)-$(date +%Y)'): " key_title
    local pub_key
    pub_key=$(<"$HOME/.ssh/id_ed25519.pub")
    log_info "Uploading SSH key to GitHub..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY‑RUN] Would call GitHub API to add key titled '$key_title'"
    else
        local response http_code
        response=$(curl -s -w '\n%{http_code}' -H "Authorization: token $token" \
            --data "{\"title\":\"$key_title\",\"key\":\"$pub_key\"}" \
            https://api.github.com/user/keys)
        http_code=$(echo "$response" | tail -n1)
        if [[ "$http_code" == "201" ]]; then
            log_info "SSH key successfully uploaded to GitHub!"
        else
            log_warn "Failed to upload SSH key to GitHub (HTTP $http_code). Please add it manually."
        fi
    fi
    # Clear token from memory
    unset token
}

# Phase: shell_configuration
# Install Oh My Zsh if necessary, back up and configure .zshrc with
# NVM and pyenv initialisation.  Also source any dotfiles if present.
setup_shell_configuration() {
    log_info "Setting up shell configuration..."
    # Install Oh My Zsh
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Oh My Zsh already installed."
    else
        echo "📥 Installing Oh My Zsh..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would run the Oh My Zsh installer"
        else
            RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
            # Install useful plugins if not already present
            mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
            if [[ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]]; then
                git clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
            fi
            if [[ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
                git clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
            fi
        fi
    fi

    # Backup existing shell config files
    backup_file "$HOME/.zshrc"
    backup_file "$HOME/.zprofile"

    # Generate a baseline .zshrc.  If a dotfiles repository will be
    # linked later it may override this file, but we still write it
    # here so that environment variables are set on first run.
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY‑RUN] Would write baseline .zshrc"
    else
        cat > "$HOME/.zshrc" <<'ZSHRC'
# Auto‑generated by unified setup script
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(
  git
  npm
  node
  yarn
  zsh-autosuggestions
  history-substring-search
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# NVM setup (Homebrew installation)
export NVM_DIR="$HOME/.nvm"
if command -v brew >/dev/null 2>&1 && brew list nvm >/dev/null 2>&1; then
  [ -s "$(brew --prefix nvm)/nvm.sh" ] && source "$(brew --prefix nvm)/nvm.sh"
  [ -s "$(brew --prefix nvm)/etc/bash_completion.d/nvm" ] && source "$(brew --prefix nvm)/etc/bash_completion.d/nvm"
fi

# pyenv setup
export PYENV_ROOT="$HOME/.pyenv"
if [ -d "$PYENV_ROOT/bin" ]; then
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi
ZSHRC
        log_info "Wrote baseline .zshrc"
    fi
}

# Phase: dotfiles
# Clone the dotfiles repository and link .zshrc and .gitconfig.  If
# DOTFILES_REPO is empty or "skip", this phase is skipped.  When
# linking, existing files are backed up and replaced by symlinks.
install_dotfiles() {
    if [[ -z "$DOTFILES_REPO" || "$DOTFILES_REPO" == "skip" ]]; then
        log_info "Skipping dotfiles installation (DOTFILES_REPO not set)"
        return
    fi
    log_info "Installing dotfiles from $DOTFILES_REPO"
    local dotfiles_dir="$HOME/dotfiles"
    if [[ -d "$dotfiles_dir/.git" ]]; then
        log_info "Dotfiles repository already exists; pulling latest changes"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would run: git -C $dotfiles_dir pull"
        else
            git -C "$dotfiles_dir" pull --ff-only || true
        fi
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would clone $DOTFILES_REPO into $dotfiles_dir"
        else
            git clone "$DOTFILES_REPO" "$dotfiles_dir" || {
                log_warn "Failed to clone dotfiles repository; skipping dotfiles installation"
                return
            }
        fi
    fi
    # Link .zshrc and .gitconfig if present
    for file in .zshrc .gitconfig; do
        if [[ -f "$dotfiles_dir/$file" ]]; then
            backup_file "$HOME/$file"
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY‑RUN] Would symlink $dotfiles_dir/$file to $HOME/$file"
            else
                ln -sf "$dotfiles_dir/$file" "$HOME/$file"
                log_info "Linked $file from dotfiles repository"
            fi
        fi
    done
}

# Phase: development_tools
# Install Node.js via NVM and Python via pyenv.  Versions are
# recorded to the state file upon completion.  Skip installation if
# tools already meet minimum version requirements.
install_development_tools() {
    # Ensure Homebrew is installed; brew list will error if not
    if ! command -v brew &>/dev/null; then
        log_error "Homebrew must be installed before development tools can be set up."
        return 1
    fi
    # Install Node.js using NVM
    if brew list nvm &>/dev/null; then
        export NVM_DIR="$HOME/.nvm"
        mkdir -p "$NVM_DIR"
        # Source NVM scripts
        local nvm_script="$(brew --prefix nvm)/nvm.sh"
        if [[ -f "$nvm_script" ]]; then
            # shellcheck source=/dev/null
            if [[ "$DRY_RUN" != "true" ]]; then
                # ensure we load nvm in current shell
                source "$nvm_script"
            fi
            if [[ -n "$(command -v nvm || true)" ]]; then
                # Determine current installed Node version (if any)
                local current_node="$(command -v node >/dev/null 2>&1 && node --version || echo '')"
                if [[ -n "$current_node" ]]; then
                    log_info "Node.js already installed ($current_node). Skipping installation."
                else
                    log_info "Installing latest LTS version of Node.js via NVM..."
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo "  [DRY‑RUN] Would run: nvm install --lts && nvm use --lts && nvm alias default node"
                    else
                        nvm install --lts
                        nvm use --lts
                        nvm alias default node
                    fi
                    log_info "Node.js installation complete!"
                fi
                # Install global npm packages
                log_info "Installing global npm packages (yarn, typescript, nodemon, create-react-app)..."
                safe_execute "npm install -g yarn typescript nodemon create-react-app"
            else
                log_warn "nvm command is unavailable after sourcing. Please check NVM installation."
            fi
        else
            log_warn "NVM script not found at $nvm_script; skipping Node.js installation"
        fi
    else
        log_warn "NVM not installed via Homebrew; skipping Node.js setup"
    fi
    # Install Python using pyenv
    if command -v pyenv &>/dev/null; then
        local target_python="3.12.7"
        if [[ -n "$(python3 --version 2>/dev/null || true)" ]]; then
            log_info "Python already installed ($(python3 --version)); ensuring pyenv version $target_python is available."
        fi
        if pyenv versions --bare | grep -qx "$target_python"; then
            log_info "Python $target_python already installed via pyenv."
        else
            log_info "Installing Python $target_python via pyenv (this may take a while)..."
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY‑RUN] Would run: pyenv install $target_python"
            else
                if ! pyenv install "$target_python"; then
                    # fallback to latest 3.12.x version
                    local latest_312
                    latest_312=$(pyenv install --list | grep -E '^\s*3\.12\.[0-9]+$' | tail -1 | xargs)
                    if [[ -n "$latest_312" ]]; then
                        pyenv install "$latest_312"
                        target_python="$latest_312"
                    else
                        log_error "Failed to install any Python 3.12.x version via pyenv"
                        return 1
                    fi
                fi
            fi
        fi
        log_info "Setting Python $target_python as global default via pyenv..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY‑RUN] Would run: pyenv global $target_python"
        else
            pyenv global "$target_python"
        fi
        # Upgrade pip and install common packages
        log_info "Upgrading pip and installing useful Python packages (virtualenv, black, flake8, pytest, requests)..."
        safe_execute "pip install --upgrade pip"
        safe_execute "pip install virtualenv black flake8 pytest requests"
    else
        log_warn "pyenv not installed; skipping Python setup"
    fi
}

# Helper: download a file with curl and report progress.  Returns 0 on
# success.  In dry‑run mode no download occurs.
download_with_verification() {
    local url="$1"; local output="$2"; local description="$3"
    log_info "Downloading $description..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY‑RUN] Would download: $url -> $output"
        return 0
    fi
    if curl -L --progress-bar --fail -o "$output" "$url"; then
        log_info "$description downloaded successfully"
        return 0
    else
        log_warn "Failed to download $description from $url"
        return 1
    fi
}

# Install a DMG application.  Checks if the application already exists
# in /Applications and skips installation if so.  Expects the DMG file
# to be present in $HOME/Downloads.  This function handles mounting
# and unmounting the image.
install_dmg_app() {
    local dmg_path="$1"; local app_name="$2"; local app_bundle_name="$3"
    # If the application bundle already exists skip installation
    if [[ -d "/Applications/$app_bundle_name.app" ]]; then
        log_info "$app_bundle_name is already installed. Skipping."
        return 0
    fi
    if [[ ! -f "$dmg_path" ]]; then
        log_warn "$app_name DMG not found at $dmg_path; skipping $app_name installation"
        return 0
    fi
    log_info "Installing $app_name..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY‑RUN] Would mount and copy $app_name from $dmg_path"
        return 0
    fi
    # Mount DMG
    if ! hdiutil attach "$dmg_path" -nobrowse -quiet; then
        log_error "Failed to mount $dmg_path"
        return 1
    fi
    # Find mount point
    local volume
    volume=$(hdiutil info | grep "/Volumes/" | tail -1 | awk '{print substr($0,index($0,$3))}')
    local app_source
    app_source=$(find "$volume" -maxdepth 2 -name "$app_bundle_name.app" -print -quit)
    if [[ -d "$app_source" ]]; then
        log_info "Copying $app_bundle_name to /Applications..."
        echo "🔐 Administrator access may be required."
        sudo cp -R "$app_source" "/Applications/" || log_error "Failed to copy $app_bundle_name"
    else
        log_warn "Unable to locate $app_bundle_name.app in mounted DMG"
    fi
    # Unmount volume
    hdiutil detach "$volume" -quiet || log_warn "Failed to unmount $volume"
}

# Phase: applications
# Download and install GUI applications: PyCharm Professional, Google
# Chrome and ChatGPT Desktop.  Additional applications can be added by
# editing this function.
install_applications() {
    log_info "Downloading GUI applications to ~/Downloads..."
    mkdir -p "$HOME/Downloads"
    # Download DMGs
    download_with_verification "https://download.jetbrains.com/python/pycharm-professional.dmg" "$HOME/Downloads/pycharm.dmg" "PyCharm Professional"
    download_with_verification "https://persistent.oaistatic.com/sidekick/public/ChatGPT_Desktop_public_latest.dmg" "$HOME/Downloads/ChatGPT.dmg" "ChatGPT Desktop"
    download_with_verification "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg" "$HOME/Downloads/GoogleChrome.dmg" "Google Chrome"
    # Install DMG apps
    install_dmg_app "$HOME/Downloads/pycharm.dmg" "PyCharm Professional" "PyCharm"
    install_dmg_app "$HOME/Downloads/ChatGPT.dmg" "ChatGPT Desktop" "ChatGPT"
    install_dmg_app "$HOME/Downloads/GoogleChrome.dmg" "Google Chrome" "Google Chrome"
    # Additional manual recommendations
    echo "💡 Additional recommended downloads:"
    echo "   • Windsurf: https://windsurf.dev"
    echo "   • Docker Desktop: https://www.docker.com/products/docker-desktop"
}

# Phase: system_configuration
# Perform final system tweaks such as setting the default web browser.
final_system_configuration() {
    # Ensure defaultbrowser CLI is installed
    if ! command -v defaultbrowser &>/dev/null; then
        log_info "Installing defaultbrowser CLI tool via Homebrew..."
        safe_execute "brew install defaultbrowser"
    fi
    log_info "Setting Google Chrome as the default browser..."
    safe_execute "defaultbrowser chrome"
}

# -----------------------------------------------------------------------------
#  Main execution
# -----------------------------------------------------------------------------

main() {
    # Handle --dry-run flag
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        echo "🔍 Running in dry‑run mode – no changes will be made."
    fi
    # Initialise logging and validate system
    init_logging
    validate_system_state
    # Load previous state if any
    load_installation_state
    # Execute phases in order
    execute_phase "system_prerequisites" install_system_prerequisites
    execute_phase "git_and_ssh" configure_git_and_ssh
    execute_phase "shell_configuration" setup_shell_configuration
    execute_phase "dotfiles" install_dotfiles
    execute_phase "development_tools" install_development_tools
    execute_phase "applications" install_applications
    execute_phase "system_configuration" final_system_configuration
    # All done
    cleanup_and_exit 0
}

main "$@"