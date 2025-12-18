#!/bin/sh
# shellcheck shell=ash
# Description: Tailscale updater tailored for Buildroot-based systems (e.g., Comet/Comet Pro).
# Source repo: https://github.com/wickedyoda/glinet-tailscale-updater

SCRIPT_VERSION="2025.13.11.01"
SCRIPT_NAME="update-tailscale-buildroot.sh"
UPDATE_URL="https://raw.githubusercontent.com/wickedyoda/glinet-tailscale-updater/refs/heads/main/update-tailscale-buildroot.sh"

IGNORE_FREE_SPACE=0
FORCE=0
FORCE_UPGRADE=0
SHOW_LOG=0
ASCII_MODE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
INFO='\033[0m'

log() {
    local level=$1 message=$2 ts color=$INFO symbol=""
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    case "$level" in
        ERROR) color=$RED;   symbol=$([ "$ASCII_MODE" -eq 1 ] && printf '[X] ' || printf '❌ ');;
        WARNING) color=$YELLOW; symbol=$([ "$ASCII_MODE" -eq 1 ] && printf '[!] ' || printf '⚠️  ');;
        SUCCESS) color=$GREEN;  symbol=$([ "$ASCII_MODE" -eq 1 ] && printf '[OK] ' || printf '✅ ');;
        *) symbol=$([ "$ASCII_MODE" -eq 1 ] && printf '[->] ' || printf 'ℹ️  ');;
    esac
    if [ "$SHOW_LOG" -eq 1 ]; then
        printf "%s[%s] %s%s%s\n" "$color" "$ts" "$symbol" "$message" "$INFO"
    else
        printf "%s%s%s\n" "$color" "$symbol" "$message$INFO"
    fi
}

usage() {
    cat <<'EOF'
Usage: sh update-tailscale-buildroot.sh [OPTIONS]
Options:
  --ignore-free-space   Skip free space check (15 MB recommended)
  --force               Skip confirmations
  --force-upgrade       Reinstall even if already on latest version
  --log                 Show timestamps in log output
  --ascii               Use ASCII log symbols
  --help                Show this help
EOF
}

self_update() {
    log INFO "Checking for script updates"
    remote_version=$(wget -qO- "$UPDATE_URL" | grep -m1 'SCRIPT_VERSION="' | cut -d'"' -f2)
    if [ -z "$remote_version" ]; then
        log WARNING "Could not check remote version; continuing with local copy"
        return
    fi
    if [ "$remote_version" = "$SCRIPT_VERSION" ]; then
        log SUCCESS "Script is up to date"
        return
    fi
    log WARNING "New script version available: $remote_version (current $SCRIPT_VERSION)"
    if [ "$FORCE" -eq 0 ]; then
        printf "Update now? (y/N) "
        read -r answer
        case $(printf "%s" "$answer" | tr 'A-Z' 'a-z') in
            y|yes) ;;
            *) log INFO "Skipping self-update"; return ;;
        esac
    fi
    if wget -q -O "/tmp/$SCRIPT_NAME" "$UPDATE_URL"; then
        chmod +x "/tmp/$SCRIPT_NAME"
        log SUCCESS "Downloaded updated script; re-running"
        exec "/tmp/$SCRIPT_NAME" "$@"
    else
        log ERROR "Failed to download updated script; continuing with current version"
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}:${ID_LIKE:-}" in
            buildroot:*|*:buildroot*)
                log SUCCESS "Buildroot detected: ${PRETTY_NAME:-Buildroot}"
                ;;
            *)
                log WARNING "Non-Buildroot system detected (${PRETTY_NAME:-unknown}); script may still work"
                ;;
        esac
    else
        log WARNING "/etc/os-release missing; unable to confirm Buildroot"
    fi
}

detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64) PKG_ARCH="amd64";;
        aarch64) PKG_ARCH="arm64";;
        armv7l|armv7*) PKG_ARCH="arm";;
        armv6l|armv6*) PKG_ARCH="arm";;
        mips|mips64) PKG_ARCH="mips";;
        mipsel|mips64el) PKG_ARCH="mipsle";;
        *)
            log ERROR "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    log SUCCESS "Architecture detected: $arch (tailscale pkg: $PKG_ARCH)"
}

check_space() {
    avail_mb=$(df -k / | awk 'NR==2 {printf "%.0f", $4/1024}')
    if [ "$avail_mb" -lt 15 ] && [ "$IGNORE_FREE_SPACE" -eq 0 ]; then
        log ERROR "Not enough free space (${avail_mb} MB). Use --ignore-free-space to override."
        exit 1
    fi
    log SUCCESS "Available space: ${avail_mb} MB"
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        log ERROR "Please run as root."
        exit 1
    fi
}

