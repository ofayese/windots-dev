# Merged PowerShell Profile Script - CurrentUserAllHosts
# Combines settings and functions from both custom profiles and ChrisTitusTech base profile.

# Global flags and update settings
$global:PowerShellVersion = $PSVersionTable.PSVersion.Major
$global:IsPowerShell5    = ($global:PowerShellVersion -eq 5)
$global:IsPowerShellCore = ($global:PowerShellVersion -ge 6)
$debug = $false

# $PSStyle is an automatic variable only in PowerShell 6+. Provide a no-op fallback on
# Windows PowerShell 5.1 so colorized output (Show-Help, banners) degrades to plain text
# instead of producing empty/garbled sequences.
if (-not $PSStyle) {
    $emptyColors = [pscustomobject]@{
        Cyan = ''; Yellow = ''; Green = ''; Magenta = ''; Red = ''; Blue = ''; White = ''
    }
    $global:PSStyle = [pscustomobject]@{ Reset = ''; Foreground = $emptyColors }
}
# Path to file storing last update check date and interval (days)
$timeFilePath   = [Environment]::GetFolderPath("MyDocuments") + "\PowerShell\LastExecutionTime.txt"
$updateInterval = 7

if ($debug) {
    Write-Host "#######################################" -ForegroundColor Red
    Write-Host "#           Debug mode enabled        #" -ForegroundColor Red
    Write-Host "#         (Skipping update checks)    #" -ForegroundColor Red
    Write-Host "#######################################" -ForegroundColor Red
}

# Opt-out of telemetry if run as admin (machine-wide for PS Core)
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [EnvironmentVariableTarget]::Machine)
}

# Initial GitHub connectivity check with timeout
$global:canConnectToGitHub = if ($global:IsPowerShellCore) {
    Test-Connection github.com -Count 1 -Quiet -TimeoutSeconds 1
} else {
    # PS 5.1 version (no -TimeoutSeconds parameter)
    Test-Connection github.com -Count 1 -Quiet
}

# Ensure Terminal-Icons module is installed, then import
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
}
# Terminal-Icons caches its theme data as CLIXML under %APPDATA%\powershell\Community\Terminal-Icons.
# These caches can get corrupted (interrupted writes, OneDrive sync conflicts), after which the module
# emits a raw "Import-Clixml: ... start tag ... does not match the end tag" error during profile load.
# Proactively drop any unreadable cache file so the module regenerates a clean copy on import.
$terminalIconsCache = Join-Path $env:APPDATA 'powershell\Community\Terminal-Icons'
if (Test-Path -LiteralPath $terminalIconsCache) {
    Get-ChildItem -LiteralPath $terminalIconsCache -Filter '*.xml' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $cacheFile = $_.FullName
        try {
            $null = Import-Clixml -LiteralPath $cacheFile -ErrorAction Stop
        } catch {
            Write-Warning "Removing corrupted Terminal-Icons cache file: $cacheFile"
            Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
        }
    }
}
try {
    Import-Module -Name Terminal-Icons -ErrorAction Stop
} catch {
    Write-Warning "Failed to import Terminal-Icons: $_"
}

# Import Chocolatey's profile module if available (for Chocolatey enhancements)
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module $ChocolateyProfile
}

# Functions and Aliases
function Find-WindotsRepository {
    <#
    .SYNOPSIS
        Finds the local dotfiles ("Windots") repository directory by resolving the profile symlink.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ProfilePath
    )
    Write-Verbose "Resolving the symbolic link for the profile at $ProfilePath"
    $profileLink = Get-ChildItem $ProfilePath -ErrorAction SilentlyContinue
    if ($profileLink -and $profileLink.Attributes -match 'ReparsePoint') {
        # If the profile file is a symlink, get its target
        return Split-Path -Path $profileLink.Target
    }
    # If not a symlink (profile stored directly), use its directory
    return Split-Path -Path $ProfilePath
}

