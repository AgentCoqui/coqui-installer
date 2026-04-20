#Requires -Modules Pester
#
# Pester tests for install.ps1
# Run: Invoke-Pester ./tests/test_install.ps1 -Output Detailed

BeforeAll {
    $ScriptDir = Split-Path -Parent $PSScriptRoot
    $InstallScript = Join-Path $ScriptDir "install.ps1"

    function New-FakeWslScript {
        $path = Join-Path $env:TEMP "fake-wsl-install-$(Get-Random).ps1"
        @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$joined = $Args -join ' '
$logPath = $env:COQUI_TEST_WSL_LOG
if ($logPath) {
    Add-Content -Path $logPath -Value ("ARGS:" + $joined)
}

$stdin = [Console]::In.ReadToEnd()
if ($logPath -and -not [string]::IsNullOrWhiteSpace($stdin)) {
    Add-Content -Path $logPath -Value ("STDIN:" + $stdin.TrimEnd())
}

function Emit-Lines([string]$text) {
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        $text -split "`n" | ForEach-Object { Write-Output $_ }
    }
}

function Env-Exit([string]$name, [int]$default = 0) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $default
    }
    return [int]$value
}

if ($joined -eq '-l -v') {
    Emit-Lines $env:COQUI_TEST_WSL_LIST_OUTPUT
    exit (Env-Exit 'COQUI_TEST_WSL_LIST_EXIT')
}

if ($joined -eq '-d Ubuntu -- bash -lc printf coqui-ready') {
    if ([string]::IsNullOrWhiteSpace($env:COQUI_TEST_WSL_READY_OUTPUT)) {
        Write-Output 'coqui-ready'
    } else {
        Emit-Lines $env:COQUI_TEST_WSL_READY_OUTPUT
    }
    exit (Env-Exit 'COQUI_TEST_WSL_READY_EXIT')
}

if ($joined -eq '--install -d Ubuntu') {
    Emit-Lines $env:COQUI_TEST_WSL_INSTALL_OUTPUT
    exit (Env-Exit 'COQUI_TEST_WSL_INSTALL_EXIT')
}

if ($joined -eq '--set-version Ubuntu 2') {
    Emit-Lines $env:COQUI_TEST_WSL_SET_VERSION_OUTPUT
    exit (Env-Exit 'COQUI_TEST_WSL_SET_VERSION_EXIT')
}

if ($joined -like '-d Ubuntu -- bash -s --*') {
    Emit-Lines $env:COQUI_TEST_WSL_RUN_OUTPUT
    exit (Env-Exit 'COQUI_TEST_WSL_RUN_EXIT')
}

