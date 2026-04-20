# Native Windows Install (Deprecated and Unsupported)

This document covers the legacy native Windows PowerShell scripts that remain in this repository for at-risk users.

Coqui's supported Windows install path is WSL2. Use the supported bootstrap instead:

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex
```

## Status

- Deprecated
- Unsupported
- Not recommended for normal use
- Kept in the repository for advanced users who understand the risks

## Risks

The native Windows path is not a supported install target. It may work for basic REPL experiments, but it is not the platform the project supports for full Coqui workflows.

Known issues include:

- PHP and extension provisioning can be inconsistent across Windows environments.
- Shell, process, and background-task behavior differ from Linux and WSL2.
- PATH and wrapper behavior can vary across shells and terminals.
- Future improvements will prioritize WSL2 and Docker instead of the native Windows path.

## Native Scripts

```powershell
# Native install
.\install-native.ps1

# Native uninstall
.\uninstall-native.ps1
```

## Explicit Acknowledgement Requirement

The native installer requires an explicit confirmation before it continues.

For unattended or at-risk automation, set:

```powershell
$env:COQUI_NATIVE_INSTALL_ACKNOWLEDGED = '1'
.\install-native.ps1
```

## Development Mode

```powershell
.\install-native.ps1 -Dev
```

## Native Uninstall

```powershell
.\uninstall-native.ps1
.\uninstall-native.ps1 -RemoveWorkspace
.\uninstall-native.ps1 -Force -All
```

## Support Policy

Bug reports and install help for Windows should use the WSL2 path first. If you choose the native scripts, you are using a deprecated compatibility path at your own risk.
