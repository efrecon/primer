# wifi

`wifi` connects the host to a wifi network at boot.

## Description

The `wifi` step installs `wpa_supplicant` and adds a block to
`/etc/network/interfaces` for the wifi interface, so that it connects to a given
network through DHCP, using [ifupdown]. The block is surrounded by comments
starting with `# primer autoadd wifi settings:` and `# primer endof wifi
settings:` followed by the name of the interface. The passphrase is not stored
in clear: the step stores the pre-shared key computed by `wpa_passphrase`
instead. Networks without a passphrase are configured as open networks.

  [ifupdown]: https://manpages.debian.org/ifupdown

When no interface is specified, the step picks the first interface which name
starts with `wl`, e.g. `wlan0`, `wlp2s0` or `wlx00c0ca123456`. The step does
nothing when there is no wifi interface, when no network is specified, or when
the interface already has a global address. A block is only added once per
interface. Once the block is added, the interface is brought down and up again,
to verify the settings.

When cleaning, the interface is brought down if connected, and the block is
removed from `/etc/network/interfaces`. The remaining content of the file is
kept as is.

## Options

### `--interface`

Name of the wifi interface to configure. Empty, the default, to pick the first
wifi interface.

### `--essid`

Name of the network to connect to. `--network` and `--ssid` are aliases.

### `--psk`

Passphrase for the network, empty (the default) for an open network.
`--password`, `--key` and `--passphrase` are aliases.

## Environment Variables

### `PRIMER_STEP_WIFI_INTERFACE`

This environment variable is the same as the [`--interface`](#--interface)
option.

### `PRIMER_STEP_WIFI_ESSID`

This environment variable is the same as the [`--essid`](#--essid) option.

### `PRIMER_STEP_WIFI_PSK`

This environment variable is the same as the [`--psk`](#--psk) option.

### `PRIMER_STEP_WIFI_IFLIST`

Path to the interfaces file, defaults to `/etc/network/interfaces`.
