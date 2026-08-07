#!/usr/bin/env bats

# Guards the clean-cut removal of all PowerShell / Windows-native artifacts.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no PowerShell scripts remain anywhere in the repo" {
    run bash -c "find '$REPO_ROOT' -name '*.ps1' -not -path '*/.git/*' | head -20"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "no PSScriptAnalyzer settings remain" {
    [ ! -f "$REPO_ROOT/.github/PSScriptAnalyzerSettings.psd1" ]
}

@test "Windows-native deprecation docs are gone" {
    [ ! -f "$REPO_ROOT/docs/NATIVE-WINDOWS-DEPRECATED.md" ]
    [ ! -f "$REPO_ROOT/tests/WINDOWS-SMOKE-CHECKLIST.md" ]
}

@test "CI workflow has no PowerShell jobs" {
    run grep -iE 'powershell|pwsh|pester|psscriptanalyzer|test-windows' "$REPO_ROOT/.github/workflows/test-installer.yml"
    [ "$status" -ne 0 ]
}
