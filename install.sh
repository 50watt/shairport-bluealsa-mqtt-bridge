#!/usr/bin/env bash

# Install the bridge scripts and systemd units without overwriting an existing
# site configuration.

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY
readonly CONFIG_FILE="/etc/default/shairport-bluealsa-mqtt-bridge"
readonly LEGACY_CONFIG_FILE="/etc/default/airplay-bluealsa-mqtt-bridge"
readonly DEFAULT_MQTT_CONFIG_DIRECTORY="/etc/shairport-bluealsa-mqtt"

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Run this installer as root.\n' >&2
    exit 1
fi

install -D -m 0755 \
    "${PROJECT_DIRECTORY}/scripts/bluealsa-mqtt-status" \
    /usr/local/sbin/bluealsa-mqtt-status

install -D -m 0755 \
    "${PROJECT_DIRECTORY}/scripts/bluealsa-mqtt-control" \
    /usr/local/sbin/bluealsa-mqtt-control

install -D -m 0755 \
    "${PROJECT_DIRECTORY}/scripts/bluetooth-reconnect" \
    /usr/local/sbin/bluetooth-reconnect

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/lib/common.sh" \
    /usr/local/lib/shairport-bluealsa-mqtt-bridge/common.sh

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bluealsa-mqtt-status.service" \
    /etc/systemd/system/bluealsa-mqtt-status.service

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bluealsa-mqtt-control.service" \
    /etc/systemd/system/bluealsa-mqtt-control.service

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bluetooth-reconnect.service" \
    /etc/systemd/system/bluetooth-reconnect.service

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bluetooth-reconnect.timer" \
    /etc/systemd/system/bluetooth-reconnect.timer

configuration_action="preserved"

if [[ ! -e "${CONFIG_FILE}" ]]; then
    if [[ -e "${LEGACY_CONFIG_FILE}" ]]; then
        install -D -m 0600 "${LEGACY_CONFIG_FILE}" "${CONFIG_FILE}"
        configuration_action="migrated from ${LEGACY_CONFIG_FILE}"
    else
        install -D -m 0600 \
            "${PROJECT_DIRECTORY}/config/shairport-bluealsa-mqtt-bridge.example" \
            "${CONFIG_FILE}"
        configuration_action="created"
    fi
fi

mqtt_config_directory="$(
    # The root-owned configuration is intentionally a shell fragment and is
    # sourced by the runtime services as well.
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    printf '%s' "${MQTT_CONFIG_DIRECTORY:-${DEFAULT_MQTT_CONFIG_DIRECTORY}}"
)"

case "${mqtt_config_directory}" in
    /)
        printf 'MQTT_CONFIG_DIRECTORY must not be the filesystem root.\n' >&2
        exit 1
        ;;
    /*)
        ;;
    *)
        printf 'MQTT_CONFIG_DIRECTORY must be an absolute path.\n' >&2
        exit 1
        ;;
esac

install -d -m 0700 "${mqtt_config_directory}"

if [[ ! -e "${mqtt_config_directory}/mosquitto_pub" ]]; then
    install -m 0600 \
        "${PROJECT_DIRECTORY}/config/mosquitto_pub.example" \
        "${mqtt_config_directory}/mosquitto_pub"
fi

if [[ ! -e "${mqtt_config_directory}/mosquitto_sub" ]]; then
    install -m 0600 \
        "${PROJECT_DIRECTORY}/config/mosquitto_sub.example" \
        "${mqtt_config_directory}/mosquitto_sub"
fi

systemctl daemon-reload

# Remove the obsolete library only after the replacement and updated units
# have been installed successfully. Legacy configuration remains available for
# rollback and audit purposes.
rm -f /usr/local/lib/airplay-bluealsa-mqtt-bridge/common.sh
rmdir /usr/local/lib/airplay-bluealsa-mqtt-bridge 2>/dev/null || true

printf '%s\n' \
    "Installation completed." \
    "Configuration ${configuration_action}: ${CONFIG_FILE}" \
    "Mosquitto client configuration: ${mqtt_config_directory}" \
    "Then run:" \
    "  systemctl enable --now bluealsa-mqtt-status.service bluealsa-mqtt-control.service" \
    "Optional automatic reconnect:" \
    "  systemctl enable --now bluetooth-reconnect.timer"
