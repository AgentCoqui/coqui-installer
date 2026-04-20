# Windows Handoff For Next Test And Coding Round

This file is the handoff for the next developer working on Windows installer coverage.

## Current Product Direction

- `install.ps1` is the supported Windows installer entrypoint.
- `uninstall.ps1` is the supported Windows uninstall entrypoint.
- Both public PowerShell scripts are WSL2 bootstrap scripts that delegate to `install.sh` and `uninstall.sh` inside WSL.
- `install-native.ps1` and `uninstall-native.ps1` still exist, but they are deprecated and unsupported compatibility paths.
- Native Windows should only get limited regression coverage. Do not expand it into a first-class platform.

## What Was Already Validated Off Windows

- Bash installer tests passed on macOS with `bats`.
- The Windows CI workflow is set up to lint all four PowerShell scripts and run four Pester suites.
- The public WSL2 bootstrap scripts and bootstrap Pester suites were recently rewritten manually, so inspect current file contents before assuming older discussion is still accurate.

## First Priority: Verify The Real Windows State

Do this on an actual Windows machine before making broader changes.

### 1. Prepare the environment

Run from the `coqui-installer` checkout.

```powershell
Set-Location C:\path\to\coqui-installer
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

### 2. Run the exact CI-relevant checks locally

```powershell
Invoke-ScriptAnalyzer -Path .\install.ps1 -Settings .\.github\PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
Invoke-ScriptAnalyzer -Path .\install-native.ps1 -Settings .\.github\PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
Invoke-ScriptAnalyzer -Path .\uninstall.ps1 -Settings .\.github\PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
Invoke-ScriptAnalyzer -Path .\uninstall-native.ps1 -Settings .\.github\PSScriptAnalyzerSettings.psd1 -Severity Warning,Error

Invoke-Pester .\tests\test_install.ps1 -Output Detailed
Invoke-Pester .\tests\test_install_native.ps1 -Output Detailed
Invoke-Pester .\tests\test_uninstall.ps1 -Output Detailed
Invoke-Pester .\tests\test_uninstall_native.ps1 -Output Detailed
```

Record every failure exactly before editing code.

## Second Priority: Manual WSL2 Bootstrap Smoke

Use a Windows machine that can exercise these cases.

### 1. Help and messaging

```powershell
pwsh -NoProfile -NonInteractive -File .\install.ps1 -Help
pwsh -NoProfile -NonInteractive -File .\uninstall.ps1 -Help
pwsh -NoProfile -NonInteractive -File .\install-native.ps1 -Help
pwsh -NoProfile -NonInteractive -File .\uninstall-native.ps1 -Help
```

Verify:

- Public scripts describe WSL2 as the supported Windows path.
- Native scripts describe themselves as unsupported.
- Native install help mentions the acknowledgement requirement.

### 2. Real `install.ps1` behavior

Test these scenarios if possible:

- WSL missing entirely.
- Ubuntu installed as WSL1.
- Ubuntu installed as WSL2 but not yet first-launched.
- Ubuntu installed as WSL2 and ready.

For each scenario, confirm:

- The prompt text is correct.
- The next command it asks the user to run is correct.
- `-Dev` and `-Quiet` are forwarded into WSL.
- The script fails with actionable messaging instead of a PowerShell stack trace.

### 3. Real `uninstall.ps1` behavior

Verify:

- It refuses to run when the supported WSL2 setup is missing.
- It forwards `-RemoveWorkspace`, `-Force`, and `-Quiet` into `uninstall.sh`.
- It gives first-launch guidance when the distro exists but is not ready.

## Third Priority: Native Compatibility Cleanup

There is at least one known code-versus-test mismatch right now.

### Known mismatch to resolve

- `tests/test_install_native.ps1` currently expects `install-native.ps1` to declare `dom`, `mbstring`, `pdo_sqlite`, and `xml` as required extensions, and to drop `openssl`.
- `install-native.ps1` currently still declares `curl`, `mbstring`, `openssl`, `pdo_sqlite`, `readline`, `xml`, and `zip` as required extensions.

Do not patch this blindly. Decide which one is correct, then align all three surfaces:

- `install-native.ps1`
- `tests/test_install_native.ps1`
- any native-only docs that describe extension expectations

Prefer the smallest change that keeps native Windows clearly unsupported.

## Coding Rules For The Next Round

- Keep WSL2 bootstrap as the public Windows story.
- Do not reintroduce native Windows into the main installer README as a supported path.
- Keep native Windows docs isolated to deprecated or internal documentation.
- Fix only Windows-installer-specific drift. Do not broaden the task into unrelated Coqui runtime work.
- If a failure only affects native Windows and would require major platform-specific complexity, stop and document it instead of building a new subsystem.

## Suggested Edit Order

1. Run the four PowerShell analyzer checks.
2. Run the four Pester suites.
3. Reproduce one real `install.ps1` bootstrap flow on Windows.
4. Reproduce one real `uninstall.ps1` bootstrap flow on Windows.
5. Fix the smallest set of failing script or test issues.
6. Re-run the exact same checks.
7. Update docs only if behavior changed.

## Deliverables From The Next Developer

When handing back results, include:

- which Windows environment was used
- which of the four Pester suites passed or failed
- exact failures from any failing suite
- whether real WSL bootstrap install and uninstall were exercised
- what code or test files were changed
- any native-Windows issues intentionally left unresolved

## Stop Conditions

Stop and document instead of over-engineering if any of these happen:

- `winget` behavior is inconsistent across shells or sessions
- WSL installation requires OS-level restarts that break deterministic automation
- native PATH or wrapper behavior becomes shell-specific
- fixing native Windows would require substantial platform-specific branching

If you hit a stop condition, preserve WSL2 bootstrap quality and leave native Windows as a documented compatibility path only.
