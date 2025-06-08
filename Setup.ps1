# Consolidated PowerShell Profile Setup Script

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as an Administrator!"
    return
}

# Function to test internet connectivity (ping a reliable host)
function Test-InternetConnection {
    try {
        Test-Connection -ComputerName "www.google.com" -Count 1 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warning "Internet connection is required but not available. Please check your connection."
        return $false
    }
}

# Check internet connectivity before proceeding
if (-not (Test-InternetConnection)) {
    return
}

# Function to install a Nerd Font if not already installed
function Install-NerdFonts {
    param(
        [string] $FontName = "CascadiaCode",
        [string] $FontDisplayName = "CaskaydiaCove NF",
        [string] $Version = "3.2.1"
    )
    try {
        # Check if the font is already installed
        [void] [Reflection.Assembly]::LoadWithPartialName("System.Drawing")
        $installedFonts = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
        if ($installedFonts -contains $FontDisplayName) {
            Write-Host "Font $FontDisplayName is already installed."
            return
        }
        Write-Host "Downloading and installing font $FontDisplayName..."
        $fontZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v${Version}/${FontName}.zip"
        $zipFilePath = "$env:TEMP\${FontName}.zip"
        $extractPath = "$env:TEMP\${FontName}"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($fontZipUrl, $zipFilePath)
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
        $shellApp = New-Object -ComObject Shell.Application
        $fontsFolder = $shellApp.Namespace(0x14)  # Fonts folder
        Get-ChildItem -Path $extractPath -Recurse -Filter "*.ttf" | ForEach-Object {
            if (-not (Test-Path "C:\Windows\Fonts\$($_.Name)")) {
                $fontsFolder.CopyHere($_.FullName, 0x10)
            }
        }
        Remove-Item -Path $extractPath -Recurse -Force
        Remove-Item -Path $zipFilePath -Force
        Write-Host "Font $FontDisplayName installed successfully."
    }
    catch {
        Write-Error "Failed to install font $FontDisplayName. Error: $_"
    }
}

# Ensure the profile directory for CurrentUserAllHosts exists
$targetProfile = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Path $targetProfile -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    Write-Host "Created profile directory: $profileDir"
}

# Set working directory to the script's location (repository root)
Set-Location -Path $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot

# Define dependencies to install via winget and choco
$wingetDeps = @(
    "chocolatey.chocolatey",
    "eza-community.eza",
    "ezwinports.make",
    "fastfetch-cli.fastfetch",
    "git.git",
    "github.cli",
    "JanDeDobbeleer.OhMyPosh",
    "Kitware.CMake",
    "mbuilov.sed",
    "Microsoft.PowerShell",
    "Neovim.Neovim",
    "OpenJS.NodeJS",
    "Starship.Starship",
    "Task.Task"
)
$chocoDeps = @(
    "altsnap",
    "bat",
    "fd",
    "fzf",
    "gawk",
    "lazygit",
    "mingw",
    "nerd-fonts-jetbrainsmono",
    "ripgrep",
    "sqlite",
    "wezterm",
    "zig",
    "zoxide"
)

# PowerShell modules to ensure are installed
$psModules = @(
    "CompletionPredictor",
    "PSScriptAnalyzer",
    "ps-arch-wsl",
    "ps-color-scripts",
    "PowerShellProTools",
    "PSReadLine",
    "PSWriteColor",
    "PSWriteHTML",
    "PSWriteKeyValue",
    "PSWriteMarkdown",
    "PSWriteWord",
    "Terminal-Icons"
)

Write-Host "Installing missing winget and Chocolatey packages..."

# Winget packages: install if not already present
$installedWinget = winget list | Out-String
foreach ($pkg in $wingetDeps) {
    if ($installedWinget -notmatch [regex]::Escape($pkg)) {
        Write-Host "Installing $pkg via winget..."
        winget install --id $pkg -e --accept-source-agreements --accept-package-agreements
    }
}

# Refresh PATH to include any new winget installs
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

