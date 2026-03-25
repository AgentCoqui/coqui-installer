<#
.SYNOPSIS
    Coqui Installer for Windows
    https://github.com/AgentCoqui/coqui

.DESCRIPTION
    Installs PHP and Coqui on a Windows system.
    By default, downloads the latest GitHub release (no Git/Composer needed).
    Use -Dev to clone the git repository instead (for development).
    Creates a coqui.bat wrapper in your user path for easy execution.

.PARAMETER Dev
    Use git clone instead of release download (for development).

.EXAMPLE
    # Default: download latest release
    irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex

.EXAMPLE
    # Development mode: git clone
    .\install.ps1 -Dev
#>

param(
    [switch]$Dev,
    [switch]$Quiet,
    [switch]$Help
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$script:HadError = $false

# ─── Configuration (override via environment variables) ──────────────────────

$COQUI_REPO = if ($env:COQUI_REPO) { $env:COQUI_REPO } else { "https://github.com/AgentCoqui/coqui.git" }
$COQUI_INSTALL_DIR = if ($env:COQUI_INSTALL_DIR) { $env:COQUI_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".coqui" }
$COQUI_VERSION = if ($env:COQUI_VERSION) { $env:COQUI_VERSION } else { "" }

# GitHub release configuration
$COQUI_GITHUB_OWNER = "AgentCoqui"
$COQUI_GITHUB_REPO = "coqui"
$COQUI_API_URL = "https://api.github.com/repos/$COQUI_GITHUB_OWNER/$COQUI_GITHUB_REPO/releases/latest"
$COQUI_DOWNLOAD_BASE = "https://github.com/$COQUI_GITHUB_OWNER/$COQUI_GITHUB_REPO/releases/download"

# Minimum PHP version required
$REQUIRED_PHP_MAJOR = 8
$REQUIRED_PHP_MINOR = 4

# PHP extensions required by Coqui and php-agents
$REQUIRED_EXTENSIONS = @("curl", "mbstring", "openssl", "pdo_sqlite", "readline", "xml", "zip")

# Mode flags
$script:DEV_MODE = $Dev.IsPresent
$script:QUIET_MODE = $Quiet.IsPresent
$script:HELP_MODE = $Help.IsPresent

# Resolved at runtime
$script:LATEST_VERSION = ""

# ─── Output helpers ──────────────────────────────────────────────────────────

function Write-Status {
    param([string]$Message)
    if ($script:QUIET_MODE) { return }
    Write-Host -Object "  $([char]0x25B8) $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    if ($script:QUIET_MODE) { return }
    Write-Host -Object "  $([char]0x2713) $Message" -ForegroundColor Green
}

function Write-Milestone {
    param([string]$Message)
    Write-Host -Object "  $([char]0x25B8) $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host -Object "  ! $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host -Object "  $([char]0x2717) $Message" -ForegroundColor Red
}

function Write-Fatal {
    param([string]$Message)
    Write-Err $Message
    $script:HadError = $true
    throw "CoquiInstallerError: $Message"
}

# ─── Utility functions ───────────────────────────────────────────────────────

function Test-Command {
    param([string]$CommandName)
    $null = Get-Command $CommandName -ErrorAction SilentlyContinue
    return $?
}

function Refresh-Path {
    # Reload PATH from the registry so newly installed tools are visible
    $MachinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$MachinePath;$UserPath"
}

function Get-UserBinDir {
    # Prefer AppData\Local\Programs\Coqui\bin (clean, dedicated location)
    $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"
    if (-not (Test-Path $CoquiBinDir)) {
        New-Item -ItemType Directory -Force -Path $CoquiBinDir | Out-Null
    }

    # Check if it's in PATH
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not ($UserPath -like "*$CoquiBinDir*")) {
        [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$CoquiBinDir", "User")
        $env:PATH = "$env:PATH;$CoquiBinDir"
        Write-Status "Added $CoquiBinDir to your PATH"
    }

    return $CoquiBinDir
}

# ─── PHP install ─────────────────────────────────────────────────────────────

function Install-Php {
    if (-not (Test-Command "winget")) {
        Write-Host ""
        Write-Host "  PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required but winget is not available."
        Write-Host "  Please install PHP manually from: https://windows.php.net/download/"
        Write-Host ""
        Write-Fatal "PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
    }

    # Prefer the Non-Thread-Safe (NTS) build for CLI use — it is lighter and
    # the TS winget manifest has had broken download URLs in the past.
    # Fall back to the Thread-Safe (TS) package if NTS is unavailable.
    Write-Status "Installing PHP via winget (NTS)..."
    & winget install --id PHP.PHP.NTS.${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    $NtsExitCode = $LASTEXITCODE

    if ($NtsExitCode -ne 0) {
        Write-Status "NTS package unavailable, trying Thread-Safe build..."
        & winget install --id PHP.PHP.${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    }

    if ($NtsExitCode -ne 0 -and $LASTEXITCODE -ne 0) {
        # winget returns non-zero for "already installed" — check if PHP is
        # already present on PATH before treating this as a real failure.
        Refresh-Path
        if (Test-Command "php") {
            Write-Success "PHP already installed"
            return
        }
        Write-Host ""
        Write-Host "  winget could not install PHP automatically."
        Write-Host "  Please install PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ manually:"
        Write-Host "    https://windows.php.net/download/"
        Write-Host ""
        Write-Fatal "PHP installation failed."
    }

    Refresh-Path

    if (-not (Test-Command "php")) {
        Write-Warn "PHP was installed but is not yet in PATH."
        Write-Host "  Please restart your terminal and re-run the installer."
        Write-Fatal "PHP not found in PATH after install."
    }

    if ($NtsExitCode -eq 0) {
        Write-Success "PHP installed via winget (NTS)"
    } else {
        Write-Success "PHP installed via winget"
    }
}

# ─── PHP checks ──────────────────────────────────────────────────────────────

function Check-Php {
    Write-Status "Checking PHP..."

    # Refresh PATH first — PHP may have been installed by winget in a previous
    # run but the current shell session hasn't picked up the new PATH entry yet.
    Refresh-Path

    if (-not (Test-Command "php")) {
        Write-Warn "PHP is not installed."
        Install-Php
    }

    # Get PHP version — use -ErrorAction SilentlyContinue to avoid stderr killing the script
    $PhpVersionOutput = $null
    try {
        $PhpVersionOutput = & php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;" 2>$null
    } catch {
        # Ignore — handled below
    }

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($PhpVersionOutput)) {
        Write-Warn "PHP is in PATH but could not be executed properly."
        Write-Host "  Please reinstall PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ from https://windows.php.net/download/"
        Write-Fatal "PHP is not working correctly."
    }

    $parts = ($PhpVersionOutput -as [string]).Split('.')
    if ($parts.Length -lt 2) {
        Write-Fatal "Could not determine PHP version (got: '$PhpVersionOutput')."
    }

    $PhpMajor = [int]$parts[0]
    $PhpMinor = [int]$parts[1]

    if ($PhpMajor -lt $REQUIRED_PHP_MAJOR -or ($PhpMajor -eq $REQUIRED_PHP_MAJOR -and $PhpMinor -lt $REQUIRED_PHP_MINOR)) {
        Write-Warn "PHP $PhpVersionOutput found, but ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
        Install-Php

        # Re-check after install
        $PhpVersionOutput = & php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;" 2>$null
        $parts = ($PhpVersionOutput -as [string]).Split('.')
        $PhpMajor = [int]$parts[0]
        $PhpMinor = [int]$parts[1]

        if ($PhpMajor -lt $REQUIRED_PHP_MAJOR -or ($PhpMajor -eq $REQUIRED_PHP_MAJOR -and $PhpMinor -lt $REQUIRED_PHP_MINOR)) {
            Write-Fatal "PHP version is still too old after install attempt."
        }
    }

    Write-Success "PHP $PhpVersionOutput"
}

# ─── Extension checks ────────────────────────────────────────────────────────

function Check-Extensions {
    Write-Status "Checking PHP extensions..."

    $Missing = @()
    $Loaded = @()
    try {
        $Loaded = & php -m 2>$null
    } catch {
        Write-Fatal "Failed to query PHP extensions."
    }

    foreach ($Ext in $REQUIRED_EXTENSIONS) {
        $match = $Loaded | Where-Object { $_ -match "^$Ext$" }
        if (-not $match) {
            $Missing += $Ext
        }
    }

    if ($Missing.Count -eq 0) {
        Write-Success "All required extensions available"
        return
    }

    # Try to auto-enable missing extensions in php.ini
    $MissingList = $Missing -join ", "
    Write-Warn "Missing PHP extensions: $MissingList"

    $PhpIniPath = $null
    try {
        $PhpIniPath = (& php -r "echo php_ini_loaded_file();" 2>$null)
    } catch {}

    if ([string]::IsNullOrWhiteSpace($PhpIniPath) -or -not (Test-Path $PhpIniPath)) {
        # No php.ini loaded — try to find and copy php.ini-development
        try {
            $PhpDir = Split-Path (Get-Command php -ErrorAction SilentlyContinue).Source
            $PhpIniDev = Join-Path $PhpDir "php.ini-development"
            $PhpIniTarget = Join-Path $PhpDir "php.ini"

            if ((Test-Path $PhpIniDev) -and -not (Test-Path $PhpIniTarget)) {
                Write-Status "Creating php.ini from php.ini-development..."
                Copy-Item $PhpIniDev $PhpIniTarget
                $PhpIniPath = $PhpIniTarget
            }
        } catch {}
    }

    if ($PhpIniPath -and (Test-Path $PhpIniPath)) {
        Write-Status "Enabling missing extensions in $PhpIniPath..."
        $IniContent = Get-Content -Path $PhpIniPath -Raw

        # Ensure extension_dir is set
        if ($IniContent -match ';\s*extension_dir\s*=\s*"ext"') {
            $IniContent = $IniContent -replace ';\s*(extension_dir\s*=\s*"ext")', '$1'
        }

        foreach ($Ext in $Missing) {
            # Uncomment the extension line if it exists
            $Pattern = ";\s*extension=$Ext"
            if ($IniContent -match $Pattern) {
                $IniContent = $IniContent -replace $Pattern, "extension=$Ext"
            } else {
                # Append if not present at all
                $IniContent += "`nextension=$Ext"
            }
        }

        Set-Content -Path $PhpIniPath -Value $IniContent

        # Re-check extensions
        $Loaded = & php -m 2>$null
        $StillMissing = @()
        foreach ($Ext in $Missing) {
            $match = $Loaded | Where-Object { $_ -match "^$Ext$" }
            if (-not $match) {
                $StillMissing += $Ext
            }
        }

        if ($StillMissing.Count -eq 0) {
            Write-Success "Extensions enabled successfully"
            return
        }

        $MissingList = $StillMissing -join ", "
        Write-Warn "Could not enable: $MissingList"
    }

    Write-Host ""
    Write-Host "  Some extensions could not be enabled automatically."
    Write-Host "  Run 'php --ini' to locate your php.ini, then uncomment:"
    foreach ($Ext in $Missing) {
        Write-Host "    extension=$Ext"
    }
    Write-Host ""
    Write-Warn "Continuing with missing extensions (some features may not work)."
}

# ─── Git check ───────────────────────────────────────────────────────────────

function Check-Git {
    Write-Status "Checking Git..."

    if (Test-Command "git") {
        try {
            $GitVersion = (& git --version 2>$null).Split(' ')[2]
            Write-Success "Git $GitVersion"
        } catch {
            Write-Success "Git found"
        }
        return
    }

    if (-not (Test-Command "winget")) {
        Write-Host ""
        Write-Host "  Git is required. Please install it from:"
        Write-Host "    https://git-scm.com/download/win"
        Write-Host ""
        Write-Fatal "Git is required."
    }

    Write-Status "Installing Git via winget..."
    & winget install --id Git.Git --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  winget could not install Git automatically."
        Write-Host "  Please install Git manually: https://git-scm.com/download/win"
        Write-Host ""
        Write-Fatal "Git installation failed."
    }

    Refresh-Path

    if (-not (Test-Command "git")) {
        Write-Warn "Git was installed but is not yet in PATH."
        Write-Host "  Please restart your terminal and re-run the installer."
        Write-Fatal "Git not found in PATH after install."
    }

    Write-Success "Git installed"
}

# ─── Composer check ──────────────────────────────────────────────────────────

function Check-Composer {
    Write-Status "Checking Composer..."

    if (Test-Command "composer") {
        try {
            $ComposerVersion = (((& composer --version 2>$null) -split ' ')[2]).Trim()
            Write-Success "Composer $ComposerVersion"
        } catch {
            Write-Success "Composer found"
        }
        return
    }

    Install-Composer
}

function Install-Composer {
    Write-Status "Downloading Composer installer..."

    $TempScript = Join-Path $env:TEMP "composer-setup.php"
    try {
        Invoke-WebRequest -Uri "https://getcomposer.org/installer" -UseBasicParsing -OutFile $TempScript -ErrorAction Stop
    } catch {
        Write-Fatal "Failed to download Composer installer."
    }

    Write-Status "Installing Composer..."

    $BinDir = Get-UserBinDir

    try {
        $ComposerOutput = & php $TempScript --quiet --install-dir=$BinDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($ComposerOutput) {
                Write-Err ($ComposerOutput | Out-String).Trim()
            }
            Remove-Item -Path $TempScript -Force -ErrorAction SilentlyContinue
            Write-Fatal "Composer installation failed."
        }
    } catch {
        Remove-Item -Path $TempScript -Force -ErrorAction SilentlyContinue
        throw
    }

    Remove-Item -Path $TempScript -Force -ErrorAction SilentlyContinue

    # Create composer.bat wrapper
    $ComposerBat = Join-Path $BinDir "composer.bat"
    Set-Content -Path $ComposerBat -Value "@php `"%~dp0composer.phar`" %*"

    Write-Success "Composer installed"

    # Make composer available for the rest of this session
    if (-not (Test-Command "composer")) {
        Set-Alias composer $ComposerBat -Scope Global
    }
}

# ─── Installation detection ──────────────────────────────────────────────────

function Test-DevInstalled {
    $GitPath = Join-Path $COQUI_INSTALL_DIR ".git"
    return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $GitPath)
}

function Test-ReleaseInstalled {
    $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
    return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $VersionFile)
}

function Test-CoquiInstalled {
    return (Test-DevInstalled) -or (Test-ReleaseInstalled)
}

function Get-InstalledVersion {
    $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
    if (Test-Path $VersionFile) {
        return (Get-Content -Path $VersionFile -Raw).Trim()
    }
    return ""
}

# ─── GitHub release functions ────────────────────────────────────────────────

function Get-LatestVersion {
    if ($COQUI_VERSION) {
        $script:LATEST_VERSION = $COQUI_VERSION
        return
    }

    Write-Status "Checking latest release..."

    try {
        $Response = Invoke-RestMethod -Uri $COQUI_API_URL -ErrorAction Stop
    } catch {
        Write-Fatal "Failed to fetch release info from GitHub. Check your internet connection or try -Dev."
    }

    $TagName = $Response.tag_name
    if ([string]::IsNullOrWhiteSpace($TagName)) {
        Write-Fatal "Could not determine latest version from GitHub. Try: `$env:COQUI_VERSION='0.0.1'; .\install.ps1"
    }

    # Strip leading 'v' if present
    $script:LATEST_VERSION = $TagName -replace '^v', ''
    Write-Success "Latest release: v$($script:LATEST_VERSION)"
}

