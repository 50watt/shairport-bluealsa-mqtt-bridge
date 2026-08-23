# Changelog

## 0.2.0 - 2026-08-23

- Rename the project to Shairport Sync - BlueALSA MQTT Bridge so that AirPlay
  is used only as a compatibility reference rather than as product branding.
- Add a typical use case, an independence disclaimer, and Apple trademark
  attribution to the documentation.
- Move the default configuration, Mosquitto client configuration, and shared
  library to neutral `shairport-bluealsa-mqtt-bridge` paths.
- Automatically migrate an existing 0.1.x configuration while preserving the
  legacy configuration and credential directory for rollback.

## 0.1.3 - 2026-08-23

- Resolve sourced-library paths relative to each checked script with ShellCheck's `SCRIPTDIR` search path.
- Validate the complete repository checks on the target Raspberry Pi with ShellCheck 0.10.0.

## 0.1.2 - 2026-08-23

- Resolve all ShellCheck 0.10.0 findings in the repository checks.
- Follow the shared library during ShellCheck analysis.
- Document the tested Debian, Shairport Sync, BlueALSA, BlueZ, and MQTT client
  versions.
- Declare BlueALSA 4.3.1 as the supported 0.1.x interface.

## 0.1.1 - 2026-08-23

- Stop Shairport Sync before a manual Bluetooth disconnect.
- Wait for the A2DP PCM before starting Shairport Sync after a connect.
- Add an optional 30-second automatic reconnect timer.
- Restore Shairport Sync automatically after timer-driven reconnection.
- Hide the conflicting connection toggle in the default FHEM UI example.

## 0.1.0 - 2026-08-23

- Initial public project structure.
- MQTT status and control services.
- Low-overhead BlueALSA D-Bus monitoring.
- Optional RSSI and link-quality metrics.
- Manual recovery command with cooldown.
- systemd units, installer, documentation, and CI checks.
