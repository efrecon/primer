# wifi

`wifi` connects the host to a wifi network at boot.

## Description

The `wifi` step connects the host to a given network through DHCP, using
[ifupdown] on Debian and Ubuntu, [ifupdown-ng] on Alpine. It installs
`wpa_supplicant` and the ifupdown flavour of the distribution, then:

+ Writes the network name and its key to the `wpa_supplicant` configuration
  file `/etc/wpa_supplicant/primer-<interface>.conf`, only readable by root.
  The passphrase is not stored in clear: the step stores the pre-shared key
  computed by `wpa_passphrase` instead. Networks without a passphrase are
  configured as open networks.
+ Adds a block to `/etc/network/interfaces` for the wifi interface, pointing to
  that file (`wpa-conf` with ifupdown, `wifi-config-path` with ifupdown-ng).
  The block holds no secret, as the file is often readable by all. It is
  surrounded by comments starting with `# primer autoadd wifi settings:` and
  `# primer endof wifi settings:` followed by the name of the interface.

  [ifupdown]: https://manpages.debian.org/ifupdown
  [ifupdown-ng]: https://github.com/ifupdown-ng/ifupdown-ng

The passphrase is given to `wpa_passphrase` on its standard input, as the
command line of processes is visible to all users. Recent versions of
`wpa_passphrase` (wpa_supplicant 2.11, e.g. on Alpine 3.24) only read it
from a terminal: it is then passed as an argument, visible for as long as
`wpa_passphrase` runs.

When no interface is specified, the step picks the first interface which name
starts with `wl`, e.g. `wlan0`, `wlp2s0` or `wlx00c0ca123456`. The step does
nothing when there is no wifi interface, when no network is specified, or when
the interface already has a global address. There is one block and one
configuration file per interface: they are replaced when the settings have
changed, e.g. another network or passphrase. Blocks written by older versions
of the step, with the network and its key, are replaced as well. Once in place,
the interface is brought down and up again, to verify the settings.

The step fails, without changing anything, on distributions that do not use
ifupdown, e.g. Fedora, and on hosts where NetworkManager runs, as it would
fight over the interface: use `nmcli` there.

When cleaning, the interface is brought down if connected, the block is removed
from `/etc/network/interfaces` and the configuration file written by primer is
removed. The remaining content of the file is kept as is. A block whose end
marker is missing, e.g. after a manual edit, is never removed or replaced, as
that would remove everything after it: the file is left untouched, with a
warning.

## Options

### `--interface`

Name of the wifi interface to configure. Empty, the default, to pick the first
wifi interface.

### `--essid`

Name of the network to connect to. `--network` and `--ssid` are aliases.

### `--psk`

Passphrase for the network, empty (the default) for an open network.
`--password`, `--key` and `--passphrase` are aliases. Passphrases must have 8
to 63 characters, and network names cannot contain double quotes: the step
fails otherwise, without changing anything.

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

### `PRIMER_STEP_WIFI_CONFDIR`

Directory for the `wpa_supplicant` configuration files written by the step,
defaults to `/etc/wpa_supplicant`.
