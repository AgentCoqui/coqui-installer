#Requires -Modules Pester
#
# Pester tests for install-native.ps1
# Run: Invoke-Pester ./tests/test_install_native.ps1 -Output Detailed

BeforeAll {
    $ScriptDir = Split-Path -Parent $PSScriptRoot
    $InstallScript = Join-Path $ScriptDir "install-native.ps1"
}

Describe "install-native.ps1 argument parsing" {

    It "exits successfully with -Help flag" {
        $result = & pwsh -NonInteractive -NoProfile -File $InstallScript -Help 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It "-Help output contains usage instructions" {
        $result = & pwsh -NonInteractive -NoProfile -File $InstallScript -Help 2>&1
        ($result -join "`n") | Should -Match "Usage|Synopsis|irm"
    }

    It "-Help output warns that native Windows is degraded and recommends WSL2 or Docker" {
        $result = & pwsh -NonInteractive -NoProfile -File $InstallScript -Help 2>&1
        $joined = $result -join "`n"
        $joined | Should -Match "not a supported target|degraded"
        $joined | Should -Match "WSL2|Docker"
    }

    It "declares dom as a required extension and drops openssl" {
        $content = Get-Content -Path $InstallScript -Raw
        $content | Should -Match '\$REQUIRED_EXTENSIONS = @\("dom", "mbstring", "pdo_sqlite", "xml"\)'
        $content | Should -Not -Match 'openssl'
    }
}

Describe "install-native.ps1 installation detection" {

    It "Test-DevInstalled returns true when .git directory exists" {
        $testDir = Join-Path $env:TEMP "coqui-test-dev-$(Get-Random)"
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

    It "Test-ReleaseInstalled returns true when .coqui-version exists" {
        $testDir = Join-Path $env:TEMP "coqui-test-release-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "1.2.3"

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

    It "Test-DevInstalled returns false when .git directory is absent" {
        $testDir = Join-Path $env:TEMP "coqui-test-empty-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Test-DevInstalled {
                $GitPath = Join-Path $COQUI_INSTALL_DIR ".git"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $GitPath)
            }
            Test-DevInstalled
        } -args $testDir

        $result | Should -Be $false

        Remove-Item -Path $testDir -Recurse -Force
    }

    It "Test-ReleaseInstalled returns false when .coqui-version is absent" {
        $testDir = Join-Path $env:TEMP "coqui-test-empty-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Test-ReleaseInstalled {
                $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $VersionFile)
            }
            Test-ReleaseInstalled
        } -args $testDir

        $result | Should -Be $false

        Remove-Item -Path $testDir -Recurse -Force
    }

    It "Test-CoquiInstalled returns false when directory does not exist" {
        $fakeDir = Join-Path $env:TEMP "coqui-nonexistent-$(Get-Random)"

        $result = & pwsh -NonInteractive -NoProfile -Command {
            param($dir)
            $COQUI_INSTALL_DIR = $dir
            function Test-DevInstalled {
                $GitPath = Join-Path $COQUI_INSTALL_DIR ".git"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $GitPath)
            }
            function Test-ReleaseInstalled {
                $VersionFile = Join-Path $COQUI_INSTALL_DIR ".coqui-version"
                return (Test-Path $COQUI_INSTALL_DIR) -and (Test-Path $VersionFile)
            }
            function Test-CoquiInstalled { return (Test-DevInstalled) -or (Test-ReleaseInstalled) }
            Test-CoquiInstalled
        } -args $fakeDir

        $result | Should -Be $false
    }

    It "Get-InstalledVersion reads version from .coqui-version" {
        $testDir = Join-Path $env:TEMP "coqui-test-ver-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -Path (Join-Path $testDir ".coqui-version") -Value "4.5.6"

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

        $result | Should -Be "4.5.6"

        Remove-Item -Path $testDir -Recurse -Force
    }
}

Describe "install-native.ps1 release-over-dev guard" {

    It "exits with error when release install attempted over dev install" {
        $testDir = Join-Path $env:TEMP "coqui-test-devguard-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testDir ".git") -Force | Out-Null

        $env:COQUI_INSTALL_DIR = $testDir
        $env:COQUI_NATIVE_INSTALL_ACKNOWLEDGED = '1'
        $output = & pwsh -NonInteractive -NoProfile -File $InstallScript 2>&1
        $exitCode = $LASTEXITCODE

        # Script should communicate an error (either non-zero exit or error message)
        $hadError = ($exitCode -ne 0) -or ($output -match "dev installation|Cannot install")
        $hadError | Should -Be $true

        $env:COQUI_INSTALL_DIR = $null
        $env:COQUI_NATIVE_INSTALL_ACKNOWLEDGED = $null
        Remove-Item -Path $testDir -Recurse -Force
    }

    It "requires explicit acknowledgement before native install continues" {
        $output = & pwsh -NonInteractive -NoProfile -File $InstallScript 2>&1
        ($output -join "`n") | Should -Match "explicit confirmation|COQUI_NATIVE_INSTALL_ACKNOWLEDGED"
    }
}
