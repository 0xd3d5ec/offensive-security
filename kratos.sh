#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="kalix"
VERSION="0.2.0"
AUTHOR="Bl4ckan0n"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

DRY_RUN=0
NON_INTERACTIVE=0
SKIP_TMUX=0
SKIP_ZSH=0
ONLY_PACKAGES=0
ONLY_SHELL=0
NO_CHSH=0
ASSUME_YES=0
UNINSTALL=0
PROFILE="default"
TMUX_AUTOSTART_MODE="ask"

LOG_DIR="${HOME}/.kalix/logs"
LOG_FILE="${LOG_DIR}/kalix-$(date +%Y%m%d-%H%M%S).log"
APT_UPDATED=0

declare -a BASE_PACKAGES=(git curl zsh tmux fzf nala xclip zoxide)
declare -a PROFILE_PACKAGES=()
declare -a INSTALLED_PACKAGES=()
declare -a CHANGED_FILES=()
declare -a SKIPPED_STEPS=()
declare -a ERRORS=()

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

init_logging() {
  mkdir -p "$LOG_DIR"
  : > "$LOG_FILE"
}

log_line() {
  local level="$1"
  local color="$2"
  shift 2
  local message="$*"
  printf "%b[%s]%b %s\n" "$color" "$level" "$RESET" "$message"
  printf "[%s] [%s] %s\n" "$(timestamp)" "$level" "$message" >> "$LOG_FILE"
}

info() {
  log_line "INFO" "$BLUE" "$*"
}

success() {
  log_line "OK" "$GREEN" "$*"
}

warn() {
  log_line "WARN" "$YELLOW" "$*"
}

fail() {
  log_line "ERROR" "$RED" "$*"
}

record_change() {
  CHANGED_FILES+=("$1")
}

record_skip() {
  SKIPPED_STEPS+=("$1")
}

record_error() {
  ERRORS+=("$1")
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

on_error() {
  local line="$1"
  fail "An error occurred on line ${line}."
  record_error "Command failed on line ${line}"
  fail "Check log for details: ${LOG_FILE}"
}

trap 'on_error $LINENO' ERR

print_banner() {
  printf "%b\n" "${RED}██╗  ██╗ █████╗ ██╗     ██╗██╗  ██╗      ███████╗ ██████╗██████╗ ██╗██████╗ ████████╗"
  printf "%b\n" "██║ ██╔╝██╔══██╗██║     ██║╚██╗██╔╝      ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝"
  printf "%b\n" "█████╔╝ ███████║██║     ██║ ╚███╔╝ █████╗███████╗██║     ██████╔╝██║██████╔╝   ██║   "
  printf "%b\n" "██╔═██╗ ██╔══██║██║     ██║ ██╔██╗ ╚════╝╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   "
  printf "%b\n" "██║  ██╗██║  ██║███████╗██║██╔╝ ██╗      ███████║╚██████╗██║  ██║██║██║        ██║   "
  printf "%b\n" "╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═╝      ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ${RESET}"
  printf "%s\n" ""
  printf "%s\n" "${SCRIPT_NAME} v${VERSION} by ${AUTHOR}"
  printf "%s\n" ""
}

usage() {
  cat <<'EOF'
Usage: ./kratos.sh [options]

General options:
  --dry-run               Print actions without changing files
  --non-interactive       Disable prompts (safe defaults)
  --yes                   Answer yes to prompts
  --profile NAME          Package profile: default|minimal|dev|pentest|desktop
  --uninstall             Remove Kalix-managed config blocks

Scope options:
  --skip-zsh              Skip Zsh and Oh-My-Zsh setup
  --skip-tmux             Skip tmux setup
  --only-packages         Install packages only
  --only-shell            Configure shell/tmux only

Shell options:
  --no-chsh               Do not change default shell
  --chsh                  Force changing default shell to zsh
  --tmux-autostart MODE   Mode: yes|no|ask

Other options:
  -h, --help              Show this help message
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        NO_CHSH=1
        ;;
      --yes)
        ASSUME_YES=1
        ;;
      --skip-zsh)
        SKIP_ZSH=1
        ;;
      --skip-tmux)
        SKIP_TMUX=1
        ;;
      --only-packages)
        ONLY_PACKAGES=1
        ;;
      --only-shell)
        ONLY_SHELL=1
        ;;
      --no-chsh)
        NO_CHSH=1
        ;;
      --chsh)
        NO_CHSH=0
        ;;
      --uninstall)
        UNINSTALL=1
        ;;
      --profile)
        if [ "$#" -lt 2 ]; then
          fail "--profile requires a value"
          exit 1
        fi
        PROFILE="${2:-}"
        shift
        ;;
      --tmux-autostart)
        if [ "$#" -lt 2 ]; then
          fail "--tmux-autostart requires a value"
          exit 1
        fi
        TMUX_AUTOSTART_MODE="${2:-}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [ "$ONLY_PACKAGES" -eq 1 ] && [ "$ONLY_SHELL" -eq 1 ]; then
    fail "Use either --only-packages or --only-shell, not both."
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    return 1
  fi
  read -r -p "$prompt [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_non_root() {
  if [ "$EUID" -eq 0 ]; then
    fail "Do not run this script as root. It will use sudo when needed."
    exit 1
  fi
}

