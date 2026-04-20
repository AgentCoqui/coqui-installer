<#
.SYNOPSIS
    Coqui WSL2 Bootstrap Installer for Windows
    https://github.com/AgentCoqui/coqui

.DESCRIPTION
    Installs Coqui using the supported WSL2-based Windows workflow.
    If WSL2 or the target distro is not ready yet, the script offers to install or
    upgrade it before running the normal bash installer inside WSL.

.PARAMETER Dev
    Use git clone instead of release download inside WSL.

.PARAMETER Distro
    WSL distro to use. Defaults to Ubuntu.

.EXAMPLE
    irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Dev
#>

param(
    [switch]$Dev,
    [switch]$Quiet,
    [switch]$Help,
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$script:HadError = $false
$script:TARGET_DISTRO = $Distro
$script:DEV_MODE = $Dev.IsPresent
$script:QUIET_MODE = $Quiet.IsPresent
$script:HELP_MODE = $Help.IsPresent
$script:INSTALL_SCRIPT_URL = if ($env:COQUI_INSTALL_SH_URL) { $env:COQUI_INSTALL_SH_URL } else { "https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh" }

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
    throw "CoquiWslBootstrapError: $Message"
}

function Confirm-Action {
    param([string]$Prompt, [string]$Default = "yes")

    if ($env:COQUI_WSL_BOOTSTRAP_ASSUME_YES -eq '1') { return $true }
    if ($env:COQUI_WSL_BOOTSTRAP_ASSUME_NO -eq '1') { return $false }

    $suffix = if ($Default -eq "no") { "[y/N]" } else { "[Y/n]" }

    try {
        $reply = Read-Host "  $([char]0x25B8) $Prompt $suffix"
    } catch {
        return $Default -ne "no"
    }

    if ($Default -eq "no") {
        return ($reply -match '^[yY]')
    }

    return -not ($reply -match '^[nN]')
}

function Get-WSLExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:COQUI_WSL_EXE)) {
        return $env:COQUI_WSL_EXE
    }

    foreach ($candidate in @('wsl.exe', 'wsl')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    return $null
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$InputText = ""
    )

    $output = @()
    $exitCode = 0

    try {
        if ($InputText -ne "") {
            $output = $InputText | & $FilePath @Arguments 2>&1
        } else {
            $output = & $FilePath @Arguments 2>&1
        }
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    } catch {
        $output = @($_.ToString())
        $exitCode = 1
    }

    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Invoke-WSL {
    param(
        [string[]]$Arguments = @(),
        [string]$InputText = ""
    )

    $wslExe = Get-WSLExecutable
    if ($null -eq $wslExe) {
        return [pscustomobject]@{
            Output = @("wsl.exe was not found on PATH.")
            ExitCode = 1
        }
    }

    return Invoke-ExternalCommand -FilePath $wslExe -Arguments $Arguments -InputText $InputText
}

function Write-CommandOutput {
    param([object]$Result)

    foreach ($line in @($Result.Output)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Host "    $line"
        }
    }
}

function Get-DistroVersion {
    param([object]$ListResult)

    if ($ListResult.ExitCode -ne 0) {
        return $null
    }

    $pattern = '^\s*\*?\s*' + [regex]::Escape($script:TARGET_DISTRO) + '\s+.+?\s+(?<version>[0-9]+)\s*$'
    foreach ($line in @($ListResult.Output)) {
        $text = [string]$line
        if ($text -match $pattern) {
            return [int]$Matches['version']
        }
    }

    return $null
}

function Test-BashReady {
    $result = Invoke-WSL -Arguments @('-d', $script:TARGET_DISTRO, '--', 'bash', '-lc', 'printf coqui-ready')
    return $result.ExitCode -eq 0 -and ((@($result.Output) -join "`n") -match 'coqui-ready')
}

function Write-SetupCompletionGuidance {
    Write-Host ""
    Write-Host "  Finish WSL setup, then re-run the same install command:"
    Write-Host ""
    Write-Host "    wsl -d $($script:TARGET_DISTRO)"
    Write-Host ""
    Write-Host "  If Windows asked for a restart, reboot first and then re-run install.ps1."
    Write-Host ""
}

