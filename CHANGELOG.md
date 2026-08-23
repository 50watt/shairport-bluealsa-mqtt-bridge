# Changelog

## 0.3.0-alpha.2.1 - 2026-08-23

- Make password creation mandatory immediately after the first setup-code
  login.
- Carry the verified setup state in the signed session instead of asking for
  the setup code a second time or exposing it in HTML.
- Accept passwords from 8 characters and recommend 12 or more.
- Silence the expected missing-status warning in the isolated web test.

## 0.3.0-alpha.2 - 2026-08-23

- Introduce the `BluePort` dashboard identity and a purpose-built vector logo.
- Add an authenticated password-change workflow with confirmation and CSRF
  protection.
- Store user passwords as slow Werkzeug password hashes in a writable systemd
  state directory; the initial setup code becomes invalid after the change.

## 0.3.0-alpha.1.2 - 2026-08-23

- Quote the project-directory expansion used to derive web installation paths,
  resolving ShellCheck SC2295.

## 0.3.0-alpha.1.1 - 2026-08-23

- Fix the common-library lookup for the installed `bridge-config` command.
- Remove the undeclared `jq` dependency from the interface test suite.

## 0.3.0-alpha.1 - 2026-08-23

- Add `bridge-config status` with stable human-readable and JSON output.
- Add `bridge-config doctor` with machine-readable diagnostic checks.
- Add a root-generated runtime status snapshot for unprivileged consumers.
- Add an authenticated, read-only Flask and Gunicorn dashboard.
- Add responsive status, audio, service, configuration, and network views.
- Add a Debian 13 ARM bootstrap foundation for dashboard dependencies.
- Preserve the existing 0.2.x runtime services and configuration during an
  alpha installation.
- Add mocked interface tests that run without Bluetooth hardware or systemd.

The alpha bootstrap does not build Shairport Sync yet and the dashboard does
not modify Bluetooth, network, receiver, or MQTT configuration.

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
