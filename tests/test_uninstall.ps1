#Requires -Modules Pester
#
# Pester tests for uninstall.ps1
# Run: Invoke-Pester ./tests/test_uninstall.ps1 -Output Detailed

BeforeAll {
    $ScriptDir = Split-Path -Parent $PSScriptRoot
    $UninstallScript = Join-Path $ScriptDir "uninstall.ps1"

    function New-FakeWslScript {
        $path = Join-Path $env:TEMP "fake-wsl-uninstall-$(Get-Random).ps1"
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
            'COQUI_UNINSTALL_SH_CONTENT',
            'COQUI_TEST_WSL_LOG',
            'COQUI_TEST_WSL_LIST_OUTPUT',
            'COQUI_TEST_WSL_LIST_EXIT',
            'COQUI_TEST_WSL_READY_OUTPUT',
            'COQUI_TEST_WSL_READY_EXIT',
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

Describe "uninstall.ps1 argument parsing" {

    It "exits 0 with -Help flag" {
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Help 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "-Help output describes the WSL2 uninstall flow" {
        $result = & pwsh -NonInteractive -NoProfile -File $UninstallScript -Help 2>&1
        $joined = $result -join "`n"
        $joined | Should -Match "WSL2"
        $joined | Should -Match "WSL2-based Coqui install"
        $joined | Should -Match "RemoveWorkspace"
    }
}

Describe "uninstall.ps1 WSL bootstrap flow" {

    It "runs uninstall.sh inside WSL2 and forwards flags" {
        $fakeWsl = New-FakeWslScript
        $logPath = Join-Path $env:TEMP "coqui-wsl-uninstall-log-$(Get-Random).txt"

        $env:COQUI_WSL_EXE = $fakeWsl
        $env:COQUI_UNINSTALL_SH_CONTENT = "echo bootstrap-uninstall"
        $env:COQUI_TEST_WSL_LOG = $logPath
        $env:COQUI_TEST_WSL_LIST_OUTPUT = "  NAME STATE VERSION`n* Ubuntu Running 2"

        & pwsh -NonInteractive -NoProfile -File $UninstallScript -RemoveWorkspace -Force -Quiet 2>&1 | Out-Null

        $log = Get-Content -Path $logPath -Raw
        $log | Should -Match [regex]::Escape("ARGS:-d Ubuntu -- bash -s -- --remove-workspace --force --quiet")
        $log | Should -Match "STDIN:echo bootstrap-uninstall"

        Remove-Item -Path $fakeWsl -Force
        Remove-Item -Path $logPath -Force
    }

    It "requires the supported WSL2 setup before uninstalling" {
        $fakeWsl = New-FakeWslScript

        $env:COQUI_WSL_EXE = $fakeWsl
        $env:COQUI_TEST_WSL_LIST_OUTPUT = "  NAME STATE VERSION"

        $result = & pwsh -NonInteractive -NoProfile -File $UninstallScript 2>&1
        $joined = $result -join "`n"

        $joined | Should -Match "Use install\.ps1"
        $joined | Should -Match "WSL2 distro 'Ubuntu' is not ready"

        Remove-Item -Path $fakeWsl -Force
    }
}
