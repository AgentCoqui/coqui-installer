<#
.SYNOPSIS
    Coqui Installer for Windows
    https://github.com/AgentCoqui/coqui

.DESCRIPTION
    Installs PHP, Composer, Git, and Coqui on a Windows system.
    Creates a coqui.bat wrapper in your user path for easy execution.

.EXAMPLE
    irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex
#>

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$script:HadError = $false

# ─── Configuration (override via environment variables) ──────────────────────

$COQUI_REPO = if ($env:COQUI_REPO) { $env:COQUI_REPO } else { "https://github.com/AgentCoqui/coqui.git" }
$COQUI_INSTALL_DIR = if ($env:COQUI_INSTALL_DIR) { $env:COQUI_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".coqui" }
$COQUI_VERSION = if ($env:COQUI_VERSION) { $env:COQUI_VERSION } else { "" }

# Minimum PHP version required
$REQUIRED_PHP_MAJOR = 8
$REQUIRED_PHP_MINOR = 4

# PHP extensions required by Coqui and php-agents
$REQUIRED_EXTENSIONS = @("curl", "mbstring", "openssl", "pdo_sqlite", "xml", "zip")

# ─── Output helpers ──────────────────────────────────────────────────────────

function Write-Status {
    param([string]$Message)
    Write-Host -Object "  $([char]0x25B8) $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host -Object "  $([char]0x2713) $Message" -ForegroundColor Green
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

    Write-Status "Installing PHP via winget..."
    & winget install --id PHP.PHP.${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
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

    Write-Success "PHP installed via winget"
}

# ─── PHP checks ──────────────────────────────────────────────────────────────

function Check-Php {
    Write-Status "Checking PHP..."

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
        Invoke-WebRequest -Uri "https://getcomposer.org/installer" -OutFile $TempScript -ErrorAction Stop
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

# ─── Coqui install / update ──────────────────────────────────────────────────

function Test-CoquiInstalled {
    $GitPath = Join-Path $COQUI_INSTALL_DIR ".git"
    return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $GitPath)
}

function Install-Coqui {
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

function Update-Coqui {
    Write-Status "Checking for updates..."

    Set-Location $COQUI_INSTALL_DIR

    & git fetch --quiet 2>&1 | Out-Null

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
        Run-ComposerInstall
        return
    }

    Write-Status "Updating Coqui..."
    & git pull --ff-only --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fatal "Failed to update. Try removing $COQUI_INSTALL_DIR and re-running."
    }
    Write-Success "Coqui updated"
    Run-ComposerInstall
}

function Run-ComposerInstall {
    Write-Status "Installing dependencies..."

    Set-Location $COQUI_INSTALL_DIR
    try {
        $InstallOutput = & composer install --no-dev --optimize-autoloader --no-interaction 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($InstallOutput) {
                Write-Err ($InstallOutput | Out-String).Trim()
            }
            Write-Fatal "Composer install failed."
        }
    } catch {
        throw
    }

    Write-Success "Dependencies installed"
}

# ─── Configuration ───────────────────────────────────────────────────────────

function Setup-Config {
    $ConfigFile = Join-Path $COQUI_INSTALL_DIR "openclaw.json"

    if (Test-Path $ConfigFile) {
        Write-Success "Configuration file exists (preserved)"
        return
    }

    Write-Status "Creating default configuration..."

    $ConfigJson = @"
{
    "agents": {
        "defaults": {
            "workspace": ".workspace",
            "models": {
                "ollama/qwen3:latest": { "alias": "qwen" },
                "ollama/qwen3-coder:latest": { "alias": "coder" },
                "ollama/glm-4.7-flash:latest": { "alias": "glm" },
                "ollama/llama3.2:latest": { "alias": "llama" }
            },
            "model": {
                "primary": "ollama/glm-4.7-flash:latest",
                "fallbacks": ["ollama/qwen3-coder:latest"]
            },
            "roles": {
                "orchestrator": "ollama/glm-4.7-flash:latest",
                "coder": "ollama/qwen3-coder:latest",
                "reviewer": "ollama/qwen3:latest"
            }
        }
    },
    "models": {
        "providers": {
            "ollama": {
                "baseUrl": "http://localhost:11434/v1",
                "apiKey": "ollama-local",
                "api": "openai-completions",
                "models": [
                    {
                        "id": "qwen3:latest",
                        "name": "Qwen 3",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "qwen3-coder:latest",
                        "name": "Qwen 3 Coder",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "glm-4.7-flash:latest",
                        "name": "GLM 4.7 Flash",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 8192
                    },
                    {
                        "id": "llama3.2:latest",
                        "name": "Llama 3.2",
                        "reasoning": false,
                        "input": ["text"],
                        "contextWindow": 128000,
                        "maxTokens": 4096
                    }
                ]
            }
        }
    }
}
"@

    Set-Content -Path $ConfigFile -Value $ConfigJson
    Write-Success "Default configuration created (Ollama local provider)"
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

# ─── Banner ──────────────────────────────────────────────────────────────────

function Show-Banner {
    Write-Host ""
    Write-Host -Object "  ▄█████  ▄▄▄   ▄▄▄  ▄▄ ▄▄ ▄▄   █████▄  ▄▄▄ ▄▄▄▄▄▄" -ForegroundColor Green
    Write-Host -Object "  ██     ██▀██ ██▀██ ██ ██ ██   ██▄▄██ ██▀██  ██  " -ForegroundColor Green
    Write-Host -Object "  ▀█████ ▀███▀ ▀███▀ ▀███▀ ██   ██▄▄█▀ ▀███▀  ██  " -ForegroundColor Green
    Write-Host -Object "                  ▀▀                              " -ForegroundColor Green
    Write-Host ""
    Write-Host "  Coqui Installer (Windows)"
    Write-Host ""
}

# ─── Success message ─────────────────────────────────────────────────────────

function Print-Success {
    param([string]$InstallType)

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────"
    Write-Host -Object "  ${InstallType} complete!" -ForegroundColor Green
    Write-Host "  ──────────────────────────────────────────"
    Write-Host ""
    Write-Host "  Get started:"
    Write-Host ""
    Write-Host "    coqui"
    Write-Host ""
    Write-Host "  Configuration:"
    Write-Host ""
    Write-Host "    $COQUI_INSTALL_DIR\openclaw.json"
    Write-Host ""
    Write-Host "  Add cloud providers (optional):"
    Write-Host ""
    Write-Host "    `$env:OPENAI_API_KEY=`"sk-...`""
    Write-Host "    `$env:ANTHROPIC_API_KEY=`"sk-ant-...`""
    Write-Host ""
    Write-Host "  Prerequisites:"
    Write-Host ""
    Write-Host "    Make sure Ollama is running:  ollama serve"
    Write-Host "    Pull a model:                 ollama pull glm-4.7-flash"
    Write-Host ""
    Write-Host "  Docs:  https://github.com/AgentCoqui/coqui"
    Write-Host ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

function Main {
    Show-Banner

    $OriginalDir = Get-Location

    try {
        if (Test-CoquiInstalled) {
            Write-Host "  $([char]0x25B8) Existing installation found at $COQUI_INSTALL_DIR"
            Write-Host ""

            Check-Php
            Check-Extensions
            Check-Composer

            Update-Coqui
            Setup-Config
            Create-SymlinkWrapper

            Print-Success "Update"
        } else {
            Check-Php
            Check-Extensions
            Check-Git
            Check-Composer

            Install-Coqui
            Setup-Config
            Create-SymlinkWrapper

            Print-Success "Installation"
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