preflight_checks() {
  if [ ! -f /etc/os-release ]; then
    fail "Cannot detect distribution: /etc/os-release missing."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|kali)
      success "Detected supported distro: ${ID}"
      ;;
    *)
      if [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        warn "Detected Debian-like distro (${ID}), proceeding."
      else
        fail "Unsupported distro: ${ID:-unknown}. Kalix supports Debian/Kali."
        exit 1
      fi
      ;;
  esac

  if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is required but not installed."
    exit 1
  fi

  if [ ! -w "$HOME" ]; then
    fail "Home directory is not writable: $HOME"
    exit 1
  fi

  if ! getent hosts deb.debian.org >/dev/null 2>&1; then
    warn "Could not verify network reachability to deb.debian.org"
  fi

  if [ "$NON_INTERACTIVE" -eq 1 ] && ! sudo -n true >/dev/null 2>&1; then
    fail "Non-interactive mode requires passwordless sudo."
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 0
  fi
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local backup_path="${file}.kalix.bak.${stamp}"
  info "Backing up ${file} -> ${backup_path}"
  run cp "$file" "$backup_path"
  record_change "$backup_path"
}

select_profile_packages() {
  case "$PROFILE" in
    default)
      PROFILE_PACKAGES=()
      ;;
    minimal)
      PROFILE_PACKAGES=()
      ;;
    dev)
      PROFILE_PACKAGES=(build-essential jq ripgrep fd-find bat tree)
      ;;
    pentest)
      PROFILE_PACKAGES=(nmap sqlmap gobuster wfuzz)
      ;;
    desktop)
      PROFILE_PACKAGES=(xfce4 xfce4-goodies)
      ;;
    *)
      fail "Unknown profile: ${PROFILE}"
      exit 1
      ;;
  esac
}

apt_update() {
  if [ "$APT_UPDATED" -eq 1 ]; then
    return 0
  fi
  info "Updating package lists"
  run sudo apt-get update
  APT_UPDATED=1
  success "Package lists updated"
}

install_packages() {
  local packages=("$@")
  local missing=()
  local pkg

  for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    success "All required packages are already installed"
    return 0
  fi

  apt_update
  info "Installing missing packages: ${missing[*]}"

  local attempt
  for attempt in 1 2 3; do
    if run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
      INSTALLED_PACKAGES+=("${missing[@]}")
      success "Package installation completed"
      return 0
    fi
    warn "Package install attempt ${attempt}/3 failed"
    sleep 2
  done

  fail "Failed to install packages after retries"
  exit 1
}

clone_if_missing() {
  local repo="$1"
  local target="$2"
  if [ -d "$target" ]; then
    record_skip "Already present: ${target}"
    return 0
  fi
  info "Cloning ${repo} -> ${target}"
  run git clone --depth 1 "$repo" "$target"
  record_change "$target"
}

remove_managed_block() {
  local file="$1"
  local name="$2"
  local start_marker="# >>> ${name} >>>"
  local end_marker="# <<< ${name} <<<"
  local tmp

  if [ ! -f "$file" ]; then
    return 0
  fi

  if ! grep -qF "$start_marker" "$file"; then
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: remove block ${name} from ${file}"
    return 0
  fi

  backup_file "$file"
  tmp="$(mktemp)"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
  record_change "$file"
}

upsert_managed_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local start_marker="# >>> ${name} >>>"
  local end_marker="# <<< ${name} <<<"
  local tmp

  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: update block ${name} in ${file}"
    return 0
  fi

  if [ ! -f "$file" ]; then
    run touch "$file"
  fi

  tmp="$(mktemp)"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$file" > "$tmp"

  {
    printf "\n%s\n" "$start_marker"
    printf "%s\n" "$content"
    printf "%s\n" "$end_marker"
  } >> "$tmp"

  if ! cmp -s "$file" "$tmp"; then
    backup_file "$file"
    mv "$tmp" "$file"
    record_change "$file"
  else
    rm -f "$tmp"
    record_skip "No changes required in ${file} (${name})"
  fi
}