function Update-PowerShell {
    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $updateNeeded   = $false
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl   = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestRelease  = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion  = $latestRelease.tag_name.Trim('v')
        if ([version]$currentVersion -lt [version]$latestVersion) {
            $updateNeeded = $true
        }
        if ($updateNeeded) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoProfile -Command winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow
            Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Your PowerShell is up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to check/update PowerShell: $_"
    }
}

# Run PowerShell update check periodically (skip in debug mode)
if (-not $debug -and (
    $updateInterval -eq -1 -or
    -not (Test-Path $timeFilePath) -or
    ((Get-Date).Date - [datetime]::ParseExact((Get-Content -Path $timeFilePath), 'yyyy-MM-dd', $null).Date).TotalDays -gt $updateInterval
    )) {
    Update-PowerShell
    (Get-Date -Format 'yyyy-MM-dd') | Out-File -FilePath $timeFilePath -Encoding ASCII
} elseif ($debug) {
    Write-Warning "Skipping PowerShell update check in debug mode"
}

function Update-Software {
    <#
    .SYNOPSIS
        Updates all software installed via Winget and Chocolatey.
    .DESCRIPTION
        Upgrades all user-installed applications using Windows Package Manager (winget) and Chocolatey.
    #>
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Update-Software: Please run this function in an elevated shell (as Administrator)."
        return
    }
    Write-Host "Updating all winget and Chocolatey packages..." -ForegroundColor Cyan
    winget upgrade --all --include-unknown --silent --verbose
    choco upgrade all -y
    # Clear any software update notification flag
    $ENV:SOFTWARE_UPDATE_AVAILABLE = ""
    Write-Host "Software updates completed." -ForegroundColor Green
}

function Clear-Cache {
    <#
    .SYNOPSIS
        Clears various system caches (Prefetch, Temp, IE cache).
    #>
    Write-Host "Clearing cache..." -ForegroundColor Cyan

    Write-Host "Clearing Windows Prefetch..." -ForegroundColor Yellow
    Remove-Item "$env:SystemRoot\Prefetch\*" -Force -ErrorAction SilentlyContinue

    Write-Host "Clearing Windows Temp..." -ForegroundColor Yellow
    Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Clearing User Temp..." -ForegroundColor Yellow
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Clearing Internet Explorer Cache..." -ForegroundColor Yellow
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Cache clearing completed." -ForegroundColor Green
}

# VSCode integration: use insiders as editor when in VSCode terminal
if ($env:VSCODE_INJECTION -eq "1") {
    $env:EDITOR = "code-insiders --wait"
}

# Load PowerShell Pro Tools module from VSCode extension if present
try {
    $vscodePath         = "$env:USERPROFILE\.vscode"
    $vscodeInsidersPath = "$env:USERPROFILE\.vscode-insiders"
    $extensionPath = if (Test-Path $vscodeInsidersPath) {
        $vscodeInsidersPath
    } else {
        $vscodePath
    }
    $modulePath = Join-Path $extensionPath 'extensions\ironmansoftware.powershellprotools-2024.12.0\Modules\PowerShellProTools.VSCode\PowerShellProTools.VSCode.psd1'
    if (Test-Path $modulePath) {
        Import-Module $modulePath -ErrorAction Stop
        Write-Host "PowerShell Pro Tools loaded from $extensionPath" -ForegroundColor Green
    } else {
        Write-Warning "PowerShell Pro Tools module not found at: $modulePath"
    }
}
catch {
    Write-Warning "Could not load PowerShell Pro Tools: $_"
}

function New-Symlink {
    <#
    .SYNOPSIS
        Creates a symbolic link to a target path, with admin privilege check.
    #>
    [CmdletBinding()]
    param(
        [string] $symlink = "",
        [string] $target  = ""
    )
    try {
        if (!$symlink) { $symlink = Read-Host "Enter new symlink filename" }
        if (!$target)  { $target  = Read-Host "Enter path to target" }

        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Warning "Administrator privileges recommended for creating symbolic links. Attempting anyway..."
        }

        New-Item -Path $symlink -ItemType SymbolicLink -Value $target -ErrorAction Stop | Out-Null
        Write-Host "✅ Created new symlink '$symlink' -> $target" -ForegroundColor Green
        return $true
    }
    catch {
        if ($_.Exception.Message -match "Administrator privilege required") {
            Write-Warning "❌ Failed to create symlink: Administrator privileges required"
            Write-Host "💡 Run PowerShell as Administrator to create symbolic links" -ForegroundColor Yellow
        } else {
            Write-Error "Failed to create symlink: $_"
        }
        return $false
    }
}

