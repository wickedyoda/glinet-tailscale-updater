#!/bin/sh
# shellcheck shell=ash
# Wrapper to run the GL.iNet/OpenWrt tailscale updater on Buildroot systems.
# Target OS information:
#   NAME=Buildroot
#   VERSION=2018.02-rc3-gd56bbacb
#   ID=buildroot
#   VERSION_ID=2018.02-rc3
#   PRETTY_NAME="Buildroot 2018.02-rc3"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "buildroot" ]; then
        echo "[!] This wrapper is intended for Buildroot systems. Detected: ${PRETTY_NAME:-unknown}" >&2
    fi
else
    echo "[!] Could not detect OS information (/etc/os-release missing)." >&2
fi

exec sh "$SCRIPT_DIR/update-tailscale.sh" "$@"
