#!/usr/bin/env bash

# Remove installed program files while preserving site configuration and MQTT
# credentials for a recoverable uninstall.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Run this uninstaller as root.\n' >&2
    exit 1
fi

systemctl disable --now \
    bluealsa-mqtt-status.service \
    bluealsa-mqtt-control.service \
    bluetooth-reconnect.timer \
    2>/dev/null || true

rm -f \
    /usr/local/sbin/bluealsa-mqtt-status \
    /usr/local/sbin/bluealsa-mqtt-control \
    /usr/local/sbin/bluetooth-reconnect \
    /usr/local/lib/shairport-bluealsa-mqtt-bridge/common.sh \
    /usr/local/lib/airplay-bluealsa-mqtt-bridge/common.sh \
    /etc/systemd/system/bluealsa-mqtt-status.service \
    /etc/systemd/system/bluealsa-mqtt-control.service \
    /etc/systemd/system/bluetooth-reconnect.service \
    /etc/systemd/system/bluetooth-reconnect.timer

rmdir /usr/local/lib/shairport-bluealsa-mqtt-bridge 2>/dev/null || true
rmdir /usr/local/lib/airplay-bluealsa-mqtt-bridge 2>/dev/null || true
systemctl daemon-reload

printf '%s\n' \
    "Program files removed." \
    "Configuration and Mosquitto credentials under /etc were preserved."
