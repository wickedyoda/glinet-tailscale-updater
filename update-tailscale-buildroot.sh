#!/bin/sh
# shellcheck shell=ash
# Wrapper to run the GL.iNet/OpenWrt tailscale updater on Buildroot systems.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
MAIN_SCRIPT="$SCRIPT_DIR/update-tailscale-buildroot.sh"
MAIN_URL="https://raw.githubusercontent.com/wickedyoda/glinet-tailscale-updater/refs/heads/main/update-tailscale-buildroot.sh"

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release

    IS_BUILDROOT=false

    if [ "${ID:-}" = "buildroot" ]; then
        IS_BUILDROOT=true
    elif printf '%s' "${ID_LIKE:-}" | grep -qi "buildroot"; then
        IS_BUILDROOT=true
    fi

    if [ "$IS_BUILDROOT" != true ]; then
        echo "[!] This wrapper is intended for Buildroot systems. Detected: ${PRETTY_NAME:-unknown}" >&2
    fi
else
    echo "[!] Could not detect OS information (/etc/os-release missing)." >&2
fi

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "[*] Fetching main updater script for Buildroot wrapper..."

    if command -v wget >/dev/null 2>&1; then
        if ! wget -q -O "$MAIN_SCRIPT" "$MAIN_URL"; then
            echo "[!] Failed to download update-tailscale-buildroot.sh via wget" >&2
            exit 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL -o "$MAIN_SCRIPT" "$MAIN_URL"; then
            echo "[!] Failed to download update-tailscale-buildroot.sh via curl" >&2
            exit 1
        fi
    else
        echo "[!] Neither wget nor curl is available to download update-tailscale-buildroot.sh" >&2
        exit 1
    fi

    chmod +x "$MAIN_SCRIPT"
fi

exec sh "$MAIN_SCRIPT" "$@"