function Test-Checksum {
    param(
        [string]$FilePath,
        [string]$ChecksumUrl
    )

    Write-Status "Verifying checksum..."

    try {
        $RawContent = (Invoke-WebRequest -Uri $ChecksumUrl -UseBasicParsing -ErrorAction Stop).Content
        # .Content may be byte[] (binary content-type) or a string — handle both
        if ($RawContent -is [byte[]]) {
            $ExpectedContent = [System.Text.Encoding]::ASCII.GetString($RawContent)
        } else {
            $ExpectedContent = $RawContent -as [string]
        }
    } catch {
        Write-Warn "Could not download checksum file. Skipping verification."
        return
    }

    # The .sha256 file format is: "hash  filename"
    $ExpectedHash = ($ExpectedContent -split '\s')[0].Trim().ToLower()
    $ActualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()

    if ($ExpectedHash -ne $ActualHash) {
        Write-Fatal "Checksum verification failed. Expected: $ExpectedHash, Got: $ActualHash"
    }

    Write-Success "Checksum verified"
}

# ─── Release install / update ────────────────────────────────────────────────

function Install-Release {
    Get-LatestVersion

    $ArchiveName = "coqui-v$($script:LATEST_VERSION).zip"
    $DownloadUrl = "$COQUI_DOWNLOAD_BASE/v$($script:LATEST_VERSION)/$ArchiveName"
    $ChecksumUrl = "$DownloadUrl.sha256"

    $TempDir = Join-Path $env:TEMP "coqui-install-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    try {
        Write-Status "Downloading Coqui v$($script:LATEST_VERSION)..."
        $ArchivePath = Join-Path $TempDir $ArchiveName

        try {
            Invoke-WebRequest -Uri $DownloadUrl -UseBasicParsing -OutFile $ArchivePath -ErrorAction Stop
        } catch {
            Write-Fatal "Failed to download release v$($script:LATEST_VERSION). URL: $DownloadUrl"
        }

        Test-Checksum -FilePath $ArchivePath -ChecksumUrl $ChecksumUrl

        Write-Status "Installing to $COQUI_INSTALL_DIR..."

        # Extract — the archive contains a top-level coqui/ directory
        Expand-Archive -Path $ArchivePath -DestinationPath $TempDir -Force

        # Create install dir if needed
        if (-not (Test-Path $COQUI_INSTALL_DIR)) {
            New-Item -ItemType Directory -Force -Path $COQUI_INSTALL_DIR | Out-Null
        }

        # Copy contents from extracted directory into install dir
        $ExtractedDir = Join-Path $TempDir "coqui"
        if (Test-Path $ExtractedDir) {
            Copy-Item -Path "$ExtractedDir\*" -Destination $COQUI_INSTALL_DIR -Recurse -Force
        } else {
            Write-Fatal "Unexpected archive structure - 'coqui' directory not found."
        }

        # Write version marker
        Set-Content -Path (Join-Path $COQUI_INSTALL_DIR ".coqui-version") -Value $script:LATEST_VERSION

        Write-Success "Coqui v$($script:LATEST_VERSION) installed"
    } finally {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Update-Release {
    Get-LatestVersion

    $CurrentVersion = Get-InstalledVersion

    if ($CurrentVersion -eq $script:LATEST_VERSION) {
        Write-Success "Coqui v$CurrentVersion is already up to date"
        return
    }

    if ($CurrentVersion) {
        Write-Status "Update available: v$CurrentVersion -> v$($script:LATEST_VERSION)"
    }

    $ArchiveName = "coqui-v$($script:LATEST_VERSION).zip"
    $DownloadUrl = "$COQUI_DOWNLOAD_BASE/v$($script:LATEST_VERSION)/$ArchiveName"
    $ChecksumUrl = "$DownloadUrl.sha256"

    $TempDir = Join-Path $env:TEMP "coqui-update-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    try {
        Write-Status "Downloading Coqui v$($script:LATEST_VERSION)..."
        $ArchivePath = Join-Path $TempDir $ArchiveName

        try {
            Invoke-WebRequest -Uri $DownloadUrl -UseBasicParsing -OutFile $ArchivePath -ErrorAction Stop
        } catch {
            Write-Fatal "Failed to download release v$($script:LATEST_VERSION)."
        }

        Test-Checksum -FilePath $ArchivePath -ChecksumUrl $ChecksumUrl

        # Back up user data before replacing
        Write-Status "Backing up user data..."
        $WorkspaceDir = Join-Path $COQUI_INSTALL_DIR ".workspace"

        # Back up workspace directory
        if (Test-Path $WorkspaceDir) {
            Copy-Item -Path $WorkspaceDir -Destination (Join-Path $TempDir ".workspace.bak") -Recurse -Force
        }

        # Extract new release
        Expand-Archive -Path $ArchivePath -DestinationPath $TempDir -Force

        # Install new release
        $ExtractedDir = Join-Path $TempDir "coqui"
        if (Test-Path $ExtractedDir) {
            Copy-Item -Path "$ExtractedDir\*" -Destination $COQUI_INSTALL_DIR -Recurse -Force
        }

        # Restore user data (overwrite any defaults from new release)
        $WorkspaceBackup = Join-Path $TempDir ".workspace.bak"

        # Restore workspace if it existed
        if (Test-Path $WorkspaceBackup) {
            $WorkspaceDir = Join-Path $COQUI_INSTALL_DIR ".workspace"
            if (-not (Test-Path $WorkspaceDir)) {
                New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
            }
            Copy-Item -Path "$WorkspaceBackup\*" -Destination $WorkspaceDir -Recurse -Force
        }

        # Write version marker
        Set-Content -Path (Join-Path $COQUI_INSTALL_DIR ".coqui-version") -Value $script:LATEST_VERSION

        Write-Success "Coqui updated to v$($script:LATEST_VERSION)"
    } finally {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── Dev (git) install / update ──────────────────────────────────────────────

function Install-Dev {
    Write-Status "Cloning Coqui into $COQUI_INSTALL_DIR..."

    $CloneArgs = @("clone", "--depth", "1")
    if ($COQUI_VERSION) {
        $CloneArgs = @("clone", "--branch", $COQUI_VERSION, "--depth", "1")
    }

    $CloneArgs += $COQUI_REPO
    $CloneArgs += $COQUI_INSTALL_DIR

    try {
        $CloneOutput = & git $CloneArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($CloneOutput) {
                Write-Err ($CloneOutput | Out-String).Trim()
            }
            Write-Fatal "Failed to clone Coqui repository."
        }
    } catch {
        throw
    }

    Write-Success "Coqui cloned"

    Run-ComposerInstall
}

function Update-Dev {
    Write-Status "Checking for updates..."

    Set-Location $COQUI_INSTALL_DIR

    # Stash any local changes (e.g. modified composer.lock) before pulling
    $StashResult = ""
    try {
        $StashResult = & git stash --include-untracked 2>&1 | Out-String
    } catch {}

    & git fetch --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Restore stash before erroring
        if ($StashResult -match "Saved working directory") {
            & git stash pop --quiet 2>&1 | Out-Null
        }
        Write-Fatal "Failed to fetch updates. Check your internet connection."
    }

    $LocalHead = (& git rev-parse HEAD 2>$null).Trim()
    $RemoteHead = ""
    try {
        $RemoteHead = (& git rev-parse '@{u}' 2>$null).Trim()
    } catch {}

    if ([string]::IsNullOrWhiteSpace($RemoteHead)) {
        $RemoteHead = $LocalHead
    }

    if ($LocalHead -eq $RemoteHead) {
        Write-Success "Coqui is already up to date"

        # Restore stashed changes
        if ($StashResult -match "Saved working directory") {
            & git stash pop --quiet 2>&1 | Out-Null
        }

        Run-ComposerInstall
        return
    }

    Write-Status "Updating Coqui..."

    # Unshallow if needed (shallow clones can fail ff-only)
    $ShallowFile = Join-Path $COQUI_INSTALL_DIR ".git\shallow"
    if (Test-Path $ShallowFile) {
        & git fetch --unshallow --quiet 2>&1 | Out-Null
    }

    & git pull --ff-only --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Restore stash before reporting error
        if ($StashResult -match "Saved working directory") {
            & git stash pop --quiet 2>&1 | Out-Null
        }
        Write-Fatal "Failed to update. Your local branch may have diverged. Try: Remove-Item -Recurse $COQUI_INSTALL_DIR; re-run the installer."
    }

    Write-Success "Coqui updated"

    # Restore stashed changes — if pop fails, drop the stash since
    # the fresh pull state is authoritative and composer install will
    # regenerate composer.lock from the updated composer.json.
    if ($StashResult -match "Saved working directory") {
        & git stash pop --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not restore local changes from stash (likely a merge conflict)."
            Write-Warn "Dropping stash - composer install will regenerate lock file."
            & git stash drop --quiet 2>&1 | Out-Null
        }
    }

    Run-ComposerInstall
}

