# firewall

`firewall` opens ports in the firewall of the host.

## Description

The `firewall` step opens incoming ports in the firewall that is relevant for
the host, and closes them again when cleaning. The firewall is detected in the
following order:

1. The firewall forced through the [`--type`](#--type) option, if any.
2. The currently active firewall, i.e. [ufw], [firewalld] or [nftables].
3. On Alpine, [awall] when it manages the firewall, i.e. when at least one
   awall policy is enabled.
4. The default firewall of the distribution, when installed but inactive:
   [ufw] on Ubuntu and Debian derivatives, [firewalld] on Fedora and Red Hat
   derivatives. Rules are registered and will apply once the firewall is
   enabled.
5. [iptables] (and `ip6tables` when present) as a last resort. `iptables` is
   installed when necessary. When the OpenRC `iptables` service is available,
   as on Alpine, rules are saved and the services are enabled so the rules are
   restored at boot. Otherwise, rules are not persistent across reboots.

  [ufw]: https://wiki.ubuntu.com/UncomplicatedFirewall
  [firewalld]: https://firewalld.org/
  [awall]: https://wiki.alpinelinux.org/wiki/Alpine_Wall
  [nftables]: https://wiki.nftables.org/
  [iptables]: https://www.netfilter.org/projects/iptables/

Ports are specified as a space separated list of port definitions. A definition
is either a port number, e.g. `8080`, or a port number and a protocol, e.g.
`8080/tcp`. Supported protocols are `tcp` and `udp` (case-insensitive). A
definition without a protocol opens the port for both TCP and UDP. Invalid
definitions are skipped with a warning.

With nftables, rules are added to the `input` chain of the `inet filter` table
and marked with a comment so that cleaning only removes the rules created by
this step. With awall, each port and protocol pair gets its own policy, e.g.
`primer-8080-tcp`, accepting incoming traffic to the host from all zones.
Cleaning disables and removes these policies, and policies are activated in
both cases.

## Options

### `--port`

Add a single port definition to the set of ports to open. This option can be
specified several times to accumulate ports.

### `--ports`

Replace the entire set of port definitions with the value provided. This is a
space separated list of port definitions.

### `--type`

Force the firewall to operate on, one of `ufw`, `firewalld`, `awall`,
`nftables` or `iptables`. The default is to detect the firewall automatically.

## Environment Variables

### `PRIMER_STEP_FIREWALL_PORTS`

Space separated list of port definitions to open. It is empty by default. The
[`--port`](#--port) option appends to it, while [`--ports`](#--ports) replaces
it entirely.

### `PRIMER_STEP_FIREWALL_TYPE`

Firewall to operate on, same as the [`--type`](#--type) option. Empty by
default, meaning automatic detection.

### `PRIMER_STEP_FIREWALL_MARKER`

Marker for the rules created by this step: the comment of nftables rules and the
prefix of the names of awall policies. Defaults to `primer`.

The marker may only contain the characters accepted in awall policy names, i.e.
ASCII letters, digits and dashes (`[0-9a-zA-Z-]`). Other characters are removed
with a warning. When no character remains, `primer` is used instead.

### `PRIMER_STEP_FIREWALL_AWALL_DIR`

Directory where to place the awall policies created by this step. It must be one
of the directories where awall looks for optional policies. Defaults to
`/etc/awall/optional`.
