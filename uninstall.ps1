<#
.SYNOPSIS
    Coqui WSL2 Bootstrap Uninstaller for Windows
    https://github.com/AgentCoqui/coqui

.DESCRIPTION
    Removes a Coqui installation that was installed in the supported WSL2-based
    Windows workflow by running uninstall.sh inside WSL.

.PARAMETER RemoveWorkspace
    Delete the WSL workspace directory during uninstallation.

.PARAMETER Force
    Skip all confirmation prompts inside the WSL uninstaller.

.PARAMETER Distro
    WSL distro to use. Defaults to Ubuntu.

.EXAMPLE
    irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.ps1 | iex
#>

param(
    [switch]$RemoveWorkspace,
    [switch]$Force,
    [switch]$Quiet,
    [switch]$Help,
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$script:HadError = $false
$script:TARGET_DISTRO = $Distro
$script:REMOVE_WORKSPACE = $RemoveWorkspace.IsPresent
$script:FORCE_MODE = $Force.IsPresent
$script:QUIET_MODE = $Quiet.IsPresent
$script:HELP_MODE = $Help.IsPresent
$script:UNINSTALL_SCRIPT_URL = if ($env:COQUI_UNINSTALL_SH_URL) { $env:COQUI_UNINSTALL_SH_URL } else { "https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.sh" }

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

function Write-Err {
    param([string]$Message)
    Write-Host -Object "  $([char]0x2717) $Message" -ForegroundColor Red
}

function Write-Fatal {
    param([string]$Message)
    Write-Err $Message
    $script:HadError = $true
    throw "CoquiWslBootstrapUninstallError: $Message"
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

function Ensure-WSLReady {
    $wslExe = Get-WSLExecutable
    if ($null -eq $wslExe) {
        Write-Fatal "WSL is not available on this machine. Use install.ps1 to set up the supported Windows path first."
    }

    $listResult = Invoke-WSL -Arguments @('-l', '-v')
    $version = Get-DistroVersion -ListResult $listResult

    if ($version -ne 2) {
        Write-Fatal "WSL2 distro '$($script:TARGET_DISTRO)' is not ready. Use install.ps1 to set up the supported Windows path first."
    }

    if (-not (Test-BashReady)) {
        Write-Fatal "WSL2 distro '$($script:TARGET_DISTRO)' exists but still needs first-launch setup. Run 'wsl -d $($script:TARGET_DISTRO)' once, then retry."
    }
}

function Get-UninstallScriptContent {
    if (-not [string]::IsNullOrWhiteSpace($env:COQUI_UNINSTALL_SH_CONTENT)) {
        return $env:COQUI_UNINSTALL_SH_CONTENT
    }

    Write-Status "Downloading Coqui uninstaller..."
    try {
        return (Invoke-WebRequest -Uri $script:UNINSTALL_SCRIPT_URL -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        Write-Fatal "Failed to download uninstall.sh from $($script:UNINSTALL_SCRIPT_URL)."
    }
}

function Invoke-UninstallerInWSL {
    $scriptContent = Get-UninstallScriptContent
    $scriptArgs = @()

    if ($script:REMOVE_WORKSPACE) {
        $scriptArgs += '--remove-workspace'
    }

    if ($script:FORCE_MODE) {
        $scriptArgs += '--force'
    }

    if ($script:QUIET_MODE) {
        $scriptArgs += '--quiet'
    }

    Write-Status "Running Coqui uninstaller inside WSL2 ($($script:TARGET_DISTRO))..."
    $arguments = @('-d', $script:TARGET_DISTRO, '--', 'bash', '-s', '--') + $scriptArgs
    $result = Invoke-WSL -Arguments $arguments -InputText $scriptContent

    if ($result.ExitCode -ne 0) {
        Write-CommandOutput -Result $result
        Write-Fatal "The Coqui uninstaller failed inside WSL2."
    }

    Write-Success "Coqui uninstalled inside WSL2"
}

function Show-Usage {
    Write-Host "Usage: .\uninstall.ps1 [flags]"
    Write-Host ""
    Write-Host "Supported Windows uninstall path for a WSL2-based Coqui install."
    Write-Host ""
    Write-Host "One-liner:"
    Write-Host "  irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.ps1 | iex"
    Write-Host ""
    Write-Host "Flags:"
    Write-Host "  -RemoveWorkspace     Delete the WSL workspace directory"
    Write-Host "  -Force               Skip confirmation prompts inside WSL"
    Write-Host "  -Quiet               Minimal output"
    Write-Host "  -Help                Show this help"
    Write-Host "  -Distro <name>       WSL distro to use (default: Ubuntu)"
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
    Write-Host "  Coqui Uninstaller (Windows via WSL2)"
    Write-Host ""
}

function Main {
    if ($script:HELP_MODE) {
        Show-Usage
        return
    }

    Show-Banner
    Ensure-WSLReady
    Invoke-UninstallerInWSL
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