function Ensure-WSLReady {
    $wslExe = Get-WSLExecutable
    if ($null -eq $wslExe) {
        Write-Fatal "WSL is not available on this machine. Install WSL2 first, then re-run this installer."
    }

    $listResult = Invoke-WSL -Arguments @('-l', '-v')
    $version = Get-DistroVersion -ListResult $listResult

    if ($version -eq 2) {
        if (Test-BashReady) {
            return
        }

        Write-Warn "WSL2 distro '$($script:TARGET_DISTRO)' exists but is not ready for non-interactive use yet."
        Write-SetupCompletionGuidance
        Write-Fatal "Complete the initial WSL distro setup, then re-run the installer."
    }

    if ($version -eq 1) {
        Write-Warn "WSL distro '$($script:TARGET_DISTRO)' is installed as WSL1."
        if (-not (Confirm-Action -Prompt "Upgrade '$($script:TARGET_DISTRO)' to WSL2 now?")) {
            Write-Fatal "Coqui requires WSL2 on Windows."
        }

        Write-Status "Upgrading '$($script:TARGET_DISTRO)' to WSL2..."
        $upgradeResult = Invoke-WSL -Arguments @('--set-version', $script:TARGET_DISTRO, '2')
        if ($upgradeResult.ExitCode -ne 0) {
            Write-CommandOutput -Result $upgradeResult
            Write-Fatal "Failed to upgrade '$($script:TARGET_DISTRO)' to WSL2."
        }

        if (Test-BashReady) {
            Write-Success "WSL2 distro '$($script:TARGET_DISTRO)' is ready"
            return
        }

        Write-SetupCompletionGuidance
        Write-Fatal "WSL2 upgrade completed, but the distro still needs first-launch setup."
    }

    Write-Warn "WSL2 distro '$($script:TARGET_DISTRO)' is not installed yet."
    if (-not (Confirm-Action -Prompt "Install WSL2 and the '$($script:TARGET_DISTRO)' distro now?")) {
        Write-Fatal "WSL2 setup is required for the supported Windows install path."
    }

    Write-Status "Installing WSL2 with distro '$($script:TARGET_DISTRO)'..."
    $installResult = Invoke-WSL -Arguments @('--install', '-d', $script:TARGET_DISTRO)
    if ($installResult.ExitCode -ne 0) {
        Write-CommandOutput -Result $installResult
        Write-Fatal "WSL installation failed."
    }

    if (Test-BashReady) {
        Write-Success "WSL2 distro '$($script:TARGET_DISTRO)' is ready"
        return
    }

    Write-Warn "WSL installation was started, but Windows still needs to finish setup."
    Write-SetupCompletionGuidance
    Write-Fatal "WSL2 setup is not complete yet."
}

function Get-InstallScriptContent {
    if (-not [string]::IsNullOrWhiteSpace($env:COQUI_INSTALL_SH_CONTENT)) {
        return $env:COQUI_INSTALL_SH_CONTENT
    }

    Write-Status "Downloading Coqui installer..."
    try {
        return (Invoke-WebRequest -Uri $script:INSTALL_SCRIPT_URL -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        Write-Fatal "Failed to download install.sh from $($script:INSTALL_SCRIPT_URL)."
    }
}

function Invoke-InstallerInWSL {
    $scriptContent = Get-InstallScriptContent
    $scriptArgs = @()

    if ($script:DEV_MODE) {
        $scriptArgs += '--dev'
    }

    if ($script:QUIET_MODE) {
        $scriptArgs += '--quiet'
    }

    Write-Status "Running Coqui installer inside WSL2 ($($script:TARGET_DISTRO))..."
    $arguments = @('-d', $script:TARGET_DISTRO, '--', 'bash', '-s', '--') + $scriptArgs
    $result = Invoke-WSL -Arguments $arguments -InputText $scriptContent

    if ($result.ExitCode -ne 0) {
        Write-CommandOutput -Result $result
        Write-Fatal "The Coqui installer failed inside WSL2."
    }

    Write-Success "Coqui installed inside WSL2"
}

function Show-Usage {
    Write-Host "Usage: .\install.ps1 [flags]"
    Write-Host ""
    Write-Host "Supported Windows install path for Coqui via WSL2."
    Write-Host ""
    Write-Host "One-liner:"
    Write-Host "  irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex"
    Write-Host ""
    Write-Host "Flags:"
    Write-Host "  -Dev                 Clone the git repository inside WSL instead of downloading a release"
    Write-Host "  -Quiet               Minimal output"
    Write-Host "  -Help                Show this help"
    Write-Host "  -Distro <name>       WSL distro to use (default: Ubuntu)"
    Write-Host ""
    Write-Host "This script checks for WSL2, offers to install it when needed, and then runs install.sh inside WSL."
}

function Show-Banner {
    if ($script:QUIET_MODE) { return }
    Write-Host ""
    Write-Host -Object "   ▄▄·       .▄▄▄  ▄• ▄▌▪  ▄▄▄▄·       ▄▄▄▄▄" -ForegroundColor Green
    Write-Host -Object "  ▐█ ▌▪▪     ▐▀•▀█ █▪██▌██ ▐█ ▀█▪▪     •██  " -ForegroundColor Green
    Write-Host -Object "  ██ ▄▄ ▄█▀▄ █▌·.█▌█▌▐█▌▐█·▐█▀▀█▄ ▄█▀▄  ▐█.▪" -ForegroundColor Green
    Write-Host -Object "  ▐███▌▐█▌.▐▌▐█▪▄█·▐█▄█▌▐█▌██▄▪▐█▐█▌.▐▌ ▐█▌·" -ForegroundColor Green
    Write-Host -Object "  ·▀▀▀  ▀█▄▀▪·▀▀█.  ▀▀▀ ▀▀▀·▀▀▀▀  ▀█▄▀▪ ▀▀▀ " -ForegroundColor Green
    Write-Host ""
    Write-Host "  Coqui Installer (Windows via WSL2)"
    Write-Host ""
}

function Main {
    if ($script:HELP_MODE) {
        Show-Usage
        return
    }

    Show-Banner
    Ensure-WSLReady
    Invoke-InstallerInWSL
}

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
