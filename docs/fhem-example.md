# Generic FHEM MQTT2_DEVICE example

This example assumes the default MQTT client IDs and the topic prefix
`audio/bridge/bluetooth`. Replace the Shairport Sync client ID and topic paths
with the values used by the local installation.

Apply this as a complete raw definition after adapting the placeholders.

```text
defmod audio.bluetooth.bridge MQTT2_DEVICE shairport_receiver
attr audio.bluetooth.bridge autocreate 0
attr audio.bluetooth.bridge readingList shairport_receiver:shairport/receiver/playing:.* playing\
shairport_receiver:shairport/receiver/album:.* album\
shairport_receiver:shairport/receiver/artist:.* artist\
shairport_receiver:shairport/receiver/title:.* title\
bluealsa_mqtt_status:audio/bridge/bluetooth/availability:.* bridgeAvailability\
bluealsa_mqtt_status:audio/bridge/bluetooth/heartbeat:.* bridgeHeartbeat\
bluealsa_mqtt_status:audio/bridge/bluetooth/connected:.* bluetoothConnected\
bluealsa_mqtt_status:audio/bridge/bluetooth/state:.* bluetoothState\
bluealsa_mqtt_status:audio/bridge/bluetooth/device:.* bluetoothDevice\
bluealsa_mqtt_status:audio/bridge/bluetooth/profile:.* bluetoothProfile\
bluealsa_mqtt_status:audio/bridge/bluetooth/volume:.* bluetoothVolume\
bluealsa_mqtt_status:audio/bridge/bluetooth/muted:.* bluetoothMuted\
bluealsa_mqtt_status:audio/bridge/bluetooth/audio-running:.* bluetoothAudioRunning\
bluealsa_mqtt_status:audio/bridge/bluetooth/delay-ms:.* bluetoothDelay\
bluealsa_mqtt_status:audio/bridge/bluetooth/sequence:.* bluetoothSequence\
bluealsa_mqtt_status:audio/bridge/bluetooth/rssi:.* bluetoothRSSI\
bluealsa_mqtt_status:audio/bridge/bluetooth/link-quality:.* bluetoothLinkQuality\
bluealsa_mqtt_status:audio/bridge/bluetooth/shairport-state:.* shairportState\
bluealsa_mqtt_status:audio/bridge/bluetooth/shairport-restarts:.* shairportRestarts\
bluealsa_mqtt_control_publisher:audio/bridge/bluetooth/recovery:.* recoveryState
attr audio.bluetooth.bridge setList volumeUp:noArg audio/bridge/bluetooth/command/volume up\
volumeDown:noArg audio/bridge/bluetooth/command/volume down\
muteToggle:noArg audio/bridge/bluetooth/command/mute toggle\
connectionToggle:noArg audio/bridge/bluetooth/command/connection toggle\
connect:noArg audio/bridge/bluetooth/command/connection connect\
disconnect:noArg audio/bridge/bluetooth/command/connection disconnect\
pair:noArg audio/bridge/bluetooth/command/pair pair\
recover:noArg audio/bridge/bluetooth/command/recover recover
attr audio.bluetooth.bridge event-on-change-reading playing,playbackState,album,artist,title,bridgeAvailability,bridgeHeartbeat,bluetoothConnected,bluetoothState,bluetoothDevice,bluetoothProfile,bluetoothVolume,bluetoothMuted,bluetoothAudioRunning,bluetoothDelay,bluetoothSequence,bluetoothRSSI,bluetoothLinkQuality,shairportState,shairportRestarts,recoveryState,audioHealth
attr audio.bluetooth.bridge userReadings playbackState:playing.* {\
  ReadingsNum($name, "playing", 0)\
    ? "playing"\
    : "stopped"\
},\
audioHealth:(playing|bluetoothConnected|bluetoothAudioRunning|shairportState|recoveryState).* {\
  my $recovery = ReadingsVal($name, "recoveryState", "");;\
  return "recovering" if $recovery eq "running";;\
\
  my $shairport = ReadingsVal($name, "shairportState", "unknown");;\
  return "shairport unavailable" if $shairport ne "running";;\
\
  my $connected = ReadingsNum($name, "bluetoothConnected", 0);;\
  return "speaker disconnected" if !$connected;;\
\
  my $playing = ReadingsNum($name, "playing", 0);;\
  my $audioRunning = ReadingsNum($name, "bluetoothAudioRunning", 0);;\
  return "input active, output unavailable" if $playing && !$audioRunning;;\
  return "audio stream active" if $audioRunning;;\
\
  return "ready";;\
}
attr audio.bluetooth.bridge stateFormat audioHealth<br>artist – title<br>album<br>Bluetooth: bluetoothState · bluetoothVolume % · RSSI bluetoothRSSI · LQ bluetoothLinkQuality
attr audio.bluetooth.bridge webCmd volumeDown:volumeUp:muteToggle:recover
```

`audio stream active` deliberately describes the observable transport state. It
does not claim that sound is physically audible from the speaker.

`connectionToggle` remains available as a maintenance command but is not shown
by default. It conflicts with the optional automatic reconnect timer because
the timer intentionally restores a disconnected speaker.