confirm_continue() {
    if [ "$FORCE" -eq 1 ]; then
        return
    fi
    printf "Proceed with update? (y/N) "
    read -r answer
    case $(printf "%s" "$answer" | tr 'A-Z' 'a-z') in
        y|yes) log INFO "Continuing";;
        *) log SUCCESS "Aborted by user"; exit 0;;
    esac
}

find_latest_release() {
    log INFO "Detecting latest Tailscale release for $PKG_ARCH"
    pkg_name=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o "tailscale_[0-9.]*_${PKG_ARCH}\\.tgz" | head -n1)
    if [ -z "$pkg_name" ]; then
        log ERROR "Unable to find release for architecture $PKG_ARCH"
        exit 1
    fi
    TAILSCALE_ARCHIVE_NAME="$pkg_name"
    TAILSCALE_VERSION_NEW=$(printf "%s" "$pkg_name" | sed -n 's/^tailscale_\\([0-9.]*\\)_.*$/\\1/p')
    log SUCCESS "Latest version: $TAILSCALE_VERSION_NEW"
}

download_release() {
    tmp_tar="/tmp/tailscale.tar.gz"
    rm -f "$tmp_tar"
    log INFO "Downloading $TAILSCALE_ARCHIVE_NAME"
    if ! wget -q -O "$tmp_tar" "https://pkgs.tailscale.com/stable/$TAILSCALE_ARCHIVE_NAME"; then
        log ERROR "Download failed"
        exit 1
    fi
    log SUCCESS "Download complete"
}

extract_release() {
    workdir="/tmp/tailscale"
    rm -rf "$workdir"
    mkdir -p "$workdir"
    log INFO "Extracting archive"
    tar xzf /tmp/tailscale.tar.gz -C "$workdir"
    TAILSCALE_SUBDIR=$(tar tzf /tmp/tailscale.tar.gz | grep '/$' | head -n1 | tr -d '/')
    if [ -z "$TAILSCALE_SUBDIR" ]; then
        log ERROR "Failed to locate extracted directory"
        exit 1
    fi
    BIN_DIR="$workdir/$TAILSCALE_SUBDIR"
    if [ ! -x "$BIN_DIR/tailscale" ] || [ ! -x "$BIN_DIR/tailscaled" ]; then
        log ERROR "tailscale binaries not found after extraction"
        exit 1
    fi
}

stop_tailscale() {
    log INFO "Stopping existing tailscaled (best effort)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop tailscaled 2>/dev/null || true
    fi
    if [ -x /etc/init.d/tailscale ]; then
        /etc/init.d/tailscale stop 2>/dev/null || true
    fi
    if [ -x /etc/init.d/tailscaled ]; then
        /etc/init.d/tailscaled stop 2>/dev/null || true
    fi
    killall tailscaled 2>/dev/null || true
}

start_tailscale() {
    log INFO "Starting tailscaled (best effort)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start tailscaled 2>/dev/null || true
    fi
    if [ -x /etc/init.d/tailscale ]; then
        /etc/init.d/tailscale start 2>/dev/null || true
    fi
    if [ -x /etc/init.d/tailscaled ]; then
        /etc/init.d/tailscaled start 2>/dev/null || true
    fi
}

install_release() {
    log INFO "Installing tailscale binaries to /usr/sbin"
    stop_tailscale
    install -m 755 "$BIN_DIR/tailscale" /usr/sbin/tailscale
    install -m 755 "$BIN_DIR/tailscaled" /usr/sbin/tailscaled
    rm -rf /tmp/tailscale /tmp/tailscale.tar.gz
    log SUCCESS "Binaries installed"
}

show_versions() {
    log SUCCESS "Installed tailscale version:"
    tailscale version 2>/dev/null || log WARNING "tailscale not in PATH"
    tailscaled --version 2>/dev/null || true
}

# argument parsing
for arg in "$@"; do
    case "$arg" in
        --ignore-free-space) IGNORE_FREE_SPACE=1 ;;
        --force) FORCE=1 ;;
        --force-upgrade) FORCE_UPGRADE=1 ;;
        --log) SHOW_LOG=1 ;;
        --ascii) ASCII_MODE=1 ;;
        --help) usage; exit 0 ;;
        *) log ERROR "Unknown argument: $arg"; usage; exit 1 ;;
    esac
done

require_root
detect_os
detect_arch
check_space
confirm_continue
self_update "$@"
find_latest_release

CURRENT_VERSION=$(tailscale --version 2>/dev/null | awk 'NR==1 {print $NF}')
if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$TAILSCALE_VERSION_NEW" ] && [ "$FORCE_UPGRADE" -eq 0 ]; then
    log SUCCESS "Already on latest version ($CURRENT_VERSION). Use --force-upgrade to reinstall."
    exit 0
fi

download_release
extract_release
install_release
start_tailscale
show_versions
log SUCCESS "Update complete."
