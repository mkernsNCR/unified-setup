# Unified Mac Development Environment Setup

This repository provides a **single installation script** (``setup.sh``), a
collection of **utility scripts** (`rollback.sh`, `validate.sh` and
`update.sh`) and associated **documentation** for safely and
reproducibly configuring a macOS workstation for software development.

The goal is to blend the features of the original
[`mac-dev-environment-install-wizard`][wizard] and the custom dotfiles
repository (`my‑dotfiles`) while improving reliability, idempotency and
overall safety.  The unified script is designed to be run on a fresh
macOS installation as well as on machines that already have some
development tools installed.  It respects existing configuration files by
creating timestamped backups, avoids duplicate PATH entries, tracks
installation state and supports dry‑run mode.

## Features

* **Interactive and automated modes** – you can run the script in
  ``--dry‑run`` mode to see what actions would be taken without making
  any changes.
* **Idempotent execution** – each phase checks whether the required
  software is already installed and skips tasks if they are complete.
  Running the script multiple times will not corrupt your system or
  reinstall tools unnecessarily.  The original wizard emphasised
  idempotency and state checking【318608987082410†L17-L18】【318608987082410†L300-L304】;
  this script extends those guarantees.
* **Safe PATH handling** – before modifying your ``PATH`` the script
  validates that directories exist and are not already present,
  creates timestamped backups of your shell startup files and provides a
  rollback mechanism.  This avoids common pitfalls such as accidental
  duplication or corruption of important configuration files.
* **State tracking** – a per‑user state file (``~/.setup_state``)
  records which phases have completed and versions of installed tools.
  If the script is interrupted it can resume from the last successful
  phase.
* **Robust error handling** – a global ``trap`` captures errors and
  interrupts, performs cleanup, prints informative messages and exits
  gracefully.  The original setup script already implemented
  comprehensive cleanup routines【318608987082410†L292-L303】; the unified
  script builds upon that foundation.
* **Logging** – all actions are logged with timestamps to
  ``~/unified_setup.log``.  Logs aid troubleshooting and provide an
  audit trail of actions performed.
* **Modular phases** – installation is broken into logical phases
  (system prerequisites, package managers, development tools, shell
  configuration, dotfiles and GUI applications).  Each phase is
  self‑contained, validates its prerequisites and updates the state file
  upon success.

## Quick Start

1. **Clone this repository**

   ```bash
   git clone https://example.com/unified-setup.git
   cd unified-setup
   ```

2. **Run the setup script**

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. **Preview actions with dry‑run**

   ```bash
   ./setup.sh --dry-run
   ```

   Dry‑run mode prints the commands that would be executed without
   making any changes, similar to the dry‑run mode described in the
   original wizard【318608987082410†L233-L253】.

4. **Rollback, validate or update**

   * ``rollback.sh`` – reverses changes made by the setup script.
   * ``validate.sh`` – checks that required tools are installed and
     configuration files are consistent.
   * ``update.sh`` – performs non‑destructive updates of installed
     components (``brew upgrade``, ``nvm install --lts`` etc.).

## Usage Notes

* The script will prompt for your **Git user name and email** if they
  are not already configured.  Input validation ensures the name and
  email follow basic constraints, mirroring the validation described in
  the original wizard【318608987082410†L95-L99】【318608987082410†L258-L264】.
* To link your personal dotfiles repository, set the ``DOTFILES_REPO``
  variable near the top of ``setup.sh``.  The script clones or
  updates that repository and then symlinks the ``.zshrc`` and
  ``.gitconfig`` files into your home directory.
* GUI applications (PyCharm Professional, Google Chrome and
  ChatGPT Desktop) are downloaded to ``~/Downloads`` and installed if
  they are not already present.  Integrity checks and proper mounting
  behaviour ensure safe installation【318608987082410†L201-L216】.
* After installation you may need to **restart your terminal** or run
  ``source ~/.zshrc`` so that new environment variables take effect,
  consistent with the guidance in the original README【318608987082410†L225-L226】.

## Directory Structure

```
unified_solution/
│
├── README.md         – This document
├── setup.sh          – Main installation script
├── rollback.sh       – Undo all installed components and restore backups
├── validate.sh       – Verify installation state
├── update.sh         – Update installed packages and tools
└── Brewfile          – Default Homebrew packages and casks
```

---

[wizard]: https://github.com/mkernsNCR/mac-dev-environment-install-wizard