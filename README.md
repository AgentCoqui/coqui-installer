# Coqui Installer

One liner for [Coqui](https://github.com/AgentCoqui/coqui) — a terminal AI agent with multi-model orchestration.

## Install

The installer downloads the latest GitHub release by default. No Git or Composer required.

> Platform note: Linux, macOS, and WSL2 are the supported install paths. On Windows, use the PowerShell WSL2 bootstrap.
>
> Deprecated native Windows scripts remain in the repository for at-risk users only. See [docs/NATIVE-WINDOWS-DEPRECATED.md](docs/NATIVE-WINDOWS-DEPRECATED.md).

### Bash Dev Mode

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

### Windows Bootstrap Dev Mode

The Windows bootstrap checks for WSL2, offers to install Ubuntu when needed, and then runs the standard Coqui installer inside WSL.

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex
```

### Inspect before running (Linux / macOS / WSL2)

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh -o install.sh
less install.sh
bash install.sh
```

### Inspect before running (Windows bootstrap)

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 -OutFile install.ps1
Get-Content install.ps1 | more
.\install.ps1
```

## What It Does

- Detects your OS and package manager (`apt`, `brew`, `dnf`, `yum`, `pacman`, `apk`, `nix`, `winget`)
- Installs PHP 8.4+ plus the default Coqui extension set automatically when package-manager support is available
- Downloads the latest Coqui release from GitHub (pre-built with dependencies)
- Verifies the download with SHA-256 checksums
- Adds `coqui` and `coqui-launcher` commands to your PATH

On Windows, the PowerShell bootstrap also checks for WSL2 readiness and then delegates to the bash installer inside your WSL distro.

## After Install

`coqui` is the main entry point. It starts the full launcher-managed app: REPL in the foreground plus the API in the background.

```bash
coqui
coqui --api-only
coqui status
```

Use `coqui-launcher` when you want the explicit launcher name. It exposes the same launcher-managed modes.

Coqui auto-discovers Composer toolkits and toolkit-provided REPL commands on boot. Install packages with `/space install <package>` or with Composer in your workspace, then restart Coqui to activate newly discovered tools and slash commands.

## Update

Re-run the install command. The installer detects existing installations and updates automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.ps1 | iex
```

## Development Mode

Use `--dev` (bash) or `-Dev` (Windows bootstrap) to clone the git repository instead of downloading a release. This requires Git and Composer inside the target environment.

### Linux / macOS / WSL2

```bash
./install.sh --dev
```

### Windows (WSL2 Bootstrap)

```powershell
.\install.ps1 -Dev
```

Dev mode uses `git clone` and `composer install`, which is useful for contributors or anyone who wants to modify Coqui's source.

## Selective Install (Linux / macOS / WSL2)

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

- Linux or macOS
- Windows 10/11 via WSL2
- PHP 8.4 or later
- Core extensions: `dom`, `mbstring`, `pdo_sqlite`, `xml`
- Recommended extensions: `curl`, `readline`, `zip`
- Optional extensions: `gd` for bundled image previews
- [Ollama](https://ollama.com) (recommended for local embeddings)

Additional requirements for `--dev` mode only:

- Composer 2.x
- Git

## Uninstall

The uninstaller removes Coqui, its symlinks/wrappers, and PATH entries. By default it preserves workspace data and does **not** remove PHP or Composer.

### Linux / macOS / WSL2 Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.sh | bash
```

### Windows (WSL2 Bootstrap) Uninstall

```powershell
irm https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/uninstall.ps1 | iex
```

### Uninstall flags

| Flag (bash)          | Flag (PowerShell)  | Description                                            |
| -------------------- | ------------------ | ------------------------------------------------------ |
| `--remove-workspace` | `-RemoveWorkspace` | Delete the workspace directory (`~/.coqui/.workspace`) |
| `--force`            | `-Force`           | Skip all confirmation prompts                          |
| `--all`              | Not supported      | Also remove PHP and Composer installed by Coqui        |
| `--quiet`, `-q`      | `-Quiet`           | Minimal output                                         |
| `--help`, `-h`       | `-Help`            | Show usage                                             |

### Uninstall examples

```bash
# Interactive (workspace preserved by default)
./uninstall.sh

# Remove workspace data too
./uninstall.sh --remove-workspace

# Remove everything without prompts (workspace preserved)
./uninstall.sh --force

# Remove everything including PHP and Composer, no prompts
./uninstall.sh --force --all
```

```powershell
# Interactive (workspace preserved by default)
.\uninstall.ps1

# Remove workspace data too
.\uninstall.ps1 -RemoveWorkspace

# Skip confirmation prompts inside WSL
.\uninstall.ps1 -Force
```

## License

MIT