function Clear-Docker {
    <#
    .SYNOPSIS
        Removes all unused Docker resources (with optional volumes).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [switch] $Force,
        [switch] $SkipVolumes
    )
    if ($Force -or $PSCmdlet.ShouldProcess("all unused Docker resources", "Remove")) {
        Write-Host "Cleaning Docker resources..." -ForegroundColor Cyan
        $volumeParam = if (!$SkipVolumes) { "--volumes" } else { "" }
        docker system prune -af $volumeParam
        docker builder prune -f
        Write-Host "Docker cleanup complete!" -ForegroundColor Green
    }
}
Set-Alias -Name dclean -Value Clear-Docker

# Determine admin status for prompt and other uses
$global:isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Custom prompt function (differentiate VSCode and admin)
function customPrompt {
    $currentPath = (Get-Location).Path
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] " -NoNewline -ForegroundColor Yellow
    Write-Host "$(Split-Path -Leaf $currentPath)" -NoNewline -ForegroundColor Cyan
    return " > "
}
function prompt {
    if ($env:VSCODE_INJECTION -eq "1") {
        customPrompt
    } else {
        if ($isAdmin) { "[" + (Get-Location) + "] # " } else { "[" + (Get-Location) + "] $ " }
    }
}
# Indicate admin status in window title
$adminSuffix = if ($isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell $($PSVersionTable.PSVersion)$adminSuffix"

function Test-CommandExists {
    param($command)
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}

# Editor configuration - pick an editor in preference order
$EDITOR = if (Test-CommandExists code-insiders) { 'code-insiders' }
    elseif (Test-CommandExists pvim) { 'pvim' }
    elseif (Test-CommandExists nvim) { 'nvim' }
    elseif (Test-CommandExists vim) { 'vim' }
    elseif (Test-CommandExists vi)  { 'vi' }
    elseif (Test-CommandExists code) { 'code' }
    elseif (Test-CommandExists 'notepad++') { 'notepad++' }
    elseif (Test-CommandExists sublime_text) { 'sublime_text' }
    else { 'notepad' }
if ($EDITOR) {
    Set-Alias -Name vim -Value $EDITOR
    Set-Alias -Name vi  -Value $EDITOR
}

# Quick access to editing this profile
function Edit-Profile {
    & $EDITOR $PROFILE.CurrentUserAllHosts
}
Set-Alias -Name ep -Value Edit-Profile

# Basic file and search utilities
function touch($file) { "" | Out-File $file -Encoding ASCII }
function ff($name) {
    # Find files by name recursively from current directory
    Get-ChildItem -Recurse -Filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.FullName)"
    }
}

# Network utilities
function Get-PubIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

# Chris Titus Tech WinUtil shortcuts
function winutil   { Invoke-RestMethod "https://christitus.com/win"   | Invoke-Expression }
function winutildev{ Invoke-RestMethod "https://christitus.com/windev" | Invoke-Expression }

# System utilities
function admin {
    <#
    .SYNOPSIS
        Open a new Windows Terminal with admin rights, optionally running a given command.
    #>
    if ($args.Count -gt 0) {
        $argList = $args -join ' '
        Start-Process wt -Verb runAs -ArgumentList "pwsh.exe -NoExit -Command $argList"
    } else {
        Start-Process wt -Verb runAs
    }
}
# Alias 'su' to quickly elevate to admin terminal
Set-Alias -Name su -Value admin