configure_kali_theme() {
  local theme_file="$1"
  if [ ! -f "$theme_file" ]; then
    fail "Kali-like theme file not found: ${theme_file}"
    exit 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: enforce twoline kali-like prompt"
    return 0
  fi

  backup_file "$theme_file"
  sed -i 's|^[[:space:]]*PROMPT="\$oneline_prompt"|# PROMPT="$oneline_prompt"|' "$theme_file"
  sed -i 's|^[[:space:]]*#[[:space:]]*PROMPT="\$twoline_prompt"|PROMPT="$twoline_prompt"|' "$theme_file"
  record_change "$theme_file"
}

choose_tmux_autostart() {
  case "$TMUX_AUTOSTART_MODE" in
    yes|no)
      return 0
      ;;
    ask)
      if [ "$NON_INTERACTIVE" -eq 1 ]; then
        TMUX_AUTOSTART_MODE="no"
        return 0
      fi
      if confirm "Enable tmux auto-start in new zsh sessions?"; then
        TMUX_AUTOSTART_MODE="yes"
      else
        TMUX_AUTOSTART_MODE="no"
      fi
      ;;
    *)
      fail "Invalid --tmux-autostart value: ${TMUX_AUTOSTART_MODE}"
      exit 1
      ;;
  esac
}

setup_zsh() {
  if [ "$SKIP_ZSH" -eq 1 ]; then
    record_skip "Skipped Zsh setup (--skip-zsh)"
    return 0
  fi

  local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
  local zsh_custom="${zsh_dir}/custom"
  local theme_repo_dir="${zsh_custom}/themes/kali-like-zsh-theme"
  local theme_repo_file="${theme_repo_dir}/kali-like.zsh-theme"
  local theme_file="${zsh_custom}/themes/kali-like.zsh-theme"
  local zshrc="$HOME/.zshrc"

  clone_if_missing "https://github.com/ohmyzsh/ohmyzsh.git" "$zsh_dir"
  clone_if_missing "https://github.com/clamy54/kali-like-zsh-theme" "$theme_repo_dir"
  configure_kali_theme "$theme_repo_file"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: install Kali-like theme at ${theme_file}"
  else
    ln -sfn "$theme_repo_file" "$theme_file"
    record_change "$theme_file"
  fi

  clone_if_missing "https://github.com/zsh-users/zsh-autosuggestions" "${zsh_custom}/plugins/zsh-autosuggestions"
  clone_if_missing "https://github.com/zsh-users/zsh-syntax-highlighting" "${zsh_custom}/plugins/zsh-syntax-highlighting"

  local core_block
  core_block=$(cat <<EOF
export ZSH="${zsh_dir}"
ZSH_THEME="kali-like"
plugins=(git z fzf zsh-autosuggestions zsh-syntax-highlighting)
source "\$ZSH/oh-my-zsh.sh"
EOF
)
  upsert_managed_block "$zshrc" "KALIX_CORE" "$core_block"

  local zoxide_block
  zoxide_block=$(cat <<'EOF'
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
EOF
)
  upsert_managed_block "$zshrc" "KALIX_ZOXIDE" "$zoxide_block"

  local alias_block
  alias_block=$(cat <<'EOF'
alias apt="sudo nala"
EOF
)
  upsert_managed_block "$zshrc" "KALIX_ALIASES" "$alias_block"

  choose_tmux_autostart
  if [ "$TMUX_AUTOSTART_MODE" = "yes" ]; then
    local tmux_block
    tmux_block=$(cat <<'EOF'
if command -v tmux >/dev/null 2>&1; then
  if [ -z "${TMUX-}" ] && [ -n "${PS1-}" ]; then
    tmux new-session -A -s main
  fi
fi
EOF
)
    upsert_managed_block "$zshrc" "KALIX_TMUX_AUTOSTART" "$tmux_block"
  else
    remove_managed_block "$zshrc" "KALIX_TMUX_AUTOSTART"
  fi

  success "Zsh setup completed"
}

