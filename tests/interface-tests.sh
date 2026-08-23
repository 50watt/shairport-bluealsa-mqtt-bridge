#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_DIRECTORY
temporary_directory="$(mktemp -d)"
readonly temporary_directory

cleanup() {
    rm -rf "${temporary_directory}"
}

trap cleanup EXIT

mock_directory="${temporary_directory}/bin"
mqtt_directory="${temporary_directory}/mqtt"
mkdir -p "${mock_directory}" "${mqtt_directory}"
touch "${mqtt_directory}/mosquitto_pub" "${mqtt_directory}/mosquitto_sub"

cat >"${mock_directory}/mock-command" <<'MOCK'
#!/usr/bin/env bash

case "$(basename "$0")" in
    systemctl)
        case "${1:-}" in
            is-active)
                if [[ "${2:-}" != "--quiet" ]]; then
                    printf 'active\n'
                fi
                exit 0
                ;;
            show)
                printf '0\n'
                exit 0
                ;;
        esac
        ;;
    bluetoothctl)
        printf 'Device 00:11:22:33:44:55\n\tConnected: yes\n'
        exit 0
        ;;
    bluealsa-cli)
        if [[ "${1:-}" == "list-pcms" ]]; then
            printf '/org/bluealsa/hci0/dev_00_11_22_33_44_55/a2dpsrc/sink\n'
        fi
        exit 0
        ;;
    busctl)
        case "${*: -1}" in
            Running) printf 'b true\n' ;;
            Delay) printf 'q 150\n' ;;
            Sequence) printf 'u 10\n' ;;
            Volume) printf 'q 25700\n' ;;
        esac
        exit 0
        ;;
    nmcli)
        printf 'full\n'
        exit 0
        ;;
    ip)
        if [[ "${2:-}" == "route" ]]; then
            printf 'default via 192.0.2.1 dev eth0\n'
        else
            printf '2: eth0    inet 192.0.2.20/24 scope global eth0\n'
        fi
        exit 0
        ;;
    hostname)
        printf 'bridge-test\n'
        exit 0
        ;;
    timeout)
        shift
        exec "$@"
        ;;
    mosquitto_pub|mosquitto_sub)
        exit 0
        ;;
esac

exit 1
MOCK

chmod +x "${mock_directory}/mock-command"

for mock_name in \
    bluealsa-cli \
    bluetoothctl \
    busctl \
    hostname \
    ip \
    mosquitto_pub \
    mosquitto_sub \
    nmcli \
    systemctl \
    timeout; do
    ln -s mock-command "${mock_directory}/${mock_name}"
done

config_file="${temporary_directory}/bridge.conf"
cat >"${config_file}" <<CONFIG
MQTT_HOST="192.0.2.10"
MQTT_PORT="1883"
MQTT_TOPIC_PREFIX="audio/test/bluetooth"
MQTT_CONFIG_DIRECTORY="${mqtt_directory}"
MQTT_STATUS_CLIENT_ID="test_status"
MQTT_CONTROL_CLIENT_ID="test_control"
BLUETOOTH_ADAPTER="hci0"
SPEAKER_MAC="00:11:22:33:44:55"
SPEAKER_NAME="Test Speaker"
CONFIG

status_json="$(
    PATH="${mock_directory}:${PATH}" \
    BRIDGE_CONFIG_FILE="${config_file}" \
    BRIDGE_INSTALLED_COMMON_LIB="${PROJECT_DIRECTORY}/lib/common.sh" \
        "${PROJECT_DIRECTORY}/scripts/bridge-config" status --json
)"

STATUS_JSON="${status_json}" python3 - <<'PYTHON'
import json
import os

status = json.loads(os.environ["STATUS_JSON"])
assert status["schema_version"] == 1
assert status["bridge_version"] == "0.3.0-alpha.2.1"
assert status["overall"] == "streaming"
assert status["audio"]["speaker_name"] == "Test Speaker"
assert status["audio"]["running"] is True
assert status["audio"]["volume"] == 100
assert status["audio"]["delay_ms"] == 15.0
assert status["network"]["address"] == "192.0.2.20"
assert status["services"]["shairport"] == "running"
PYTHON

doctor_json="$(
    PATH="${mock_directory}:${PATH}" \
    BRIDGE_CONFIG_FILE="${config_file}" \
    BRIDGE_COMMON_LIB="${PROJECT_DIRECTORY}/lib/common.sh" \
        "${PROJECT_DIRECTORY}/scripts/bridge-config" doctor --json
)"

DOCTOR_JSON="${doctor_json}" python3 - <<'PYTHON'
import json
import os

doctor = json.loads(os.environ["DOCTOR_JSON"])
assert doctor["healthy"] is True
assert not any(check["status"] == "fail" for check in doctor["checks"])
PYTHON

printf 'Configuration interface tests passed.\n'
