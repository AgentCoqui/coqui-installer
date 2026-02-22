# Coqui Installer

One liner for [Coqui](https://github.com/AgentCoqui/coqui) — a terminal AI agent with multi-model orchestration.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

Or download and inspect first:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh -o install.sh
less install.sh    # review the script
bash install.sh
```

## What It Does

- Checks for PHP 8.4+ and required extensions (offers to install on Debian/Ubuntu)
- Installs Composer if not present
- Clones Coqui to `~/.coqui` and installs dependencies
- Creates a default configuration with Ollama as the local provider
- Symlinks the `coqui` command to your PATH

## Selective Install

Install individual components with flags:

```bash
# PHP only (no prompts)
./install.sh --install-php --non-interactive

# PHP + Composer only
./install.sh --install-php --install-composer

# Coqui only (user has PHP + Composer already)
./install.sh --install-coqui
```

When no `--install-*` flags are given, all components are installed (full setup, backward compatible with `curl | bash`).

| Flag | Description |
|------|-------------|
| `--install-php` | Install/check PHP 8.4+ and required extensions |
| `--install-composer` | Install/check Composer |
| `--install-coqui` | Install/update Coqui, create config and symlink |
| `--non-interactive` | Skip all confirmation prompts (assume yes) |
| `--help`, `-h` | Show usage |

## Update

Re-run the install command. The installer detects existing installations and offers to update:

```bash
curl -fsSL https://raw.githubusercontent.com/AgentCoqui/coqui-installer/main/install.sh | bash
```

## Configuration

Override defaults with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COQUI_INSTALL_DIR` | `~/.coqui` | Where Coqui is installed |
| `COQUI_REPO` | GitHub repo URL | Git repository to clone from |
| `COQUI_VERSION` | latest | Git branch or tag to install |

Example:

```bash
COQUI_INSTALL_DIR=/opt/coqui bash install.sh
```

## Requirements

- Linux or macOS (WSL2 supported)
- PHP 8.4 or later
- Extensions: `curl`, `mbstring`, `pdo_sqlite`, `xml`, `zip`
- Composer 2.x
- Git
- [Ollama](https://ollama.ai) (recommended for local inference)

## Uninstall

```bash
rm -rf ~/.coqui
sudo rm -f /usr/local/bin/coqui
```

## License

MIT
