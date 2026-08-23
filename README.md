# Shairport Sync - BlueALSA MQTT Bridge

A small, systemd-managed bridge that forwards audio received by Shairport Sync
to a Bluetooth speaker through BlueALSA. It publishes operational state to
MQTT and accepts a strict allowlist of MQTT control commands.

The project is designed for headless Linux audio appliances, including
Raspberry Pi systems running Shairport Sync, BlueZ, and BlueALSA.

## Typical use case

You have an existing Bluetooth speaker but want to use it as a network audio
destination without replacing the speaker.

A small Linux system such as a Raspberry Pi receives audio compatible with the
AirPlay software feature through Shairport Sync and forwards the decoded PCM
stream to the speaker through BlueALSA. This project adds MQTT monitoring,
control, reconnect handling, and recovery around that audio path.

For example:

- an audio source selects the Shairport Sync receiver as its destination;
- Shairport Sync receives and decodes the stream;
- BlueALSA sends the audio to a paired Bluetooth speaker;
- a home automation system monitors connection and playback state through
  MQTT; and
- volume, mute, reconnect, and recovery can be controlled remotely.

The MQTT interface is platform-independent. FHEM is included as one example,
but Home Assistant, Node-RED, openHAB, or custom MQTT clients can use the same
topics.

## Features

- Bluetooth connection, A2DP PCM, and Shairport Sync health reporting
- Low-overhead D-Bus property reads for active stream state
- Retained MQTT status snapshots and periodic heartbeats
- Optional Bluetooth Classic RSSI and controller link-quality metrics
- Relative volume, mute, connect, disconnect, pairing, and recovery commands
- Retained MQTT commands are rejected to prevent command replay
- systemd hardening and automatic service restart
- Site-specific values are stored outside the scripts

## Architecture

```text
Compatible audio source
    -> Shairport Sync
    -> ALSA BlueALSA PCM
    -> BlueALSA A2DP source
    -> Bluetooth speaker

MQTT broker
    <-> status publisher
    <-> control gateway
```

## Requirements

- Bash 5 or later
- systemd
- BlueZ tools (`bluetoothctl`, optionally `hcitool`)
- BlueALSA tools (`bluealsa-cli`)
- Mosquitto clients (`mosquitto_pub`, `mosquitto_sub`)
- Shairport Sync configured with a BlueALSA output device
- `busctl`, `timeout`, and standard GNU userland tools

## Supported and tested platform

Version 0.2.x targets the stable BlueALSA 4.3.1 command and D-Bus interfaces.
It does not yet support the renamed `bluealsad` and `bluealsactl` development
interfaces found after the 4.3.1 release.

The 0.2.0 runtime is based on the 0.1.3 code validated with:

- Raspberry Pi 3B+
- Debian GNU/Linux 13.6 (Trixie), arm64
- Linux 6.18 Raspberry Pi kernel
- Shairport Sync 5.2.1 with AirPlay 2 software feature support, ALSA, soxr,
  metadata, and MQTT
- BlueALSA 4.3.1
- BlueZ 5.82
- Mosquitto clients 2.0.21
- ShellCheck 0.10.0

The bridge assumes that Shairport Sync can already play through the configured
BlueALSA A2DP source PCM. It does not build or configure Shairport Sync,
BlueALSA, Bluetooth pairing, or the MQTT broker.

The status and control services run as root because they query systemd,
Bluetooth HCI state, and BlueALSA. The included units restrict filesystem and
kernel access while preserving the required D-Bus, network, and Bluetooth
interfaces.

## Installation

```bash
sudo ./install.sh
```

Edit:

```text
/etc/default/shairport-bluealsa-mqtt-bridge
```

Set at least:

```text
MQTT_HOST
MQTT_TOPIC_PREFIX
SPEAKER_MAC
SPEAKER_NAME
```

Configure broker authentication or TLS in:

```text
/etc/shairport-bluealsa-mqtt/mosquitto_pub
/etc/shairport-bluealsa-mqtt/mosquitto_sub
```

### Upgrading from 0.1.x

The installer copies an existing legacy configuration to
`/etc/default/shairport-bluealsa-mqtt-bridge` when the new configuration does
not yet exist. The copied configuration continues to reference its existing
Mosquitto credential directory, so credentials are neither rewritten nor
duplicated. The legacy configuration file is preserved for rollback.

