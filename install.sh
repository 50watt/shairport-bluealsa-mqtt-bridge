#!/usr/bin/env bash

# Install the bridge scripts and systemd units without overwriting an existing
# site configuration.

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY
readonly CONFIG_FILE="/etc/default/shairport-bluealsa-mqtt-bridge"
readonly LEGACY_CONFIG_FILE="/etc/default/airplay-bluealsa-mqtt-bridge"
readonly DEFAULT_MQTT_CONFIG_DIRECTORY="/etc/shairport-bluealsa-mqtt"
readonly WEB_USER="bridge-web"
readonly WEB_GROUP="bridge-web"
readonly WEB_INSTALL_DIRECTORY="/opt/shairport-bluealsa-mqtt-bridge/web"
readonly WEB_CONFIG_DIRECTORY="/etc/shairport-bluealsa-mqtt-bridge"
readonly WEB_CONFIG_FILE="${WEB_CONFIG_DIRECTORY}/web.json"
readonly WEB_TOKEN_FILE="${WEB_CONFIG_DIRECTORY}/initial-token"

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Run this installer as root.\n' >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required to install the web dashboard.\n' >&2
    exit 1
fi

if ! getent group "${WEB_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${WEB_GROUP}"
fi

if ! id -u "${WEB_USER}" >/dev/null 2>&1; then
    useradd \
        --system \
        --gid "${WEB_GROUP}" \
        --home-dir /nonexistent \
        --shell /usr/sbin/nologin \
        "${WEB_USER}"
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

install -D -m 0755 \
    "${PROJECT_DIRECTORY}/scripts/bridge-config" \
    /usr/local/sbin/bridge-config

install -D -m 0755 \
    "${PROJECT_DIRECTORY}/scripts/bridge-status-export" \
    /usr/local/sbin/bridge-status-export

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

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bridge-status-export.service" \
    /etc/systemd/system/bridge-status-export.service

install -D -m 0644 \
    "${PROJECT_DIRECTORY}/systemd/bridge-web.service" \
    /etc/systemd/system/bridge-web.service

while IFS= read -r web_file; do
    web_relative_path="${web_file#"${PROJECT_DIRECTORY}"/web/}"
    install -D -m 0644 \
        "${web_file}" \
        "${WEB_INSTALL_DIRECTORY}/${web_relative_path}"
done < <(find "${PROJECT_DIRECTORY}/web" -type f -print | sort)

install -d -m 0750 -o root -g "${WEB_GROUP}" "${WEB_CONFIG_DIRECTORY}"

web_token=""

if [[ ! -e "${WEB_CONFIG_FILE}" ]]; then
    mapfile -t generated_web_values < <(
        python3 - <<'PYTHON'
import hashlib
import secrets

token = secrets.token_urlsafe(12)
print(token)
print(hashlib.sha256(token.encode("utf-8")).hexdigest())
print(secrets.token_hex(32))
PYTHON
    )

    web_token="${generated_web_values[0]}"
    web_token_hash="${generated_web_values[1]}"
    web_session_secret="${generated_web_values[2]}"
    web_config_temporary="$(mktemp "${WEB_CONFIG_DIRECTORY}/web.json.XXXXXX")"

    chmod 0600 "${web_config_temporary}"
    printf '{\n  "token_sha256": "%s",\n  "session_secret": "%s"\n}\n' \
        "${web_token_hash}" \
        "${web_session_secret}" >"${web_config_temporary}"
    chown root:"${WEB_GROUP}" "${web_config_temporary}"
    chmod 0640 "${web_config_temporary}"
    mv "${web_config_temporary}" "${WEB_CONFIG_FILE}"

    printf '%s\n' "${web_token}" >"${WEB_TOKEN_FILE}"
    chown root:root "${WEB_TOKEN_FILE}"
    chmod 0600 "${WEB_TOKEN_FILE}"
fi

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
    "  systemctl enable --now bluetooth-reconnect.timer" \
    "BluePort web dashboard:" \
    "  systemctl enable --now bridge-status-export.service bridge-web.service"

if [[ -n "${web_token}" ]]; then
    printf '%s\n' \
        "Initial web setup code: ${web_token}" \
        "Display it again as root with: bridge-config web-token"
fi