Write-Error "Unhandled fake wsl args: $joined"
exit 1
'@ | Set-Content -Path $path
        return $path
    }

    function Clear-TestEnv {
        foreach ($name in @(
            'COQUI_WSL_EXE',
            'COQUI_INSTALL_SH_CONTENT',
            'COQUI_WSL_BOOTSTRAP_ASSUME_YES',
            'COQUI_WSL_BOOTSTRAP_ASSUME_NO',
            'COQUI_TEST_WSL_LOG',
            'COQUI_TEST_WSL_LIST_OUTPUT',
            'COQUI_TEST_WSL_LIST_EXIT',
            'COQUI_TEST_WSL_READY_OUTPUT',
            'COQUI_TEST_WSL_READY_EXIT',
            'COQUI_TEST_WSL_INSTALL_OUTPUT',
            'COQUI_TEST_WSL_INSTALL_EXIT',
            'COQUI_TEST_WSL_SET_VERSION_OUTPUT',
            'COQUI_TEST_WSL_SET_VERSION_EXIT',
            'COQUI_TEST_WSL_RUN_OUTPUT',
            'COQUI_TEST_WSL_RUN_EXIT'
        )) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

AfterEach {
    Clear-TestEnv
}

Describe "install.ps1 argument parsing" {

    It "exits successfully with -Help flag" {
        & pwsh -NonInteractive -NoProfile -File $InstallScript -Help 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "-Help output describes the WSL2 installer flow" {
        $result = & pwsh -NonInteractive -NoProfile -File $InstallScript -Help 2>&1
        $joined = $result -join "`n"
        $joined | Should -Match "WSL2"
        $joined | Should -Match "install\.sh inside WSL"
        $joined | Should -Match "Distro"
    }
}

Describe "install.ps1 WSL bootstrap flow" {

    It "runs install.sh inside WSL2 when the distro is ready" {
        $fakeWsl = New-FakeWslScript
        $logPath = Join-Path $env:TEMP "coqui-wsl-install-log-$(Get-Random).txt"

        $env:COQUI_WSL_EXE = $fakeWsl
        $env:COQUI_INSTALL_SH_CONTENT = "echo bootstrap-install"
        $env:COQUI_TEST_WSL_LOG = $logPath
        $env:COQUI_TEST_WSL_LIST_OUTPUT = "  NAME STATE VERSION`n* Ubuntu Running 2"

        & pwsh -NonInteractive -NoProfile -File $InstallScript -Dev -Quiet 2>&1 | Out-Null

        $log = Get-Content -Path $logPath -Raw
        $log | Should -Match [regex]::Escape("ARGS:-d Ubuntu -- bash -s -- --dev --quiet")
        $log | Should -Match "STDIN:echo bootstrap-install"

        Remove-Item -Path $fakeWsl -Force
        Remove-Item -Path $logPath -Force
    }

    It "offers WSL installation and prints rerun guidance when setup is incomplete" {
        $fakeWsl = New-FakeWslScript
        $logPath = Join-Path $env:TEMP "coqui-wsl-install-log-$(Get-Random).txt"

        $env:COQUI_WSL_EXE = $fakeWsl
        $env:COQUI_INSTALL_SH_CONTENT = "echo bootstrap-install"
        $env:COQUI_WSL_BOOTSTRAP_ASSUME_YES = '1'
        $env:COQUI_TEST_WSL_LOG = $logPath
        $env:COQUI_TEST_WSL_LIST_OUTPUT = "  NAME STATE VERSION"
        $env:COQUI_TEST_WSL_READY_EXIT = '1'
        $env:COQUI_TEST_WSL_INSTALL_EXIT = '0'

        $result = & pwsh -NonInteractive -NoProfile -File $InstallScript 2>&1
        $joined = $result -join "`n"

        $joined | Should -Match "Finish WSL setup"
        $joined | Should -Match "wsl -d Ubuntu"

        $log = Get-Content -Path $logPath -Raw
        $log | Should -Match [regex]::Escape("ARGS:--install -d Ubuntu")

        Remove-Item -Path $fakeWsl -Force
        Remove-Item -Path $logPath -Force
    }

    It "upgrades a WSL1 distro to WSL2 when approved" {
        $fakeWsl = New-FakeWslScript
        $logPath = Join-Path $env:TEMP "coqui-wsl-install-log-$(Get-Random).txt"

        $env:COQUI_WSL_EXE = $fakeWsl
        $env:COQUI_INSTALL_SH_CONTENT = "echo bootstrap-install"
        $env:COQUI_WSL_BOOTSTRAP_ASSUME_YES = '1'
        $env:COQUI_TEST_WSL_LOG = $logPath
        $env:COQUI_TEST_WSL_LIST_OUTPUT = "  NAME STATE VERSION`n* Ubuntu Running 1"

        & pwsh -NonInteractive -NoProfile -File $InstallScript -Quiet 2>&1 | Out-Null

        $log = Get-Content -Path $logPath -Raw
        $log | Should -Match [regex]::Escape("ARGS:--set-version Ubuntu 2")
        $log | Should -Match [regex]::Escape("ARGS:-d Ubuntu -- bash -s -- --quiet")

        Remove-Item -Path $fakeWsl -Force
        Remove-Item -Path $logPath -Force
    }
}