After installation, restart the two long-running services so that systemd uses
the new shared-library path:

```bash
sudo systemctl restart \
  bluealsa-mqtt-status.service \
  bluealsa-mqtt-control.service
```

Then enable the long-running services:

```bash
sudo systemctl enable --now \
  bluealsa-mqtt-status.service \
  bluealsa-mqtt-control.service
```

The reconnect helper is a one-shot service and can be invoked manually:

```bash
sudo systemctl start bluetooth-reconnect.service
```

To reconnect a speaker automatically after it is powered on or returns to
range, enable the optional timer:

```bash
sudo systemctl enable --now bluetooth-reconnect.timer
```

The timer checks the connection every 30 seconds. When it reconnects a speaker,
it waits for the A2DP PCM and starts Shairport Sync if necessary.

## MQTT status topics

All topics are relative to `MQTT_TOPIC_PREFIX`.

| Topic | Example | Meaning |
|---|---:|---|
| `availability` | `online` | Status publisher process state |
| `heartbeat` | `1787495722` | Unix timestamp published periodically |
| `connected` | `1` | BlueZ connection state |
| `state` | `streaming` | Combined Bluetooth/BlueALSA state |
| `device` | `Bluetooth speaker` | Configured display name |
| `profile` | `a2dp` | Active audio profile |
| `audio-running` | `1` | BlueALSA transport is acquired |
| `volume` | `75` | Average left/right BlueALSA volume |
| `muted` | `0` | BlueALSA mute state |
| `delay-ms` | `15.0` | BlueALSA transport delay |
| `sequence` | `10` | BlueALSA PCM connection sequence |
| `rssi` | `-9` | Controller-specific Bluetooth RSSI value |
| `link-quality` | `255` | Controller-specific link quality |
| `shairport-state` | `running` | Shairport Sync systemd state |
| `shairport-restarts` | `4` | systemd restart counter |
| `recovery` | `completed` | Last manual recovery result |

Possible combined `state` values are:

- `bluetooth-unavailable`
- `disconnected`
- `connected`
- `bluealsa-unavailable`
- `connected-no-audio`
- `audio-ready`
- `streaming`

## MQTT commands

Commands are not retained. The control gateway also uses `mosquitto_sub -R` to
reject retained messages received from the broker.

| Topic suffix | Payloads |
|---|---|
| `command/volume` | `up`, `down` |
| `command/mute` | `on`, `off`, `toggle` |
| `command/connection` | `connect`, `disconnect`, `toggle` |
| `command/pair` | `pair` |
| `command/recover` | `recover` |

Recovery ensures that the speaker has an A2DP PCM path and then restarts the
configured Shairport Sync service. A cooldown prevents rapid repeated recovery
attempts.

Manual disconnect first stops Shairport Sync so that removing an active
BlueALSA PCM cannot trigger an output-device crash. Connect waits for the A2DP
PCM before starting Shairport Sync again.

Do not expose a persistent disconnect control while the optional reconnect
timer is enabled: the timer will intentionally reconnect the speaker. Disable
the timer first when a persistent manual disconnect is required.

## Monitoring limitations

`audio-running=1` means that BlueALSA has acquired the transport and can accept
audio samples. It does not prove that the speaker is physically producing
sound. A speaker that changes to a second Bluetooth source can therefore remain
technically connected while its audible output comes from another device.

RSSI for Bluetooth Classic is controller-specific and should not be interpreted
as an absolute dBm value. Establish local good and bad baselines before defining
alerts. `hcitool` is deprecated; set `ENABLE_HCI_METRICS=false` where it is not
available.

## FHEM

A generic MQTT2_DEVICE example is available in
[`docs/fhem-example.md`](docs/fhem-example.md).

## Development

Run the local checks with:

```bash
./scripts/check
```

The GitHub Actions workflow runs Bash syntax checks and ShellCheck.

## Trademark notice

AirPlay is a trademark of Apple Inc., registered in the U.S. and other
countries and regions.

This independent project has not been authorized, sponsored, or otherwise
approved by Apple Inc.

## License

MIT License. See [`LICENSE`](LICENSE).
