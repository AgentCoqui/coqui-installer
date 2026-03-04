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
- Optionally installs Coqui as a background API service

## Update

Re-run the install command. The installer detects existing installations and updates automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

If a background service is running, it will be restarted automatically after the update.

## Selective Install

Install individual components with flags:

### Linux / macOS

```bash
# PHP only (no prompts)
./install.sh --install-php --non-interactive

# PHP + Composer only
./install.sh --install-php --install-composer

# Coqui only (user has PHP + Composer already)
./install.sh --install-coqui

# Service only (Coqui already installed)
./install.sh --install-service
```

### Windows

```powershell
.\install.ps1 --install-service
```

| Flag | Description |
| ---- | ----------- |
| `--install-php` | Install/check PHP 8.4+ and required extensions |
| `--install-composer` | Install/check Composer |
| `--install-coqui` | Install/update Coqui, create config and symlink |
| `--install-service` | Install Coqui API as a background service |
| `--non-interactive` | Skip all confirmation prompts (assume yes) |
| `--help`, `-h` | Show usage |

## Configuration

Override defaults with environment variables:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `COQUI_INSTALL_DIR` | `~/.coqui` | Where Coqui is installed |
| `COQUI_REPO` | GitHub repo URL | Git repository to clone from |
| `COQUI_VERSION` | latest | Git branch or tag to install |
| `COQUI_API_PORT` | `3300` | API port for service mode |

Example:

```bash
COQUI_INSTALL_DIR=/opt/coqui bash install.sh
```

## Background Service

The installer can set up Coqui as a background API service that starts on boot, restarts on failure, and is accessible over the network with API key authentication.

### How It Works

On fresh install, the installer asks if you'd like to set up the service. You can also install it separately:

```bash
# Linux / macOS
./install.sh --install-service

# Windows
.\install.ps1 --install-service
```

During setup, the installer:

1. Generates a random API key for authentication
2. Saves the key to `~/.coqui/.workspace/.env`
3. Creates and starts the appropriate service (systemd, launchd, or Task Scheduler)
4. Binds to `0.0.0.0` on port 3300 (network accessible, auth enforced)

The API key is displayed once during setup — save it. You can always retrieve it from `~/.coqui/.workspace/.env`.

### Service Management

#### Linux (systemd)

```bash
systemctl --user status coqui       # Check status
systemctl --user stop coqui         # Stop
systemctl --user start coqui        # Start
systemctl --user restart coqui      # Restart
systemctl --user disable coqui      # Disable auto-start
journalctl --user -u coqui -f       # View logs
```

#### macOS (launchd)

```bash
launchctl list bot.coqui.agent                                        # Check status
launchctl unload ~/Library/LaunchAgents/bot.coqui.agent.plist         # Stop
launchctl load ~/Library/LaunchAgents/bot.coqui.agent.plist           # Start
tail -f /tmp/coqui-stderr.log                                        # View logs
```

#### Windows (Task Scheduler)

```powershell
schtasks /Query /TN "CoquiApiService"      # Check status
schtasks /Run /TN "CoquiApiService"        # Start
schtasks /End /TN "CoquiApiService"        # Stop
schtasks /Delete /TN "CoquiApiService" /F  # Remove
```

### Security

- API key authentication is always enforced when the service binds to `0.0.0.0`
- The `--no-auth` flag is never used in service mode
- Linux services run with systemd security hardening (`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`)
- All services run at the user level — no root/admin privileges required for installation

## Requirements

- Linux, macOS, or Windows 10/11
- PHP 8.4 or later
- Extensions: `curl`, `mbstring`, `pdo_sqlite`, `xml`, `zip`
- Composer 2.x
- Git
- [Ollama](https://ollama.ai) (recommended for local inference)

## Uninstall

### Linux

```bash
# Stop and remove the service (if installed)
systemctl --user stop coqui
systemctl --user disable coqui
rm -f ~/.config/systemd/user/coqui.service
systemctl --user daemon-reload

# Remove Coqui
rm -rf ~/.coqui
sudo rm -f /usr/local/bin/coqui
```

### macOS

```bash
# Stop and remove the service (if installed)
launchctl unload ~/Library/LaunchAgents/bot.coqui.agent.plist
rm -f ~/Library/LaunchAgents/bot.coqui.agent.plist

# Remove Coqui
rm -rf ~/.coqui
sudo rm -f /usr/local/bin/coqui
```

### Windows

```powershell
# Stop and remove the service (if installed)
schtasks /End /TN "CoquiApiService" 2>$null
schtasks /Delete /TN "CoquiApiService" /F 2>$null

# Remove Coqui
Remove-Item -Recurse -Force $HOME\.coqui
Remove-Item -Force "$env:LOCALAPPDATA\Programs\Coqui\bin\coqui.bat"
```

## License

MIT
