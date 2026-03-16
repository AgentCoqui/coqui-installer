# Coqui Installer

One liner for [Coqui](https://github.com/AgentCoqui/coqui) — a terminal AI agent with multi-model orchestration.

## Install

The installer downloads the latest GitHub release by default. No Git or Composer required.

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
- Installs PHP 8.4+ and required extensions automatically if missing
- Downloads the latest Coqui release from GitHub (pre-built with dependencies)
- Verifies the download with SHA-256 checksums
- Adds `coqui` command to your PATH

## Update

Re-run the install command. The installer detects existing installations and updates automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

## Development Mode

Use `--dev` (Linux/macOS) or `-Dev` (Windows) to clone the git repository instead of downloading a release. This requires Git and Composer.

### Linux / macOS

```bash
./install.sh --dev
```

### Windows

```powershell
.\install.ps1 -Dev
```

Dev mode uses `git clone` and `composer install`, which is useful for contributors or anyone who wants to modify Coqui's source.

## Selective Install (Linux / macOS)

Install individual components with flags:

```bash
# PHP only (no prompts)
./install.sh --install-php --non-interactive

# PHP + Composer only
./install.sh --install-php --install-composer

# Coqui only (user has PHP already)
./install.sh --install-coqui

# Dev mode Coqui only
./install.sh --install-coqui --dev
```

| Flag                 | Description                                     |
| -------------------- | ----------------------------------------------- |
| `--install-php`      | Install/check PHP 8.4+ and required extensions  |
| `--install-composer` | Install/check Composer                          |
| `--install-coqui`    | Install/update Coqui, create config and symlink |
| `--dev`              | Use git clone instead of release download       |
| `--non-interactive`  | Skip all confirmation prompts (assume yes)      |
| `--help`, `-h`       | Show usage                                      |

## Configuration

Override defaults with environment variables:

| Variable            | Default         | Description                                  |
| ------------------- | --------------- | -------------------------------------------- |
| `COQUI_INSTALL_DIR` | `~/.coqui`      | Where Coqui is installed                     |
| `COQUI_REPO`        | GitHub repo URL | Git repository to clone from (dev mode only) |
| `COQUI_VERSION`     | latest          | Release version or git branch/tag to install |

Example:

```bash
# Specific release version
COQUI_VERSION=0.0.1 bash install.sh

# Custom install directory
COQUI_INSTALL_DIR=/opt/coqui bash install.sh
```

## Requirements

- Linux, macOS, or Windows 10/11
- PHP 8.4 or later
- Extensions: `curl`, `mbstring`, `pdo_sqlite`, `xml`, `zip`
- [Ollama](https://ollama.com) (recommended for local embeddings)

Additional requirements for `--dev` mode only:
- Composer 2.x
- Git

## Uninstall

The uninstaller removes Coqui, its symlinks/wrappers, and PATH entries. By default it prompts before deleting workspace data and does **not** remove PHP or Composer.

### Linux / macOS / WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.ps1 | iex
```

### Uninstall flags

| Flag (bash)        | Flag (PowerShell) | Description                                               |
| ------------------ | ----------------- | --------------------------------------------------------- |
| `--keep-workspace` | `-KeepWorkspace`  | Preserve the workspace directory (`~/.coqui/.workspace`)  |
| `--force`          | `-Force`          | Skip all confirmation prompts (removes Coqui + workspace) |
| `--all`            | `-All`            | Also remove PHP and Composer installed by Coqui           |
| `--quiet`, `-q`    | `-Quiet`          | Minimal output                                            |
| `--help`, `-h`     | `-Help`           | Show usage                                                |

### Uninstall examples

```bash
# Interactive (prompts for workspace)
./uninstall.sh

# Keep workspace for future reinstall
./uninstall.sh --keep-workspace

# Remove everything without prompts
./uninstall.sh --force

# Remove everything including PHP and Composer, no prompts
./uninstall.sh --force --all
```

```powershell
# Interactive
.\uninstall.ps1

# Remove everything including PHP and Composer
.\uninstall.ps1 -Force -All
```

### What gets removed

| Component               | Default                | `--force` | `--all`              |
| ----------------------- | ---------------------- | --------- | -------------------- |
| Coqui install directory | Yes                    | Yes       | Yes                  |
| Symlink / wrapper       | Yes                    | Yes       | Yes                  |
| PATH entry (Windows)    | Yes                    | Yes       | Yes                  |
| Workspace data          | Prompt (default: keep) | Yes       | Yes                  |
| PHP                     | No                     | No        | Prompt (default: no) |
| Composer                | No                     | No        | Prompt (default: no) |

With `--force --all`, everything is removed without prompts.

## License

MIT