# Chocolatey packages: install if not already present
$installedChoco = (choco list --local-only --limit-output --no-color | Out-String).Split("`n")
foreach ($pkg in $chocoDeps) {
    if ($installedChoco -notcontains $pkg) {
        Write-Host "Installing $pkg via Chocolatey..."
        choco install $pkg -y
    }
}

# PowerShell modules: install if not already present
foreach ($module in $psModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing PowerShell module $module..."
        Install-Module -Name $module -Scope CurrentUser -Force -AcceptLicense
    }
}

# Install Cascadia Code Nerd Font (for Oh-My-Posh icons)
Install-NerdFonts -FontName "CascadiaCode" -FontDisplayName "CaskaydiaCove NF"

# Remove default Neovim shortcuts (if present, since we installed via winget)
$nvShortcutDir = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Neovim"
if (Test-Path $nvShortcutDir) {
    Remove-Item "$nvShortcutDir" -Recurse -Force
    Write-Host "Removed default Neovim Start Menu shortcuts."
}

# Persist environment variables (e.g., WezTerm config)
[Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', "$PSScriptRoot\wezterm\wezterm.lua", [EnvironmentVariableTarget]::User)

# Save current global Git config (name and email) to restore after linking
$gitName  = git config --global user.name
$gitEmail = git config --global user.email

# Define symbolic links (destination => source in the repo)
$symlinks = @{
    "$($PROFILE.CurrentUserAllHosts)"                                              = "$PSScriptRoot\Microsoft.PowerShell_profile.ps1"
    "$HOME\AppData\Local\nvim"                                                     = "$PSScriptRoot\nvim"
    "$HOME\AppData\Local\fastfetch"                                                = "$PSScriptRoot\fastfetch"
    "$HOME\AppData\Local\k9s"                                                      = "$PSScriptRoot\k9s"
    "$HOME\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" = "$PSScriptRoot\windowsterminal\settings.json"
    "$HOME\OneDrive\Documents\PowerShell"                                          = "$HOME\Documents\PowerShell\"
    "$HOME\OneDrive\Documents\WindowsPowerShell"                                   = "$HOME\Documents\PowerShell\"
    "C:\Scripts"                                                                   = "$HOME\Documents\PowerShell\Scripts\"
    "$HOME\AppData\Roaming\lazygit"                                                = "$PSScriptRoot\lazygit"
    "$HOME\AppData\Roaming\AltSnap\AltSnap.ini"                                    = "$PSScriptRoot\altsnap\AltSnap.ini"
    "$Env:ProgramFiles\WezTerm\wezterm_modules"                                    = "$PSScriptRoot\wezterm\"
    "C:\tools"                                                                     = "$HOME\Documents\PowerShell\tools\"
}

Write-Host "Creating symbolic links for configuration files/directories..."
foreach ($link in $symlinks.GetEnumerator()) {
    $dest = [string]$link.Key
    $src  = [string](Resolve-Path -Path $link.Value)
    try {
        # Remove existing item at destination (if any)
        if (Test-Path $dest) {
            Remove-Item $dest -Force -Recurse -ErrorAction SilentlyContinue
        }
        # Create the symbolic link
        New-Item -ItemType SymbolicLink -Path $dest -Target $src -Force | Out-Null
        Write-Host "Linked `"$dest`" -> `"$src`""
    }
    catch {
        Write-Warning "Failed to create link for $dest -> $src : $_"
    }
}

# Restore global Git config
if ($gitEmail) { git config --global user.email "$gitEmail" }
if ($gitName)  { git config --global user.name "$gitName" }

# Rebuild bat cache to include any new themes (if bat is installed)
if (Test-Path (Get-Command bat -ErrorAction SilentlyContinue)) {
    bat cache --clear ; bat cache --build
}

# Run AltSnap scheduled task creation (if script exists)
if (Test-Path "$PSScriptRoot\altsnap\createTask.ps1") {
    & "$PSScriptRoot\altsnap\createTask.ps1" | Out-Null
    Write-Host "AltSnap scheduled task created."
}

Write-Host "Setup complete! The PowerShell profile has been linked and configured."
