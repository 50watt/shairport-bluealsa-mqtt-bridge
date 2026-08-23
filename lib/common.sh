#!/usr/bin/env bash

# Shared helpers for the Shairport Sync to BlueALSA MQTT bridge.

set -u

readonly DEFAULT_CONFIG_FILE="/etc/default/shairport-bluealsa-mqtt-bridge"
readonly LEGACY_CONFIG_FILE="/etc/default/airplay-bluealsa-mqtt-bridge"

log_info() {
    printf '%s\n' "$*"
}

log_error() {
    printf '%s\n' "$*" >&2
}

load_configuration() {
    local config_file=""

    if [[ -n "${BRIDGE_CONFIG_FILE:-}" ]]; then
        config_file="${BRIDGE_CONFIG_FILE}"
    elif [[ -r "${DEFAULT_CONFIG_FILE}" ]]; then
        config_file="${DEFAULT_CONFIG_FILE}"
    elif [[ -r "${LEGACY_CONFIG_FILE}" ]]; then
        config_file="${LEGACY_CONFIG_FILE}"
    else
        config_file="${DEFAULT_CONFIG_FILE}"
    fi

    if [[ ! -r "${config_file}" ]]; then
        log_error "Configuration file is not readable: ${config_file}"
        return 1
    fi

    # The configuration file must only be writable by a trusted administrator.
    # shellcheck disable=SC1090
    source "${config_file}"

    : "${MQTT_HOST:?MQTT_HOST is required}"
    : "${MQTT_PORT:?MQTT_PORT is required}"
    : "${MQTT_TOPIC_PREFIX:?MQTT_TOPIC_PREFIX is required}"
    : "${MQTT_CONFIG_DIRECTORY:?MQTT_CONFIG_DIRECTORY is required}"
    : "${MQTT_STATUS_CLIENT_ID:?MQTT_STATUS_CLIENT_ID is required}"
    : "${MQTT_CONTROL_CLIENT_ID:?MQTT_CONTROL_CLIENT_ID is required}"
    : "${BLUETOOTH_ADAPTER:?BLUETOOTH_ADAPTER is required}"
    : "${SPEAKER_MAC:?SPEAKER_MAC is required}"
    : "${SPEAKER_NAME:?SPEAKER_NAME is required}"

    POLL_INTERVAL="${POLL_INTERVAL:-5}"
    DETAIL_INTERVAL="${DETAIL_INTERVAL:-30}"
    HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"
    VOLUME_STEP="${VOLUME_STEP:-5}"
    VOLUME_MAX="${VOLUME_MAX:-100}"
    RECONNECT_TIMEOUT="${RECONNECT_TIMEOUT:-20}"
    RECOVERY_COOLDOWN="${RECOVERY_COOLDOWN:-60}"
    ENABLE_HCI_METRICS="${ENABLE_HCI_METRICS:-true}"
    BLUETOOTH_SERVICE="${BLUETOOTH_SERVICE:-bluetooth.service}"
    BLUEALSA_SERVICE="${BLUEALSA_SERVICE:-bluealsa.service}"
    SHAIRPORT_SERVICE="${SHAIRPORT_SERVICE:-shairport-sync.service}"

    validate_positive_integer "POLL_INTERVAL" "${POLL_INTERVAL}" || return 1
    validate_positive_integer "DETAIL_INTERVAL" "${DETAIL_INTERVAL}" || return 1
    validate_positive_integer "HEARTBEAT_INTERVAL" "${HEARTBEAT_INTERVAL}" || return 1
    validate_positive_integer "VOLUME_STEP" "${VOLUME_STEP}" || return 1
    validate_positive_integer "VOLUME_MAX" "${VOLUME_MAX}" || return 1
    validate_positive_integer "RECONNECT_TIMEOUT" "${RECONNECT_TIMEOUT}" || return 1
    validate_positive_integer "RECOVERY_COOLDOWN" "${RECOVERY_COOLDOWN}" || return 1

    if ((VOLUME_MAX > 127)); then
        log_error "VOLUME_MAX must not exceed the A2DP limit of 127."
        return 1
    fi

    if [[ ! "${SPEAKER_MAC}" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        log_error "SPEAKER_MAC is not a valid Bluetooth address."
        return 1
    fi

    if [[ ! -r "${MQTT_CONFIG_DIRECTORY}/mosquitto_pub" ]] ||
       [[ ! -r "${MQTT_CONFIG_DIRECTORY}/mosquitto_sub" ]]; then
        log_error "Mosquitto client configuration is missing in ${MQTT_CONFIG_DIRECTORY}."
        return 1
    fi

    export XDG_CONFIG_HOME="${MQTT_CONFIG_DIRECTORY}"
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
        log_error "${name} must be a positive integer; got: ${value}"
        return 1
    fi
}

require_commands() {
    local command_name=""

    for command_name in "$@"; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            log_error "Required command is not available: ${command_name}"
            return 1
        fi
    done
}

speaker_dbus_fragment() {
    printf 'dev_%s' "${SPEAKER_MAC//:/_}"
}

find_pcm_path() {
    timeout 5 bluealsa-cli list-pcms 2>/dev/null |
        grep -F "/$(speaker_dbus_fragment)/a2dpsrc/sink" |
        head -n 1
}

speaker_is_connected() {
    timeout 5 bluetoothctl info "${SPEAKER_MAC}" 2>/dev/null |
        grep -q '^[[:space:]]*Connected:[[:space:]]*yes'
}

read_pcm_property() {
    local pcm_path="$1"
    local property_name="$2"
    local expected_signature="$3"
    local property_output=""

    property_output="$(
        timeout 5 busctl get-property \
            org.bluealsa \
            "${pcm_path}" \
            org.bluealsa.PCM1 \
            "${property_name}" \
            2>/dev/null ||
        true
    )"

    awk -v expected_signature="${expected_signature}" \
        '$1 == expected_signature { print $2; exit }' \
        <<<"${property_output}"
}

read_pcm_property_raw() {
    local pcm_path="$1"
    local property_name="$2"

    timeout 5 busctl get-property \
        org.bluealsa \
        "${pcm_path}" \
        org.bluealsa.PCM1 \
        "${property_name}" \
        2>/dev/null ||
    true
}

decode_volume_property() {
    local property_output="$1"
    local -a fields=()
    local left_channel=""
    local right_channel=""
    local packed_volume=""
    local muted=0
    local average_volume=""

    read -r -a fields <<<"${property_output}"

    case "${fields[0]:-}" in
        q)
            packed_volume="${fields[1]:-}"

            if ! [[ "${packed_volume}" =~ ^[0-9]+$ ]]; then
                return 1
            fi

            left_channel=$(((packed_volume >> 8) & 255))
            right_channel=$((packed_volume & 255))
            ;;
        ay)
            if [[ "${fields[1]:-}" == "1" ]]; then
                left_channel="${fields[2]:-}"
                right_channel="${left_channel}"
            elif [[ "${fields[1]:-}" =~ ^[2-9][0-9]*$ ]]; then
                left_channel="${fields[2]:-}"
                right_channel="${fields[3]:-}"
            else
                return 1
            fi

            if ! [[ "${left_channel}" =~ ^[0-9]+$ ]] ||
               ! [[ "${right_channel}" =~ ^[0-9]+$ ]]; then
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    if (((left_channel & 128) != 0 || (right_channel & 128) != 0)); then
        muted=1
    fi

    left_channel=$((left_channel & 127))
    right_channel=$((right_channel & 127))
    average_volume=$(((left_channel + right_channel) / 2))

    printf '%s %s\n' "${average_volume}" "${muted}"
}

publish_mqtt_value() {
    local client_id="$1"
    local topic_suffix="$2"
    local payload="$3"

    timeout 8 mosquitto_pub \
        -h "${MQTT_HOST}" \
        -p "${MQTT_PORT}" \
        -i "${client_id}" \
        -q 1 \
        -r \
        -t "${MQTT_TOPIC_PREFIX}/${topic_suffix}" \
        -m "${payload}"
}