function uptime {
    <#
    .SYNOPSIS
        Displays the system start time and uptime.
    #>
    try {
        # Determine date/time formats for current culture
        $dateFormat = [CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
        $timeFormat = [CultureInfo]::CurrentCulture.DateTimeFormat.LongTimePattern

        if ($PSVersionTable.PSVersion.Major -eq 5) {
            # For Windows PowerShell (uses WMI)
            $lastBoot = (Get-WmiObject win32_operatingsystem).LastBootUpTime
            $bootTime = [Management.ManagementDateTimeConverter]::ToDateTime($lastBoot)
            $lastBoot = $bootTime.ToString("$dateFormat $timeFormat")
        } else {
            # For PowerShell 6+
            $lastBoot = net statistics workstation | Select-String "since" | ForEach-Object { $_.ToString().Replace('Statistics since ', '') }
            $bootTime = [datetime]::ParseExact($lastBoot, "$dateFormat $timeFormat", [CultureInfo]::CurrentCulture)
        }
        # Format the start time
        $formattedBootTime = $bootTime.ToString("dddd, MMMM dd, yyyy HH:mm:ss", [CultureInfo]::InvariantCulture) + " [$lastBoot]"
        Write-Host "System started on: $formattedBootTime" -ForegroundColor DarkGray

        # Calculate uptime
        $uptime = (Get-Date) - $bootTime
        Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor Blue
    }
    catch {
        Write-Error "An error occurred while retrieving system uptime: $_"
    }
}

function Restart-Profile {
    # Reload the current user's profile script (useful after making changes)
    $global:ThemeLoaded = $false
    . $PROFILE
}

function unzip($file) {
    Write-Host "Extracting $file to $PWD"
    $fullFile = Get-ChildItem -Path $PWD -Filter $file | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
    if ($fullFile) {
        Expand-Archive -Path $fullFile -DestinationPath $PWD
    } else {
        Write-Warning "File $file not found in current directory."
    }
}

function hb {
    <#
    .SYNOPSIS
        Uploads the content of a file to a hastebin-like service and copies the URL.
    #>
    if ($args.Count -eq 0) {
        Write-Error "Usage: hb <FilePath>"
        return
    }
    $FilePath = $args[0]
    if (-not (Test-Path $FilePath)) {
        Write-Error "File path does not exist."
        return
    }
    $Content = Get-Content $FilePath -Raw
    $uri = "http://bin.christitus.com/documents"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $Content -ErrorAction Stop
        $hasteKey = $response.key
        $url = "http://bin.christitus.com/$hasteKey"
        $url | Set-Clipboard
        Write-Output $url
    }
    catch {
        Write-Error "Failed to upload the document. Error: $_"
    }
}

function grep($regex, $dir) {
    # Grep utility: search for regex in files
    if ($dir) {
        Get-ChildItem $dir | Select-String $regex
    } else {
        $Input | Select-String $regex
    }
}
function df { Get-Volume }
function sed($file, $find, $replace) {
    (Get-Content $file) -replace [regex]::Escape($find), $replace | Set-Content $file
}
function which($command) {
    Get-Command -Name $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue
}
function export($name, $value) {
    Set-Item -Path "Env:$name" -Value $value -Force
}
function pkill($name) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process
}
function pgrep($name) {
    Get-Process -Name $name
}
function head { param($Path, $n = 10) Get-Content $Path -Head $n }
function tail { param($Path, $n = 10, [switch]$f) Get-Content $Path -Tail $n -Wait:$f }
# Quick file creation
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }
# Directory creation + navigation
function mkcd { param($dir) New-Item -ItemType Directory -Force -Path $dir | Out-Null; Set-Location $dir }
function trash($path) {
    <#
    .SYNOPSIS
        Moves a file or folder to the Recycle Bin (Windows).
    #>
    # Null-conditional (?.) is PS7-only; use an explicit null check for 5.1 compatibility.
    $resolved = Resolve-Path -Path $path -ErrorAction SilentlyContinue
    $fullPath = if ($resolved) { $resolved.Path } else { $null }
    if (-not $fullPath) {
        Write-Host "Error: Item '$path' does not exist."
        return
    }
    $item = Get-Item $fullPath
    $parentPath = if ($item.PSIsContainer) { $item.Parent.FullName } else { $item.DirectoryName }
    $shell = New-Object -ComObject 'Shell.Application'
    $shellItem = $shell.NameSpace($parentPath).ParseName($item.Name)
    if ($shellItem) {
        $shellItem.InvokeVerb('delete')
        Write-Host "Item '$fullPath' has been moved to the Recycle Bin."
    } else {
        Write-Host "Error: Could not send '$fullPath' to Recycle Bin."
    }
}

