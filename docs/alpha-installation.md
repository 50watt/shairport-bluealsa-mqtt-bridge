# v0.3.0-alpha.2.1 installation

This alpha adds the configuration interface foundation and the authenticated
BluePort status dashboard. It is intended for development testing on an
existing bridge installation.

## Supported platform

- Raspberry Pi OS Lite 64-bit based on Debian 13 (Trixie)
- Raspberry Pi `arm64` or `armhf`
- an existing valid bridge configuration
- an existing working Shairport Sync to BlueALSA audio path

The alpha bootstrap installs BlueZ, BlueALSA, Mosquitto clients, NetworkManager,
Flask, and Gunicorn from Debian packages. It does not yet build Shairport Sync
or NQPTP from source.

## Back up the installed version

Before testing an alpha, preserve the current program files, configuration,
credentials, and systemd units. Adapt the destination if it already exists.

```bash
sudo install -d -m 0700 /var/backups/shairport-bluealsa-mqtt-bridge

backup_directory="$(
  sudo mktemp -d \
    /var/backups/shairport-bluealsa-mqtt-bridge/pre-alpha.XXXXXX
)"

sudo cp -a --parents \
  /etc/default/shairport-bluealsa-mqtt-bridge \
  /etc/shairport-bluealsa-mqtt \
  /usr/local/sbin/bluealsa-mqtt-status \
  /usr/local/sbin/bluealsa-mqtt-control \
  /usr/local/sbin/bluetooth-reconnect \
  /usr/local/lib/shairport-bluealsa-mqtt-bridge \
  /etc/systemd/system/bluealsa-mqtt-status.service \
  /etc/systemd/system/bluealsa-mqtt-control.service \
  /etc/systemd/system/bluetooth-reconnect.service \
  /etc/systemd/system/bluetooth-reconnect.timer \
  "${backup_directory}"

printf 'Backup: %s\n' "${backup_directory}"
```

## Install the alpha

Run from the extracted release directory:

```bash
./scripts/check
sudo ./bootstrap.sh
```

The bootstrap displays the dashboard URL and a randomly generated setup code.
The code is stored root-only and can be displayed again with:

```bash
sudo bridge-config web-token
```

## Validate the installation

```bash
sudo bridge-config status
sudo bridge-config status --json
sudo bridge-config doctor

systemctl --no-pager --full status \
  bridge-status-export.service \
  bridge-web.service

journalctl \
  -u bridge-status-export.service \
  -u bridge-web.service \
  --since "10 minutes ago" \
  --no-pager
```

Open the URL printed by the bootstrap, normally:

```text
http://PI_ADDRESS:8080/
```

The first setup-code login opens a mandatory password dialog. The setup code is
already marked as verified and does not need to be entered again. Choose a
password containing at least 8 characters; 12 or more are recommended. The
setup code is no longer accepted after the change.

The alpha dashboard binds to all interfaces on TCP port 8080. Protect the
device with the local network firewall and do not expose the port to the
Internet. Authentication is required, but HTTPS is not part of this alpha.

## Scope and limitations

- Bridge settings remain read-only in this alpha; the dashboard password can
  be changed from the user interface.
- Bluetooth speaker selection is planned for `alpha.3`.
- Network changes with automatic rollback are planned for `alpha.4`.
- Shairport Sync and NQPTP source installation is not implemented yet.
- MQTT connectivity is represented by the bridge service state; an active
  broker probe will be added later.
