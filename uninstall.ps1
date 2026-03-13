<#
.SYNOPSIS
    Coqui Uninstaller for Windows
    https://github.com/AgentCoqui/coqui

.DESCRIPTION
    Removes Coqui and associated files from a Windows system.
    Optionally removes PHP and Composer with the -All flag.

.PARAMETER KeepWorkspace
    Preserve the workspace directory during uninstallation.

.PARAMETER Force
    Skip all confirmation prompts.

.PARAMETER All
    Also remove PHP and Composer installed by Coqui.

.PARAMETER Quiet
    Minimal output (milestones and errors only).

.PARAMETER Help
    Show usage instructions.

.EXAMPLE
    # Interactive uninstall
    .\uninstall.ps1

.EXAMPLE
    # Keep workspace data
    .\uninstall.ps1 -KeepWorkspace

.EXAMPLE
    # Remove everything without prompts
    .\uninstall.ps1 -Force

.EXAMPLE
    # Remove everything including PHP and Composer
    .\uninstall.ps1 -Force -All
#>

param(
    [switch]$KeepWorkspace,
    [switch]$Force,
    [switch]$All,
    [switch]$Quiet,
    [switch]$Help
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$script:HadError = $false

# ─── Configuration (override via environment variables) ──────────────────────

$COQUI_INSTALL_DIR = if ($env:COQUI_INSTALL_DIR) { $env:COQUI_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".coqui" }

# PHP version that was installed by the Coqui installer
$PHP_MAJOR = 8
$PHP_MINOR = 4

# Mode flags
$script:KEEP_WORKSPACE = $KeepWorkspace.IsPresent
$script:FORCE_MODE = $Force.IsPresent
$script:ALL_MODE = $All.IsPresent
$script:QUIET_MODE = $Quiet.IsPresent

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

function Write-Progress {
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
    throw "CoquiUninstallerError: $Message"
}

# ─── Utility functions ───────────────────────────────────────────────────────

function Test-Command {
    param([string]$CommandName)
    $null = Get-Command $CommandName -ErrorAction SilentlyContinue
    return $?
}

function Confirm-Action {
    param(
        [string]$Prompt = "Continue?",
        [string]$Default = "yes"
    )

    # Force mode — assume yes
    if ($script:FORCE_MODE) { return $true }

    if ($Default -eq "no") {
        $suffix = "[y/N]"
    } else {
        $suffix = "[Y/n]"
    }

    $reply = Read-Host "  $([char]0x25B8) $Prompt $suffix"

    if ($Default -eq "no") {
        return ($reply -match '^[yY]')
    } else {
        return -not ($reply -match '^[nN]')
    }
}

# ─── Usage ───────────────────────────────────────────────────────────────────

function Show-Usage {
    Write-Host "Usage: .\uninstall.ps1 [flags]"
    Write-Host ""
    Write-Host "Removes Coqui and associated files from your system."
    Write-Host ""
    Write-Host "Flags:"
    Write-Host "  -KeepWorkspace       Preserve the workspace directory"
    Write-Host "  -Force               Skip all confirmation prompts"
    Write-Host "  -All                 Also remove PHP and Composer installed by Coqui"
    Write-Host "  -Quiet               Minimal output (milestones and errors only)"
    Write-Host "  -Help                Show this help"
    Write-Host ""
    Write-Host "By default, the uninstaller prompts before deleting the workspace"
    Write-Host "(default: keep) and does NOT remove PHP or Composer."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\uninstall.ps1                    # Interactive uninstall"
    Write-Host "  .\uninstall.ps1 -KeepWorkspace     # Keep workspace data"
    Write-Host "  .\uninstall.ps1 -Force             # No prompts, remove Coqui + workspace"
    Write-Host "  .\uninstall.ps1 -Force -All        # No prompts, remove everything"
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

# ─── Wrapper and PATH removal ────────────────────────────────────────────────

function Remove-CoquiWrapper {
    $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"
    $CoquiBat = Join-Path $CoquiBinDir "coqui.bat"

    Write-Status "Checking for Coqui wrapper..."

    if (Test-Path $CoquiBat) {
        Remove-Item -Path $CoquiBat -Force
        Write-Success "Removed wrapper: $CoquiBat"
    } else {
        Write-Status "No wrapper found at $CoquiBat"
    }

    # If --all, also remove Composer files from the Coqui bin directory
    if ($script:ALL_MODE) {
        $ComposerBat = Join-Path $CoquiBinDir "composer.bat"
        $ComposerPhar = Join-Path $CoquiBinDir "composer.phar"

        if (Test-Path $ComposerBat) {
            Remove-Item -Path $ComposerBat -Force
            Write-Success "Removed Composer wrapper: $ComposerBat"
        }
        if (Test-Path $ComposerPhar) {
            Remove-Item -Path $ComposerPhar -Force
            Write-Success "Removed Composer binary: $ComposerPhar"
        }
    }

    # Remove the Coqui bin directory if empty
    if ((Test-Path $CoquiBinDir) -and ((Get-ChildItem -Path $CoquiBinDir -Force | Measure-Object).Count -eq 0)) {
        Remove-Item -Path $CoquiBinDir -Force
        # Also clean up parent directories if empty
        $CoquiProgramDir = Split-Path $CoquiBinDir
        if ((Test-Path $CoquiProgramDir) -and ((Get-ChildItem -Path $CoquiProgramDir -Force | Measure-Object).Count -eq 0)) {
            Remove-Item -Path $CoquiProgramDir -Force
        }
        Write-Success "Removed empty directory: $CoquiBinDir"
    }
}

function Remove-CoquiFromPath {
    $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"

    Write-Status "Cleaning PATH..."

    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ([string]::IsNullOrWhiteSpace($UserPath)) {
        Write-Status "User PATH is empty, nothing to clean"
        return
    }

    # Split, filter out Coqui bin dir, rejoin
    $PathEntries = $UserPath -split ';' | Where-Object {
        $_.Trim() -ne "" -and $_.Trim() -ne $CoquiBinDir
    }
    $NewPath = ($PathEntries -join ';')

    if ($NewPath -ne $UserPath) {
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
        # Also update current session
        $MachinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $env:PATH = "$MachinePath;$NewPath"
        Write-Success "Removed Coqui bin directory from PATH"
    } else {
        Write-Status "Coqui bin directory not found in PATH"
    }
}

# ─── Install directory removal ───────────────────────────────────────────────

function Remove-InstallDir {
    if (-not (Test-Path $COQUI_INSTALL_DIR)) {
        Write-Status "Install directory not found: $COQUI_INSTALL_DIR"
        return
    }

    $VersionInfo = ""
    if (Test-DevInstalled) {
        $VersionInfo = " (dev mode)"
    } elseif (Test-ReleaseInstalled) {
        $Version = Get-InstalledVersion
        if ($Version) {
            $VersionInfo = " v$Version"
        }
    }

    Write-Status "Found Coqui installation${VersionInfo} at $COQUI_INSTALL_DIR"

    $WorkspaceDir = Join-Path $COQUI_INSTALL_DIR ".workspace"
    $DeleteWorkspace = $false

    if ($script:KEEP_WORKSPACE) {
        # Explicit flag: keep workspace
        Write-Status "Workspace will be preserved (-KeepWorkspace)"
    } elseif ($script:FORCE_MODE) {
        # Force mode without -KeepWorkspace: delete workspace
        $DeleteWorkspace = $true
    } elseif (Test-Path $WorkspaceDir) {
        # Interactive: prompt user (default is to keep)
        Write-Host ""
        Write-Host "  Workspace directory: $WorkspaceDir"
        Write-Host "  Contains session data, installed packages, and agent configuration."
        Write-Host ""
        if (Confirm-Action -Prompt "Delete workspace data?" -Default "no") {
            $DeleteWorkspace = $true
        } else {
            Write-Status "Workspace will be preserved"
        }
    }

    if ($DeleteWorkspace -or ($script:FORCE_MODE -and -not $script:KEEP_WORKSPACE)) {
        # Delete everything
        Write-Status "Removing $COQUI_INSTALL_DIR..."
        Remove-Item -Path $COQUI_INSTALL_DIR -Recurse -Force
        Write-Success "Removed $COQUI_INSTALL_DIR"
    } else {
        # Keep workspace: remove everything except .workspace
        Write-Status "Removing Coqui files (preserving workspace)..."

        if (Test-Path $WorkspaceDir) {
            # Move workspace to temp, delete dir, move workspace back
            $TempDir = Join-Path $env:TEMP "coqui-uninstall-$(Get-Random)"
            New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
            Move-Item -Path $WorkspaceDir -Destination (Join-Path $TempDir ".workspace") -Force

            Remove-Item -Path $COQUI_INSTALL_DIR -Recurse -Force

            New-Item -ItemType Directory -Force -Path $COQUI_INSTALL_DIR | Out-Null
            Move-Item -Path (Join-Path $TempDir ".workspace") -Destination $WorkspaceDir -Force
            Remove-Item -Path $TempDir -Recurse -Force

            Write-Success "Removed Coqui files (workspace preserved at $WorkspaceDir)"
        } else {
            # No workspace directory exists
            Remove-Item -Path $COQUI_INSTALL_DIR -Recurse -Force
            Write-Success "Removed $COQUI_INSTALL_DIR"
        }
    }
}

# ─── PHP removal ────────────────────────────────────────────────────────────

function Remove-Php {
    if (-not (Test-Command "php")) {
        Write-Status "PHP is not installed"
        return
    }

    $PhpVersion = "unknown"
    try {
        $PhpVersion = & php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;" 2>$null
    } catch {}

    if (-not $script:FORCE_MODE) {
        Write-Host ""
        Write-Warn "PHP $PhpVersion is installed on your system."
        Write-Host "  Other applications may depend on PHP. Removing it could break them."
        Write-Host ""
        if (-not (Confirm-Action -Prompt "Remove PHP $PhpVersion?" -Default "no")) {
            Write-Status "Keeping PHP"
            return
        }
    }

    Write-Status "Removing PHP..."

    if (Test-Command "winget") {
        & winget uninstall --id "PHP.PHP.${PHP_MAJOR}.${PHP_MINOR}" --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "PHP removed via winget"
        } else {
            Write-Warn "winget could not remove PHP. You may need to remove it manually."
            Write-Host "  Settings > Apps > Installed apps > PHP"
        }
    } else {
        Write-Warn "winget is not available. Please remove PHP manually."
        Write-Host "  Settings > Apps > Installed apps > PHP"
    }
}

# ─── Composer removal ────────────────────────────────────────────────────────

function Remove-Composer {
    if (-not (Test-Command "composer")) {
        Write-Status "Composer is not installed"
        return
    }

    if (-not $script:FORCE_MODE) {
        Write-Host ""
        Write-Warn "Composer is installed on your system."
        Write-Host "  Other PHP projects may depend on Composer."
        Write-Host ""
        if (-not (Confirm-Action -Prompt "Remove Composer?" -Default "no")) {
            Write-Status "Keeping Composer"
            return
        }
    }

    Write-Status "Removing Composer..."

    # The Coqui installer places Composer in the Coqui bin directory.
    # If it's elsewhere (e.g. installed globally by the user), leave it alone.
    $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"
    $ComposerBat = Join-Path $CoquiBinDir "composer.bat"
    $ComposerPhar = Join-Path $CoquiBinDir "composer.phar"

    if (Test-Path $ComposerBat) {
        Remove-Item -Path $ComposerBat -Force
    }
    if (Test-Path $ComposerPhar) {
        Remove-Item -Path $ComposerPhar -Force
    }
    Write-Success "Removed Composer from Coqui bin directory"

    # Remove Composer cache directory
    $ComposerHome = if ($env:COMPOSER_HOME) { $env:COMPOSER_HOME } else { Join-Path $env:APPDATA "Composer" }
    if (Test-Path $ComposerHome) {
        if ($script:FORCE_MODE) {
            Remove-Item -Path $ComposerHome -Recurse -Force
            Write-Success "Removed Composer cache: $ComposerHome"
        } else {
            if (Confirm-Action -Prompt "Remove Composer cache ($ComposerHome)?" -Default "no") {
                Remove-Item -Path $ComposerHome -Recurse -Force
                Write-Success "Removed Composer cache: $ComposerHome"
            } else {
                Write-Status "Keeping Composer cache"
            }
        }
    }
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
    Write-Host "  Coqui Uninstaller (Windows)"
    Write-Host ""
}

# ─── Summary ─────────────────────────────────────────────────────────────────

function Print-Summary {
    if ($script:QUIET_MODE) {
        Write-Progress "Uninstall complete"
        return
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────"
    Write-Host -Object "  Uninstall complete!" -ForegroundColor Green
    Write-Host "  ──────────────────────────────────────────"

    $WorkspaceDir = Join-Path $COQUI_INSTALL_DIR ".workspace"
    if (Test-Path $WorkspaceDir) {
        Write-Host ""
        Write-Host "  Workspace preserved:"
        Write-Host ""
        Write-Host "    $WorkspaceDir"
        Write-Host ""
        Write-Host "  To remove it later:"
        Write-Host ""
        Write-Host "    Remove-Item -Recurse -Force $COQUI_INSTALL_DIR"
    }

    if (-not $script:ALL_MODE) {
        $HasNote = $false
        if (Test-Command "php") {
            if (-not $HasNote) {
                Write-Host ""
                Write-Host "  Still installed:"
                $HasNote = $true
            }
            Write-Host "    PHP (re-run with -All to remove)"
        }
        if (Test-Command "composer") {
            if (-not $HasNote) {
                Write-Host ""
                Write-Host "  Still installed:"
                $HasNote = $true
            }
            Write-Host "    Composer (re-run with -All to remove)"
        }
    }

    Write-Host ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

function Main {
    if ($Help.IsPresent) {
        Show-Usage
        return
    }

    Show-Banner

    # Check if Coqui is installed
    if (-not (Test-Path $COQUI_INSTALL_DIR)) {
        Write-Warn "Coqui is not installed at $COQUI_INSTALL_DIR"
        Write-Host ""
        Write-Host "  If you installed to a custom directory, set COQUI_INSTALL_DIR:"
        Write-Host "    `$env:COQUI_INSTALL_DIR = 'C:\path\to\coqui'; .\uninstall.ps1"
        Write-Host ""
        return
    }

    # Confirm uninstall (unless -Force)
    if (-not $script:FORCE_MODE) {
        Write-Host "  This will remove Coqui from: $COQUI_INSTALL_DIR"
        Write-Host ""
        if (-not (Confirm-Action -Prompt "Proceed with uninstall?")) {
            Write-Host ""
            Write-Host "  Uninstall cancelled."
            Write-Host ""
            return
        }
        Write-Host ""
    }

    # 1. Remove wrapper and clean PATH
    Remove-CoquiWrapper
    Remove-CoquiFromPath

    # 2. Remove the install directory (with workspace logic)
    Remove-InstallDir

    # 3. Optionally remove PHP and Composer (-All only)
    if ($script:ALL_MODE) {
        Remove-Php
        Remove-Composer
    }

    # 4. Print summary
    Print-Summary
}

# Run — the try/catch prevents unhandled throw from Write-Fatal from
# propagating ugly red text. We do NOT use "exit 1" here because that
# would kill the user's PowerShell session when run via irm | iex.
try {
    Main
} catch {
    if (-not $script:HadError) {
        Write-Err "An unexpected error occurred: $_"
    }
    Write-Host ""
    Write-Host "  Need help? https://github.com/AgentCoqui/coqui/issues"
    Write-Host ""
}
