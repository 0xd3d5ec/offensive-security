# offensive-security

A repo that contains all my custom offensive security scripts for pentesting and red teaming.

---

## Tools & Scripts

### `pwsh-reverseshell.py`

**Description:** Generates a base64-encoded PowerShell reverse shell one-liner. The payload connects back to a specified IP and port, spawning an interactive PowerShell session over TCP. The output is formatted as a `powershell -EncodedCommand` string ready to paste and execute on a target Windows machine.

**Usage:**
```
python3 pwsh-reverseshell.py <IP> <PORT>
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `IP`     | Attacker IP address the target will connect back to |
| `PORT`   | Listener port (1–65535) |

**Example:**
```
python3 pwsh-reverseshell.py 192.168.1.10 4444
```

---

### `kratos.sh`

**Description:** Kalix Script — an automated Linux environment setup tool for Debian/Kali-based systems. Installs core packages, configures Zsh with Oh-My-Zsh (Kali-like theme, autosuggestions, syntax highlighting), sets up tmux with sane defaults, and optionally changes the default shell. Supports multiple package profiles and a dry-run mode for safe previewing.

**Usage:**
```
./kratos.sh [options]
```

**Flags/Options:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Print all planned actions without making any changes |
| `--non-interactive` | Disable all prompts; uses safe defaults (implies `--no-chsh`) |
| `--yes` | Automatically answer yes to all prompts |
| `--profile NAME` | Select a package profile: `default`, `minimal`, `dev`, `pentest`, `desktop` |
| `--uninstall` | Remove all Kalix-managed config blocks from shell and tmux configs |
| `--skip-zsh` | Skip Zsh and Oh-My-Zsh setup |
| `--skip-tmux` | Skip tmux setup |
| `--only-packages` | Install packages only; skip shell/tmux configuration |
| `--only-shell` | Configure shell and tmux only; skip package installation |
| `--no-chsh` | Do not change the default shell |
| `--chsh` | Force changing the default shell to Zsh |
| `--tmux-autostart MODE` | Set tmux auto-start behavior: `yes`, `no`, or `ask` (default: `ask`) |
| `-h`, `--help` | Show the help message and exit |

**Package Profiles:**

| Profile | Packages |
|---------|----------|
| `default` | Base packages only (`git curl zsh tmux fzf nala xclip zoxide`) |
| `minimal` | Same as default |
| `dev` | Base + `build-essential jq ripgrep fd-find bat tree` |
| `pentest` | Base + `nmap sqlmap gobuster wfuzz` |
| `desktop` | Base + `xfce4 xfce4-goodies` |

**Examples:**
```bash
# Full setup with defaults
./kratos.sh

# Preview all changes without applying them
./kratos.sh --dry-run

# Silent install with pentest profile, no shell change
./kratos.sh --non-interactive --profile pentest

# Install packages only, skip shell/tmux config
./kratos.sh --only-packages --profile dev

# Remove all managed config blocks
./kratos.sh --uninstall
```
