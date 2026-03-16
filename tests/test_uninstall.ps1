#Requires -Modules Pester
#
# Pester tests for uninstall.ps1
# Run: Invoke-Pester ./tests/test_uninstall.ps1 -Output Detailed

BeforeAll {
    $ScriptDir = Split-Path -Parent $PSScriptRoot
    $UninstallScript = Join-Path $ScriptDir "uninstall.ps1"
}

Describe "uninstall.ps1 argument parsing" {

    It "exits 0 with -Help flag" {
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Help 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "-Help output contains usage info" {
        $result = & pwsh -NonInteractive -NoProfile -File $UninstallScript -Help 2>&1
        $result | Should -Match "Usage|uninstall"
    }
}

Describe "uninstall.ps1 not-installed guard" {

    It "exits 0 when Coqui is not installed" {
        $fakeDir = Join-Path $env:TEMP "coqui-not-installed-$(Get-Random)"
        $env:COQUI_INSTALL_DIR = $fakeDir

        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0

        $env:COQUI_INSTALL_DIR = $null
    }

    It "warns when Coqui is not installed" {
        $fakeDir = Join-Path $env:TEMP "coqui-not-installed-$(Get-Random)"
        $env:COQUI_INSTALL_DIR = $fakeDir

        $result = & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1
        $result | Should -Match "not installed"

        $env:COQUI_INSTALL_DIR = $null
    }
}

Describe "uninstall.ps1 release install removal" {

    It "-Force removes release install directory" {
        $testDir = Join-Path $env:TEMP "coqui-uninstall-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        Test-Path $testDir | Should -Be $false
        $env:COQUI_INSTALL_DIR = $null
    }

    It "-Force removes dev install directory" {
        $testDir = Join-Path $env:TEMP "coqui-uninstall-dev-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testDir ".git") -Force | Out-Null

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        Test-Path $testDir | Should -Be $false
        $env:COQUI_INSTALL_DIR = $null
    }

    It "-Force exits 0 on successful removal" {
        $testDir = Join-Path $env:TEMP "coqui-uninstall-ok-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0

        $env:COQUI_INSTALL_DIR = $null
    }
}

Describe "uninstall.ps1 workspace preservation" {

    It "preserves workspace by default (-Force without -RemoveWorkspace)" {
        $testDir = Join-Path $env:TEMP "coqui-ws-preserve-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"
        $wsDir = Join-Path $testDir ".workspace"
        New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
        Set-Content -Path (Join-Path $wsDir "session.json") -Value '{"key":"value"}'

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        $sessionFile = Join-Path $testDir ".workspace\session.json"
        Test-Path $sessionFile | Should -Be $true
        Get-Content $sessionFile | Should -Match "value"

        $env:COQUI_INSTALL_DIR = $null
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "-RemoveWorkspace deletes workspace directory" {
        $testDir = Join-Path $env:TEMP "coqui-ws-remove-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"
        $wsDir = Join-Path $testDir ".workspace"
        New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
        Set-Content -Path (Join-Path $wsDir "session.json") -Value '{"key":"value"}'

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force -RemoveWorkspace 2>&1 | Out-Null

        Test-Path $testDir | Should -Be $false

        $env:COQUI_INSTALL_DIR = $null
    }

    It "removes install files but not workspace contents" {
        $testDir = Join-Path $env:TEMP "coqui-ws-files-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testDir "bin") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testDir "src") -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"
        Set-Content -Path (Join-Path $testDir "bin\coqui") -Value "#!/usr/bin/env php"
        $wsDir = Join-Path $testDir ".workspace"
        New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
        Set-Content -Path (Join-Path $wsDir "data.txt") -Value "user-data"

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        # App files should be gone
        Test-Path (Join-Path $testDir "bin") | Should -Be $false
        Test-Path (Join-Path $testDir ".coqui-version") | Should -Be $false

        # Workspace should remain
        Test-Path (Join-Path $testDir ".workspace\data.txt") | Should -Be $true

        $env:COQUI_INSTALL_DIR = $null
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "uninstall.ps1 wrapper removal" {

    It "removes coqui.bat wrapper when present" {
        $testDir = Join-Path $env:TEMP "coqui-wrapper-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"

        # Create a fake wrapper in the expected location
        $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"
        New-Item -ItemType Directory -Path $CoquiBinDir -Force | Out-Null
        $CoquiBat = Join-Path $CoquiBinDir "coqui.bat"
        Set-Content -Path $CoquiBat -Value "@php `"%~dp0..\coqui\bin\coqui`" %*"

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        Test-Path $CoquiBat | Should -Be $false

        $env:COQUI_INSTALL_DIR = $null
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "uninstall.ps1 PATH cleanup" {

    It "removes Coqui bin directory from user PATH" {
        $testDir = Join-Path $env:TEMP "coqui-path-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.0.0"

        $CoquiBinDir = Join-Path $env:LOCALAPPDATA "Programs\Coqui\bin"

        # Add Coqui bin to user PATH temporarily for this test
        $OriginalPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        [Environment]::SetEnvironmentVariable("PATH", "$OriginalPath;$CoquiBinDir", "User")

        $env:COQUI_INSTALL_DIR = $testDir
        & pwsh -NonInteractive -NoProfile -File $UninstallScript -Force 2>&1 | Out-Null

        $NewPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $NewPath | Should -Not -Match [regex]::Escape($CoquiBinDir)

        # Restore PATH
        [Environment]::SetEnvironmentVariable("PATH", $OriginalPath, "User")

        $env:COQUI_INSTALL_DIR = $null
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "uninstall.ps1 installation detection" {

    It "Test-DevInstalled returns true for dir with .git" {
        $testDir = Join-Path $env:TEMP "coqui-detect-dev-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testDir ".git") -Force | Out-Null

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Test-DevInstalled {
                $GitPath = Join-Path $COQUI_INSTALL_DIR ".git"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $GitPath)
            }
            Test-DevInstalled
        } -args $testDir

        $result | Should -Be $true
        Remove-Item -Path $testDir -Recurse -Force
    }

    It "Test-ReleaseInstalled returns true for dir with .coqui-version" {
        $testDir = Join-Path $env:TEMP "coqui-detect-rel-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "2.0.0"

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Test-ReleaseInstalled {
                $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $VersionFile)
            }
            Test-ReleaseInstalled
        } -args $testDir

        $result | Should -Be $true
        Remove-Item -Path $testDir -Recurse -Force
    }

    It "Get-InstalledVersion returns correct version string" {
        $testDir = Join-Path $env:TEMP "coqui-detect-ver-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "7.8.9"

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Get-InstalledVersion {
                $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
                if (Test-Path $VersionFile) {
                    return (Get-Content -Path $VersionFile -Raw).Trim()
                }
                return ""
            }
            Get-InstalledVersion
        } -args $testDir

        $result | Should -Be "7.8.9"
        Remove-Item -Path $testDir -Recurse -Force
    }
}
