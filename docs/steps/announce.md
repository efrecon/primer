# announce

`announce` installs and enables network announcement services on the host.

## Description

The `announce` step arranges for the host to be discoverable on the local
network via one or more announcement methods. By default, it enables both
[mDNS] and [NetBIOS] so the machine can be found by its hostname from other
devices without manual DNS configuration.

  [mDNS]: https://en.wikipedia.org/wiki/Multicast_DNS
  [NetBIOS]: https://en.wikipedia.org/wiki/NetBIOS

mDNS support is provided by the [Avahi] daemon (`avahi-daemon`), which allows
the host to be reached as `hostname.local` on the local network. NetBIOS
support is provided by [Samba]'s `nmbd` daemon, enabling hostname resolution
for Windows clients.

  [Avahi]: https://avahi.org/
  [Samba]: https://www.samba.org/

The daemons are started and enabled at boot, through their service: Avahi is
`avahi-daemon` everywhere, `nmbd` runs as the `nmbd` service on Debian and
Ubuntu, `nmb` on Fedora, and as part of the `samba` service on Alpine (which,
as configured in `/etc/conf.d/samba`, also runs `smbd`). When a firewall is active, their
ports are opened (5353/udp for mDNS, 137/udp and 138/udp for NetBIOS) through
the [firewall] step, with the marker `primer-announce`. When cleaning, the
daemons are stopped and disabled, and the ports opened by this step closed.
Rules that existed before are kept, and so are the packages: they might have
been installed before primer, e.g. Samba on a file server.

  [firewall]: ./firewall.md

## Options

### `--method`

Add a single announcement method to the set of methods to enable. The first
occurrence of this option replaces the default set of methods, further
occurrences add to it, without duplicates. In other words, `--method mDNS`
enables mDNS only. Recognised values are `mDNS` and `NetBIOS`
(case-insensitive).

### `--methods`

Replace the entire set of announcement methods with the value provided. This is
a space-separated list of method names. Setting this to an empty string
disables all announcements.

## Environment Variables

### `PRIMER_STEP_ANNOUNCE_METHODS`

This environment variable controls the set of DNS announcement methods to
install and enable. It is a space-separated list of method names and defaults
to `mDNS NetBIOS`. The [`--method`](#--method) option replaces it at first, then
appends to it, while [`--methods`](#--methods) replaces it entirely.