function Run-ComposerInstall {
    Write-Status "Installing dependencies..."

    Set-Location $COQUI_INSTALL_DIR

    # Remove stale lock file if it conflicts with the current composer.json
    $null = & composer validate --no-check-all --no-check-publish 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "composer.lock is out of sync - regenerating..."
        $LockFile = Join-Path $COQUI_INSTALL_DIR "composer.lock"
        if (Test-Path $LockFile) {
            Remove-Item -Force $LockFile
        }
    }

    try {
        $InstallOutput = & composer install --no-dev --optimize-autoloader --no-interaction 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($InstallOutput) {
                Write-Err ($InstallOutput | Out-String).Trim()
            }
            Write-Fatal "Composer install failed. Run manually: cd $COQUI_INSTALL_DIR; composer install --no-dev"
        }
    } catch {
        throw
    }

    Write-Success "Dependencies installed"
}

# ─── Wrapper ─────────────────────────────────────────────────────────────────

function Create-SymlinkWrapper {
    $BinDir = Get-UserBinDir
    $CoquiPhpscript = Join-Path $COQUI_INSTALL_DIR "bin\coqui"

    # Create coqui.bat to wrap the PHP proxy
    $CoquiBat = Join-Path $BinDir "coqui.bat"

    Write-Status "Creating executable wrapper..."

    $WrapperContent = "@php `"$CoquiPhpscript`" %*"
    Set-Content -Path $CoquiBat -Value $WrapperContent

    Write-Success "Wrapper created: $CoquiBat"
}

# ─── Usage ───────────────────────────────────────────────────────────────────

function Show-Usage {
    Write-Host "Usage: .\install.ps1 [flags]"
    Write-Host ""
    Write-Host "Downloads and installs Coqui on Windows."
    Write-Host ""
    Write-Host "  irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex"
    Write-Host ""
    Write-Host "Flags:"
    Write-Host "  -Dev                 Clone the git repository instead of downloading a release"
    Write-Host "  -Quiet               Minimal output (milestones and errors only)"
    Write-Host "  -Help                Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\install.ps1                # Install latest release"
    Write-Host "  .\install.ps1 -Dev           # Install from git (development)"
    Write-Host "  .\install.ps1 -Quiet         # Install with minimal output"
}

# ─── Banner ──────────────────────────────────────────────────────────────────

function Show-Banner {
    if ($script:QUIET_MODE) { return }
    Write-Host ""
    Write-Host -Object "   ▄▄·       .▄▄▄  ▄• ▄▌▪  ▄▄▄▄·       ▄▄▄▄▄" -ForegroundColor Green
    Write-Host -Object "  ▐█ ▌▪▪     ▐▀•▀█ █▪██▌██ ▐█ ▀█▪▪     •██  " -ForegroundColor Green
    Write-Host -Object "  ██ ▄▄ ▄█▀▄ █▌·.█▌█▌▐█▌▐█·▐█▀▀█▄ ▄█▀▄  ▐█.▪" -ForegroundColor Green
    Write-Host -Object "  ▐███▌▐█▌.▐▌▐█▪▄█·▐█▄█▌▐█▌██▄▪▐█▐█▌.▐▌ ▐█▌·" -ForegroundColor Green
    Write-Host -Object "  ·▀▀▀  ▀█▄▀▪·▀▀█.  ▀▀▀ ▀▀▀·▀▀▀▀  ▀█▄▀▪ ▀▀▀ " -ForegroundColor Green
    Write-Host ""
    Write-Host "  Coqui Installer (Windows)"
    Write-Host ""
}

# ─── Success message ─────────────────────────────────────────────────────────

function Print-Success {
    param([string]$InstallType)

    $VersionInfo = ""
    if ($script:LATEST_VERSION) {
        $VersionInfo = " v$($script:LATEST_VERSION)"
    } else {
        $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
        if (Test-Path $VersionFile) {
            $VersionInfo = " v$((Get-Content -Path $VersionFile -Raw).Trim())"
        }
    }

    if ($script:QUIET_MODE) {
        Write-Milestone "${InstallType} complete!${VersionInfo}"
        return
    }

    Write-Host ""
    Write-Host "  ------------------------------------------"
    Write-Host -Object "  ${InstallType} complete!${VersionInfo}" -ForegroundColor Green
    Write-Host "  ------------------------------------------"
    Write-Host ""
    Write-Host "  Get started:"
    Write-Host ""
    Write-Host "    coqui"
    Write-Host ""
    Write-Host "  Add cloud providers (optional):"
    Write-Host ""
    Write-Host "    `$env:OPENAI_API_KEY=`"sk-...`""
    Write-Host "    `$env:ANTHROPIC_API_KEY=`"sk-ant-...`""
    Write-Host ""
    Write-Host "  Docs:  https://github.com/AgentCoqui/coqui"
    Write-Host ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

function Main {
    if ($script:HELP_MODE) {
        Show-Usage
        return
    }

    Show-Banner

    $OriginalDir = Get-Location

    try {
        if ($script:DEV_MODE) {
            # Dev mode: git clone workflow
            if (Test-DevInstalled) {
                Write-Host "  $([char]0x25B8) Existing dev installation found at $COQUI_INSTALL_DIR"
                Write-Host ""

                Check-Php
                Check-Extensions
                Check-Composer

                Update-Dev
                Create-SymlinkWrapper

                Print-Success "Update"
            } else {
                if (Test-ReleaseInstalled) {
                    Write-Host ""
                    Write-Warn "A release installation was found at $COQUI_INSTALL_DIR"
                    Write-Host "  Remove it first to switch to dev mode:"
                    Write-Host "    Remove-Item -Recurse -Force $COQUI_INSTALL_DIR"
                    Write-Host ""
                    Write-Fatal "Cannot install dev over a release installation."
                }

                Check-Php
                Check-Extensions
                Check-Git
                Check-Composer

                Install-Dev
                Create-SymlinkWrapper

                Print-Success "Installation"
            }
        } else {
            # Release mode (default): download pre-built archive
            if (Test-DevInstalled) {
                Write-Host ""
                Write-Warn "A development (git) installation was found at $COQUI_INSTALL_DIR"
                Write-Host "  To update it, re-run with -Dev"
                Write-Host "  To switch to release mode, remove it first:"
                Write-Host "    Remove-Item -Recurse -Force $COQUI_INSTALL_DIR"
                Write-Host ""
                Write-Fatal "Cannot install release over a dev installation."
            }

            if (Test-ReleaseInstalled) {
                Write-Host "  $([char]0x25B8) Existing installation found at $COQUI_INSTALL_DIR"
                Write-Host ""

                Check-Php
                Check-Extensions

                Update-Release
                Create-SymlinkWrapper

                Print-Success "Update"
            } else {
                Check-Php
                Check-Extensions

                Install-Release
                Create-SymlinkWrapper

                Print-Success "Installation"
            }
        }
    } finally {
        Set-Location $OriginalDir
    }
}

# Run — the try/catch prevents unhandled throw from Write-Fatal from
# propagating ugly red text. We do NOT use "exit 1" here because that
# would kill the user's PowerShell session when run via irm | iex.
try {
    Main
} catch {
    if (-not $script:HadError) {
        # Unexpected error (not from Write-Fatal) — show it
        Write-Err "An unexpected error occurred: $_"
    }
    Write-Host ""
    Write-Host "  Need help? https://github.com/AgentCoqui/coqui/issues"
    Write-Host ""
}
