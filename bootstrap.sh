#!/usr/bin/env bash

# Install the alpha runtime dependencies and launch the dashboard.
# Building Shairport Sync from source will be added in a later alpha release.

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Run this bootstrap as root.\n' >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    printf 'Unable to identify the operating system.\n' >&2
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "debian" ]] || [[ "${VERSION_ID:-}" != "13" ]]; then
    printf '%s\n' \
        "This alpha supports Raspberry Pi OS / Debian 13 only." \
        "Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
fi

architecture="$(dpkg --print-architecture)"

case "${architecture}" in
    arm64|armhf)
        ;;
    *)
        printf 'Unsupported architecture for this alpha: %s\n' "${architecture}" >&2
        exit 1
        ;;
esac

printf '%s\n' \
    "Shairport BlueALSA MQTT Bridge v0.3.0-alpha.2.1" \
    "Platform: ${PRETTY_NAME} (${architecture})" \
    "Installing dashboard and runtime dependencies..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes \
    bluez \
    bluez-alsa-utils \
    gunicorn \
    libasound2-plugin-bluez \
    mosquitto-clients \
    network-manager \
    python3 \
    python3-flask

"${PROJECT_DIRECTORY}/install.sh"

systemctl enable --now \
    bridge-status-export.service \
    bridge-web.service

primary_address="$(
    hostname -I 2>/dev/null |
        awk '{ print $1 }'
)"

printf '\n%s\n' "Bootstrap completed."

if [[ -n "${primary_address}" ]]; then
    printf 'Dashboard: http://%s:8080/\n' "${primary_address}"
fi

printf 'Setup code: '
"${PROJECT_DIRECTORY}/scripts/bridge-config" web-token

if ! command -v shairport-sync >/dev/null 2>&1; then
    printf '\n%s\n' \
        "Shairport Sync is not installed yet." \
        "The reproducible AirPlay 2 source build is planned for a following alpha release."
fi