setup_tmux() {
  if [ "$SKIP_TMUX" -eq 1 ]; then
    record_skip "Skipped tmux setup (--skip-tmux)"
    return 0
  fi

  local tmux_repo_dir="$HOME/.tmux"
  local tmux_conf="$HOME/.tmux.conf"
  local tmux_local="$HOME/.tmux.conf.local"

  clone_if_missing "https://github.com/gpakosz/.tmux" "$tmux_repo_dir"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "DRY-RUN: symlink ${tmux_repo_dir}/.tmux.conf -> ${tmux_conf}"
  else
    if [ -e "$tmux_conf" ] && [ ! -L "$tmux_conf" ]; then
      backup_file "$tmux_conf"
    fi
    ln -sfn "${tmux_repo_dir}/.tmux.conf" "$tmux_conf"
    record_change "$tmux_conf"
  fi

  if [ ! -f "$tmux_local" ]; then
    info "Creating ${tmux_local}"
    run cp "${tmux_repo_dir}/.tmux.conf.local" "$tmux_local"
    record_change "$tmux_local"
  fi

  local logging_block
  logging_block=$(cat <<'EOF'
set -g @kalix_log_dir "$HOME/tmux-logs"
set -g @kalix_log_file "#{@kalix_log_dir}/tmux-#{session_name}-#{window_index}-#{pane_index}-%Y%m%d-%H%M%S.log"
run-shell -b 'mkdir -p "#{@kalix_log_dir}"'
bind-key L pipe-pane -o "cat >> #{@kalix_log_file}"
EOF
)
  upsert_managed_block "$tmux_local" "KALIX_LOGGING" "$logging_block"

  local defaults_block
  defaults_block=$(cat <<'EOF'
set -g mouse on
set -g history-limit 20000
set -g status-position top
setw -g mode-keys vi
unbind C-b
set -g prefix C-s
bind C-s send-prefix
EOF
)
  upsert_managed_block "$tmux_local" "KALIX_DEFAULTS" "$defaults_block"

  local clipboard_block
  clipboard_block=$(cat <<'EOF'
set -g set-clipboard on
tmux_conf_copy_to_os_clipboard=true
EOF
)
  upsert_managed_block "$tmux_local" "KALIX_CLIPBOARD" "$clipboard_block"

  success "Tmux setup completed"
}

set_default_shell() {
  if [ "$NO_CHSH" -eq 1 ]; then
    record_skip "Skipped changing default shell"
    return 0
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ "${SHELL}" = "$zsh_path" ]; then
    success "Default shell already set to zsh"
    return 0
  fi

  info "Setting default shell to zsh"
  run chsh -s "$zsh_path"
  success "Default shell changed to zsh"
}

run_uninstall() {
  info "Running uninstall: removing Kalix-managed blocks"

  remove_managed_block "$HOME/.zshrc" "KALIX_CORE"
  remove_managed_block "$HOME/.zshrc" "KALIX_ZOXIDE"
  remove_managed_block "$HOME/.zshrc" "KALIX_ALIASES"
  remove_managed_block "$HOME/.zshrc" "KALIX_TMUX_AUTOSTART"

  remove_managed_block "$HOME/.tmux.conf.local" "KALIX_LOGGING"
  remove_managed_block "$HOME/.tmux.conf.local" "KALIX_DEFAULTS"
  remove_managed_block "$HOME/.tmux.conf.local" "KALIX_CLIPBOARD"

  success "Uninstall completed for managed configuration blocks"
}

print_summary() {
  printf "\n"
  info "Run summary"
  printf "- Log file: %s\n" "$LOG_FILE"

  if [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ]; then
    printf "- Installed packages: %s\n" "${INSTALLED_PACKAGES[*]}"
  else
    printf "- Installed packages: none\n"
  fi

  if [ "${#CHANGED_FILES[@]}" -gt 0 ]; then
    printf "- Changed paths: %s\n" "${CHANGED_FILES[*]}"
  else
    printf "- Changed paths: none\n"
  fi

  if [ "${#SKIPPED_STEPS[@]}" -gt 0 ]; then
    printf "- Skipped: %s\n" "${SKIPPED_STEPS[*]}"
  else
    printf "- Skipped: none\n"
  fi

  if [ "${#ERRORS[@]}" -gt 0 ]; then
    printf "- Errors: %s\n" "${ERRORS[*]}"
  else
    printf "- Errors: none\n"
  fi
}

main() {
  init_logging
  print_banner
  parse_args "$@"
  require_non_root
  preflight_checks
  select_profile_packages

  if [ "$UNINSTALL" -eq 1 ]; then
    run_uninstall
    print_summary
    return 0
  fi

  if [ "$ONLY_SHELL" -ne 1 ]; then
    install_packages "${BASE_PACKAGES[@]}" "${PROFILE_PACKAGES[@]}"
  fi

  if [ "$ONLY_PACKAGES" -ne 1 ]; then
    setup_tmux
    setup_zsh
    set_default_shell
  fi

  success "Done. Restart your terminal or run 'exec zsh'."
  print_summary
}

main "$@"
