<#
.SYNOPSIS
    Coqui Installer for Windows
    https://github.com/AgentCoqui/coqui

    Terminal AI agent with multi-model orchestration, persistent sessions,
    and runtime extensibility via Composer.

.DESCRIPTION
    Installs PHP, Composer, Git, and Coqui on a Windows system.
    Creates a coqui.bat wrapper in your user path for easy execution.

.EXAMPLE
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | Invoke-Expression

.PARAMETER InstallPhp
    Install/check PHP 8.4+ and extensions

.PARAMETER InstallComposer
    Install/check Composer

.PARAMETER InstallCoqui
    Install/update Coqui and create alias

.PARAMETER NonInteractive
    Skip all confirmation prompts (assume yes)

.PARAMETER Help
    Show this help message
#>
[CmdletBinding()]
param(
    [switch]$InstallPhp,
    [switch]$InstallComposer,
    [switch]$InstallCoqui,
    [switch]$NonInteractive,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ─── Configuration (override via environment variables) ──────────────────────

$COQUI_REPO = if ($env:COQUI_REPO) { $env:COQUI_REPO } else { "https://github.com/AgentCoqui/coqui.git" }
$COQUI_INSTALL_DIR = if ($env:COQUI_INSTALL_DIR) { $env:COQUI_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".coqui" }
$COQUI_VERSION = if ($env:COQUI_VERSION) { $env:COQUI_VERSION } else { "" }

# Minimum PHP version required
$REQUIRED_PHP_MAJOR = 8
$REQUIRED_PHP_MINOR = 4

# PHP extensions required by Coqui and php-agents
$REQUIRED_EXTENSIONS = @("curl", "mbstring", "pdo_sqlite", "xml", "zip")

# ─── Mode flags ──────────────────────────────────────────────────────────────

$SELECTIVE_MODE = $InstallPhp -or $InstallComposer -or $InstallCoqui

if (-not $SELECTIVE_MODE) {
    $InstallPhp = $true
    $InstallComposer = $true
    $InstallCoqui = $true
}

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

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
    exit 1
}

# ─── Utility functions ───────────────────────────────────────────────────────

