# Windots-otsflavor

**Windots** is a modern, Windows-centric dotfiles setup for a consistent developer or power-user environment.
This edition features a **fully combined PowerShell profile** and a single, streamlined setup script, carefully merged and deduplicated for clarity and maintainability by Olaolu Fayese.

---

## Overview

**What’s new?**

* **Unified PowerShell profile:** All previous `Profile.ps1` and `Microsoft.PowerShell_profile.ps1` scripts merged and deduplicated. All features, functions, and aliases in one place.
* **One-step Setup:** A single `Setup.ps1` script automates everything—dependencies, fonts, symlinks, modules, cleanup, and configuration.
* **Symlink-based configuration:** All configs (PowerShell profile, Neovim, Windows Terminal, AltSnap, lazygit, tools, and more) are managed and symlinked from this repo.
* **Smart dependency installation:** Uses both Winget and Chocolatey, plus PowerShell module installation.
* **Nerd Font support:** Installs Caskaydia Cove Nerd Font for prompt icons.
* **Modern prompt:** Uses Oh-My-Posh on PowerShell 7+, with fallback for classic shells.

---

## Combined Profile and Setup Flow

### PowerShell Profile (`Microsoft.PowerShell_profile.ps1`)

* **Merged and deduplicated:** All features from previous profiles combined, removing redundant or conflicting logic.

  * Only one definitive version of each alias/function is kept.
  * Modern prompt with Oh-My-Posh.
  * Canonical utility functions: `ff`, `grep`, `which`, `Update-Software`, and many more.
  * Dynamic `$EDITOR` detection, with all related aliases.
  * Preserves advanced features (OneDrive sync helpers, secret management, enhanced navigation, etc).
  * Environment variables are set in one place for tools like zoxide, fzf, bat, etc.
  * Fun extras (ASCII memes, shortcut keybindings) included.

* **Discoverable help:**
  Type `Show-Help` in PowerShell for a full list of available custom commands and aliases.

---

### Setup Script (`Setup.ps1`)

* **Administrative and connectivity checks:**
  Script ensures it’s run as Administrator and with internet access.

* **Dependency installation:**
  Installs (or upgrades) everything you need via Winget and Chocolatey.
  Installs required PowerShell modules.

* **Font installation:**
  Downloads and installs the correct Nerd Font for prompt icons.

* **Symlinks:**
  Symlinks are automatically created for:

  * PowerShell profile (`Microsoft.PowerShell_profile.ps1` → `$PROFILE.CurrentUserAllHosts`)
  * Neovim config (`nvim`)
  * Fastfetch, k9s, AltSnap, lazygit, Windows Terminal, OneDrive PowerShell folder, and more

* **Cleanup and configuration:**
  Removes old Neovim shortcuts, refreshes `bat` cache, sets WezTerm config variable, restores Git config, and registers scheduled tasks as needed.

---

## Quickstart

**Warning:**
This project will overwrite your PowerShell profile and other settings. Back up anything important before running!

1. Clone this repository to your preferred location.
2. Open PowerShell as Administrator and run:

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   cd <WindotsRepoFolder>
   ./Setup.ps1
   ```

3. Wait for installation, linking, and configuration to finish.
4. Start PowerShell (or Windows Terminal).
   Type `Show-Help` to see all available functions and aliases.

---

## What Gets Symlinked

* PowerShell profile (CurrentUserAllHosts)
* Neovim config
* Fastfetch
* k9s
* AltSnap config
* Windows Terminal settings
* LazyGit config
* Tools folder
* PowerShell/WindowsPowerShell in OneDrive (optional)

---

## Installed/Configured Tools

* Oh-My-Posh
* Neovim
* eza (modern `ls`)
* fzf
* bat
* ripgrep
* zoxide
* lazygit
* Node.js, GitHub CLI, CMake, SQLite, and more
* Caskaydia Cove Nerd Font
* PowerShell modules: Terminal-Icons, PSReadLine, and others

---

## Core Features and Custom Commands

* Modern PowerShell prompt (Oh-My-Posh)
* Zoxide navigation (with jump alias)
* Enhanced `ls` via eza
* Fzf integration and custom colors
* One-step updates (`Update-Software`)
* Smart cache and Docker cleanup
* OneDrive sync helpers
* Secret management helpers
* Utility functions: file search, grep, head, tail, sed, which, etc.
* Enhanced keyboard shortcuts in PSReadLine

Type `Show-Help` in your shell for a full breakdown!

---

## Upstream References and Attribution

This configuration draws inspiration and code from:

* Chris Titus Tech’s open-source PowerShell profile
  (Reference: github.com/ChrisTitusTech/powershell-profile/tree/main)

* Scott McKendry’s original Windots dotfiles
  (Reference: github.com/scottmckendry/Windots/tree/main)

Thank you to both communities for their open-source contributions and inspiration.

---

## Contributing

Pull requests and issues are welcome.
Feel free to suggest improvements or report bugs.

For questions or collaboration, contact Olaolu Fayese at <ofayese@gmail.com>.

---

Windots — Combined, deduplicated, and modernized by Olaolu Fayese.
Enjoy your new, reliable, modern PowerShell environment!

---

Let me know if you want a version with live markdown links, more detailed credits, or further customization!
