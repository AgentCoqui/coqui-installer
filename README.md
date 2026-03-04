# Coqui Installer

One liner for [Coqui](https://github.com/AgentCoqui/coqui) — a terminal AI agent with multi-model orchestration.

## Install

### Linux / macOS / WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex
```

### Inspect before running (Linux / macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh -o install.sh
less install.sh
bash install.sh
```

### Inspect before running (Windows)

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 -OutFile install.ps1
Get-Content install.ps1 | more
.\install.ps1
```

## What It Does

- Detects your OS and package manager (`apt`, `brew`, `dnf`, `yum`, `pacman`, `apk`, `nix`, `winget`)
- Installs PHP 8.4+, required extensions, Composer, and Git automatically if missing
- Clones Coqui to `~/.coqui` and installs dependencies
- Creates a default configuration with Ollama as the local provider
- Adds `coqui` command to your PATH

## Update

Re-run the install command. The installer detects existing installations and updates automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

## Selective Install (Linux / macOS)

Install individual components with flags:

```bash
# PHP only (no prompts)
./install.sh --install-php --non-interactive

# PHP + Composer only
./install.sh --install-php --install-composer

# Coqui only (user has PHP + Composer already)
./install.sh --install-coqui
```

| Flag | Description |
| ---- | ----------- |
| `--install-php` | Install/check PHP 8.4+ and required extensions |
| `--install-composer` | Install/check Composer |
| `--install-coqui` | Install/update Coqui, create config and symlink |
| `--non-interactive` | Skip all confirmation prompts (assume yes) |
| `--help`, `-h` | Show usage |

## Configuration

Override defaults with environment variables:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `COQUI_INSTALL_DIR` | `~/.coqui` | Where Coqui is installed |
| `COQUI_REPO` | GitHub repo URL | Git repository to clone from |
| `COQUI_VERSION` | latest | Git branch or tag to install |

Example:

```bash
COQUI_INSTALL_DIR=/opt/coqui bash install.sh
```

## Requirements

- Linux, macOS, or Windows 10/11
- PHP 8.4 or later
- Extensions: `curl`, `mbstring`, `pdo_sqlite`, `xml`, `zip`
- Composer 2.x
- Git
- [Ollama](https://ollama.ai) (recommended for local inference)

## Uninstall

### Linux / macOS

```bash
rm -rf ~/.coqui
sudo rm -f /usr/local/bin/coqui
```

### Windows

```powershell
Remove-Item -Recurse -Force $HOME\.coqui
Remove-Item -Force "$env:LOCALAPPDATA\Programs\Coqui\bin\coqui.bat"
```

## License

MIT