# Environment Variables 🌐
$ENV:WindotsLocalRepo = Find-WindotsRepository -ProfilePath $PROFILE.CurrentUserAllHosts
$ENV:_ZO_DATA_DIR     = $ENV:WindotsLocalRepo
$ENV:OBSIDIAN_PATH    = "$HOME\Documents\Obsidian Vault"
$ENV:BAT_CONFIG_DIR   = "$ENV:WindotsLocalRepo\bat"
$ENV:FZF_DEFAULT_OPTS = '--color=fg:-1,fg+:#ffffff,bg:-1,bg+:#3c4048 --color=hl:#5ea1ff,hl+:#5ef1ff,info:#ffbd5e,marker:#5eff6c --color=prompt:#ff5ef1,spinner:#bd5eff,pointer:#ff5ea0,header:#5eff6c --color=gutter:-1,border:#3c4048,scrollbar:#7b8496,label:#7b8496 --color=query:#ffffff --border="rounded" --border-label="" --preview-window="border-rounded" --height 40% --preview="bat -n --color=always {}"'

# Enhanced PowerShell Experience (PSReadLine configuration)
if ($PSVersionTable.PSVersion.Major -ge 7) {
    # PowerShell 7+ PSReadLine settings with predictions
    $PSReadLineOptions = @{
        EditMode                      = 'Windows'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        Colors = @{
            Command   = '#87CEEB'   # SkyBlue (pastel)
            Parameter = '#98FB98'   # PaleGreen (pastel)
            Operator  = '#FFB6C1'   # LightPink (pastel)
            Variable  = '#DDA0DD'   # Plum (pastel)
            String    = '#FFDAB9'   # PeachPuff (pastel)
            Number    = '#B0E0E6'   # PowderBlue (pastel)
            Type      = '#F0E68C'   # Khaki (pastel)
            Comment   = '#D3D3D3'   # LightGray (pastel)
            Keyword   = '#8367c7'   # MediumPurple (custom pastel)
            Error     = '#FF6347'   # Tomato (noticeable red)
        }
        PredictionSource    = 'History'
        PredictionViewStyle = 'ListView'
        BellStyle           = 'None'
    }
    Set-PSReadLineOption @PSReadLineOptions
} else {
    # PowerShell 5.1 (limited PSReadLine features, no prediction)
    $PSReadLineOptions = @{
        EditMode                      = 'Windows'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        Colors = @{
            Command   = '#87CEEB'
            Parameter = '#98FB98'
            Operator  = '#FFB6C1'
            Variable  = '#DDA0DD'
            String    = '#FFDAB9'
            Number    = '#B0E0E6'
            Type      = '#F0E68C'
            Comment   = '#D3D3D3'
            Keyword   = '#8367c7'
            Error     = '#FF6347'
        }
        BellStyle = 'None'
    }
    Set-PSReadLineOption @PSReadLineOptions
}

# Custom PSReadLine key handlers
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
# AcceptSuggestion requires PSReadLine 2.1+ (predictions), which ships with PS7.
# Windows PowerShell 5.1's bundled PSReadLine lacks it, so guard this binding.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Set-PSReadLineKeyHandler -Key Alt+l -Function AcceptSuggestion
}
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+d'       -Function DeleteChar
Set-PSReadLineKeyHandler -Chord 'Ctrl+w'       -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Chord 'Alt+d'        -Function DeleteWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow'  -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