function Test-Command {
    param([string]$CommandName)
    try {
        $null = Get-Command $CommandName -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Confirm-Action {
    param([string]$PromptMessage = "Continue?")
    
    if ($NonInteractive) {
        return $true
    }

    $Title = "Confirmation Required"
    $Choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Continue with the action."),
        (New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel the action.")
    )

    $Decision = $Host.UI.PromptForChoice($Title, "  $([char]0x25B8) $PromptMessage", $Choices, 0)
    return $Decision -eq 0
}

function Get-UserBinDir {
    # Check if LocalAppData\Microsoft\WindowsApps exists (usually in PATH for Windows 10/11)
    $WindowsAppsDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    if (Test-Path $WindowsAppsDir) {
        return $WindowsAppsDir
    }
    
    # Fallback to AppData\Local\Programs\Coqui\bin
    $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"
    if (-not (Test-Path $CoquiBinDir)) {
        New-Item -ItemType Directory -Force -Path $CoquiBinDir | Out-Null
    }
    
    # Check if it's in PATH
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not ($UserPath -like "*$CoquiBinDir*")) {
        [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$CoquiBinDir", "User")
        $env:PATH = "$env:PATH;$CoquiBinDir"
        Write-Warn "Added $CoquiBinDir to your PATH. You may need to restart your terminal later."
    }

    return $CoquiBinDir
}

# ─── PHP checks ──────────────────────────────────────────────────────────────

function Check-Php {
    Write-Status "Checking PHP..."

    if (-not (Test-Command "php")) {
        Write-Warn "PHP is not installed or not in PATH."
        Install-Php
        return
    }

    $PhpVersionOutput = php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;'
    $parts = $PhpVersionOutput.Split('.')
    if ($parts.Length -lt 2) {
        Write-Warn "Could not determine PHP version."
        Install-Php
        return
    }

    $PhpMajor = [int]$parts[0]
    $PhpMinor = [int]$parts[1]

    if ($PhpMajor -lt $REQUIRED_PHP_MAJOR -or ($PhpMajor -eq $REQUIRED_PHP_MAJOR -and $PhpMinor -lt $REQUIRED_PHP_MINOR)) {
        Write-Warn "PHP $PhpVersionOutput found, but PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required."
        Install-Php
        return
    }

    Write-Success "PHP $PhpVersionOutput"
}

function Install-Php {
    Write-Host ""
    Write-Host "  Please install PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ with the required extensions."
    Write-Host "  See: https://windows.php.net/download/"
    Write-Host ""
    if (Test-Command "winget") {
        Write-Host "  You can try installing PHP via winget:"
        Write-Host "    winget install --id PHP.PHP --version ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR} --source winget"
        Write-Host ""
        Write-Host "  Make sure to add the PHP directory to your system PATH!"
    }
    Write-Host ""
    Write-Fatal ("PHP ${REQUIRED_PHP_MAJOR}.${REQUIRED_PHP_MINOR}+ is required.")
}

# ─── Extension checks ────────────────────────────────────────────────────────

function Check-Extensions {
    Write-Status "Checking PHP extensions..."

    $Missing = @()
    try {
        $Loaded = php -m 2>$null
    } catch {
        Write-Fatal "Failed to execute 'php -m'."
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

    $MissingList = $Missing -join ", "
    Write-Warn "Missing PHP extensions: $MissingList"
    Write-Host ""
    Write-Host "  Please locate your php.ini file (run 'php --ini' to find it)."
    Write-Host "  Open it and uncomment (remove the semicolon before) the following lines:"
    foreach ($Ext in $Missing) {
        Write-Host "    extension=$Ext"
    }
    Write-Host ""
    Write-Host "  Also ensure 'extension_dir = `"ext`"' is uncommented and points to the right path."
    Write-Host ""
    
    if (-not (Confirm-Action "Ignore missing extensions warning and continue?")) {
        Write-Fatal "Required PHP extensions missing: $MissingList."
    }
}

# ─── Git check ───────────────────────────────────────────────────────────────

function Check-Git {
    Write-Status "Checking git..."

    if (Test-Command "git") {
        $GitVersion = (git --version).Split(' ')[2]
        Write-Success "git $GitVersion"
        return
    }

    Write-Host ""
    Write-Host "  Git is required but missing."
    if (Test-Command "winget") {
        Write-Host "  You can try installing Git via winget:"
        Write-Host "    winget install -e --id Git.Git"
    } else {
        Write-Host "  Download it from: https://git-scm.com/download/win"
    }
    Write-Host ""
    Write-Fatal "git is required. Please install it and re-run the installer."
}

# ─── Composer check ──────────────────────────────────────────────────────────

function Check-Composer {
    Write-Status "Checking Composer..."

    if (Test-Command "composer") {
        # Strip newline/carriage returns from string
        $ComposerVersion = (((composer --version 2>$null) -split ' ')[2]).Trim()
        Write-Success "Composer $ComposerVersion"
        return
    }

    if (Confirm-Action "Composer not found. Install it now?") {
        Install-Composer
    } else {
        Write-Fatal "Composer is required."
    }
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
    $ComposerPhar = Join-Path $BinDir "composer.phar"
    
    try {
        php $TempScript --quiet --install-dir=$BinDir
    } catch {
        Remove-Item -Path $TempScript -Force -ErrorAction Ignore
        Write-Fatal "Composer installation script failed."
    }
    
    Remove-Item -Path $TempScript -Force -ErrorAction Ignore

    # Create composer.bat wrapper
    $ComposerBat = Join-Path $BinDir "composer.bat"
    Set-Content -Path $ComposerBat -Value "@php `"%~dp0composer.phar`" %*"

    Write-Success "Composer installed to $BinDir"
    
    # Validate the installation is now in PATH for this session
    if (-not (Test-Command "composer")) {
        # Temporarily alias composer to the bat file for the rest of this powershell session
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
        # Run git directly with standard output silenced
        & git $CloneArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fatal "Failed to clone Coqui repository."
        }
    } catch {
        Write-Fatal "Failed to clone Coqui repository."
    }

    Write-Success "Coqui cloned"

    Run-ComposerInstall
}

function Update-Coqui {
    Write-Status "Checking for updates..."

    Set-Location $COQUI_INSTALL_DIR
    
    & git fetch --quiet 2>&1 | Out-Null

    $LocalHead = (git rev-parse HEAD).Trim()
    $RemoteHead = ""
    try {
        $RemoteHead = (git rev-parse '@{u}' 2>$null).Trim()
    } catch {}
    
    if ([string]::IsNullOrWhiteSpace($RemoteHead)) {
        $RemoteHead = $LocalHead
    }

    if ($LocalHead -eq $RemoteHead) {
        Write-Success "Coqui is already up to date"
        Run-ComposerInstall
        return
    }

    if (Confirm-Action "A new version of Coqui is available. Update now?") {
        Write-Status "Updating Coqui..."
        & git pull --ff-only --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
             Write-Fatal "Failed to update. Try a clean install by clearing $COQUI_INSTALL_DIR."
        }
        Write-Success "Coqui updated"
        Run-ComposerInstall
    } else {
        Write-Success "Update skipped"
    }
}

function Run-ComposerInstall {
    Write-Status "Installing dependencies..."

    Set-Location $COQUI_INSTALL_DIR
    try {
        & composer install --no-dev --optimize-autoloader --no-interaction --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fatal "Composer install failed."
        }
    } catch {
       Write-Fatal "Composer install failed."
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

# ─── Symlink Wrapper ─────────────────────────────────────────────────────────

function Create-SymlinkWrapper {
    $BinDir = Get-UserBinDir
    $CoquiPhpscript = Join-Path $COQUI_INSTALL_DIR "bin\coqui"
    
    # Create coqui.bat to wrap the PHP proxy
    $CoquiBat = Join-Path $BinDir "coqui.bat"

    Write-Status "Creating executable wrapper in $BinDir..."

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
    Write-Host "  Add cloud providers (optional PowerShell):"
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
        # ── Selective mode: run only the requested components ──
        if ($SELECTIVE_MODE) {
            if ($InstallPhp) {
                Check-Php
                Check-Extensions
            }

            if ($InstallComposer) {
                if (-not (Test-Command "php")) {
                    Write-Fatal "PHP is required to install Composer. Install PHP manually and ensure it is in PATH."
                }
                Check-Composer
            }

            if ($InstallCoqui) {
                if (-not (Test-Command "php")) {
                    Write-Fatal "PHP is required to install Coqui."
                }
                if (-not (Test-Command "composer") -and -not (Test-Path $(Join-Path (Get-UserBinDir) "composer.bat"))) {
                    Write-Fatal "Composer is required to install Coqui."
                }
                Check-Git

                if (Test-CoquiInstalled) {
                    Update-Coqui
                } else {
                    Install-Coqui
                }
                Setup-Config
                Create-SymlinkWrapper
            }

            Write-Host ""
            Write-Success "Done"
            Write-Host ""
            return
        }

        # ── Full install ──
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

Main