# Add-to-history handler to exclude sensitive info
Set-PSReadLineOption -AddToHistoryHandler {
    param($line)
    $sensitive = @('password', 'secret', 'token', 'apikey', 'connectionstring')
    return ($sensitive | Where-Object { $line -match $_ } ) -eq $null
}

# Increase history size and enable plugin predictions in PS7+
Set-PSReadLineOption -MaximumHistoryCount 10000
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}

# Argument completers for common tools
$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    $customCompletions = @{
        'git'  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')
        'npm'  = @('install', 'start', 'run', 'test', 'build')
        'deno' = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
    }
    $command = $commandAst.CommandElements[0].Value
    if ($customCompletions.ContainsKey($command)) {
        $customCompletions[$command] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock $scriptblock

$scriptblock = {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition $($commandAst.ToString()) | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock $scriptblock

# Prompt and Theme Configuration
if ($PSVersionTable.PSVersion.Major -ge 7) {
    # Initialize Oh-My-Posh with the chosen theme (spacebar)
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\spacebar.omp.json" | Invoke-Expression
    } else {
        Write-Warning "oh-my-posh is not installed. (Run setup to install oh-my-posh.)"
    }
} elseif ($PSVersionTable.PSVersion.Major -eq 5) {
    Write-Warning "Oh-My-Posh is not fully compatible with PowerShell 5.1. Using classic prompt."
    function prompt { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
}

# Initialize zoxide for directory jumping
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
} else {
    Write-Warning "zoxide is not installed. (Run setup to install zoxide.)"
}
Set-Alias -Name z  -Value __zoxide_z  -Option AllScope -Scope Global -Force
Set-Alias -Name zi -Value __zoxide_zi -Option AllScope -Scope Global -Force

# Help documentation for custom commands
function Show-Help {
    $helpText = @"
$($PSStyle.Foreground.Cyan)PowerShell Profile Help$($PSStyle.Reset)
$($PSStyle.Foreground.Yellow)=======================$($PSStyle.Reset)

$($PSStyle.Foreground.Green)Update-PowerShell$($PSStyle.Reset) - Checks for the latest PowerShell release and updates if a new version is available.
$($PSStyle.Foreground.Green)Update-Software$($PSStyle.Reset) - Updates all installed software via Winget & Chocolatey.
$($PSStyle.Foreground.Green)Edit-Profile$($PSStyle.Reset) - Opens the current user's profile in the configured editor.
$($PSStyle.Foreground.Green)touch$($PSStyle.Reset) <file> - Creates a new empty file.
$($PSStyle.Foreground.Green)ff$($PSStyle.Reset) <name> - Recursively finds files with the specified name.
$($PSStyle.Foreground.Green)Get-PubIP$($PSStyle.Reset) - Retrieves the machine's public IP address.
$($PSStyle.Foreground.Green)winutil$($PSStyle.Reset) - Runs the latest Chris Titus Tech WinUtil (full release) script.
$($PSStyle.Foreground.Green)winutildev$($PSStyle.Reset) - Runs the latest WinUtil pre-release script.
$($PSStyle.Foreground.Green)uptime$($PSStyle.Reset) - Displays system start time and uptime.
$($PSStyle.Foreground.Green)Restart-Profile$($PSStyle.Reset) - Reloads the current PowerShell profile.
$($PSStyle.Foreground.Green)unzip$($PSStyle.Reset) <file> - Extracts a ZIP file to the current directory.
$($PSStyle.Foreground.Green)hb$($PSStyle.Reset) <file> - Uploads a file's content to a hastebin service and copies the URL.
$($PSStyle.Foreground.Green)grep$($PSStyle.Reset) <regex> [dir] - Searches for a regex pattern in files (in the specified directory or via pipeline).
$($PSStyle.Foreground.Green)df$($PSStyle.Reset) - Displays information about disk volumes.
$($PSStyle.Foreground.Green)sed$($PSStyle.Reset) <file> <find> <replace> - Replaces text in a file using regex escape.
$($PSStyle.Foreground.Green)which$($PSStyle.Reset) <name> - Shows the full path of the given command if it exists.
$($PSStyle.Foreground.Green)export$($PSStyle.Reset) <name> <value> - Sets an environment variable.
$($PSStyle.Foreground.Green)pkill$($PSStyle.Reset) <name> - Stops (kills) all processes matching the name.
$($PSStyle.Foreground.Green)pgrep$($PSStyle.Reset) <name> - Lists processes by name.
$($PSStyle.Foreground.Green)head$($PSStyle.Reset) <path> [n] - Displays the first n lines of a file (default 10).
$($PSStyle.Foreground.Green)tail$($PSStyle.Reset) <path> [n] - Displays the last n lines of a file (default 10; use -f for follow).
$($PSStyle.Foreground.Green)nf$($PSStyle.Reset) <name> - Creates a new file with the given name.
$($PSStyle.Foreground.Green)mkcd$($PSStyle.Reset) <dir> - Creates a directory and immediately navigates into it.
$($PSStyle.Foreground.Green)docs$($PSStyle.Reset) - Navigates to your Documents folder.
$($PSStyle.Foreground.Green)dtop$($PSStyle.Reset) - Navigates to your Desktop folder.
$($PSStyle.Foreground.Green)ep$($PSStyle.Reset) - Opens this profile in your editor (alias for Edit-Profile).
$($PSStyle.Foreground.Green)k9$($PSStyle.Reset) <name> - Kills a process by name (same as pkill).
$($PSStyle.Foreground.Green)la$($PSStyle.Reset) - Lists files in the current directory in a detailed view.
$($PSStyle.Foreground.Green)ll$($PSStyle.Reset) - Lists all files (including hidden) in a detailed view.
$($PSStyle.Foreground.Green)gs$($PSStyle.Reset) - Shortcut for 'git status'.
$($PSStyle.Foreground.Green)ga$($PSStyle.Reset) - Shortcut for 'git add .'.
$($PSStyle.Foreground.Green)gc$($PSStyle.Reset) <msg> - Shortcut for 'git commit -m "<msg>"'.
$($PSStyle.Foreground.Green)gp$($PSStyle.Reset) - Shortcut for 'git push'.
$($PSStyle.Foreground.Green)g$($PSStyle.Reset) - Jumps to your 'github' directory (using zoxide).
$($PSStyle.Foreground.Green)gcom$($PSStyle.Reset) <msg> - Adds all changes and commits with the given message.
$($PSStyle.Foreground.Green)lazyg$($PSStyle.Reset) <msg> - Adds all changes, commits with message, and pushes (lazy git).
$($PSStyle.Foreground.Green)sysinfo$($PSStyle.Reset) - Displays detailed system information.
$($PSStyle.Foreground.Green)flushdns$($PSStyle.Reset) - Clears the DNS client cache.
$($PSStyle.Foreground.Green)cpy$($PSStyle.Reset) <text> - Copies the given text to clipboard.
$($PSStyle.Foreground.Green)pst$($PSStyle.Reset) - Pastes text from the clipboard.
$($PSStyle.Foreground.Magenta)Show-Help$($PSStyle.Reset) - Displays this help message.
"@
    Write-Host $helpText
}

Write-Host "$($PSStyle.Foreground.Yellow)Use 'Show-Help' to display help$($PSStyle.Reset)"
Write-Host "$($PSStyle.Foreground.Yellow)Use 'Update-PowerShell' to check for updates$($PSStyle.Reset)"
Write-Host "$($PSStyle.Foreground.Yellow)Use 'Update-Software' to update installed software$($PSStyle.Reset)"
Write-Host "$($PSStyle.Foreground.Yellow)Use 'Edit-Profile' to open this profile in your editor$($PSStyle.Reset)"
# Only (re)initialize oh-my-posh on PS7 where it is supported here; 5.1 keeps its classic prompt.
if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    oh-my-posh init pwsh | Invoke-Expression
}
