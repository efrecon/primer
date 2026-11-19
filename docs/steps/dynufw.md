# dynufw

`dynufw` arranges for a set of firewall rules written using host names to be
updated at regular intervals to contain [ufw] rules with IP addresses. Unless
you have explicit needs for hostnames, you should probably use the
[`firewall`](./firewall.md) instead.

  [ufw]: https://wiki.ubuntu.com/UncomplicatedFirewall

## Description

The `dynufw` step will create/remove [ufw] rules at regular intervals based on a
specification file. The file is meant for using dynamic host names, i.e. host
names pointing at IP addresses that may change with time. The step is also able
to make static openings.

In the specification file, lines starting with a hash mark `#` and empty lines
are ignored. Otherwise, each line should contain a number of fields separated by
the `:` (colon) sign. These fields are, in order:

- Protocol to use, e.g. `tcp` or `udp`.
- Port to open for incoming traffic.
- Name of host

The specification file passed to the step is then installed as
`/etc/ufw-dynamic-hosts.allow`. The current IP address of each host is kept in
the comments of the [ufw] rules. Implementation for updating the rules is taken
from the [dynufw] project, which is cloned to `/usr/local/opt/dynufw`. Updates
happen every minute through cron (busybox `crond` on Alpine, `cron` on Debian
derivatives, `cronie` on Fedora derivatives). Once all rules are in place,
[ufw] is enabled.

Static rules are commented with `primer dynufw`. When cleaning, only the rules
of dynufw are removed: static rules carrying that comment, and the rules created
for the lines of the rules file, i.e. with the host as a comment and the exact
same port and protocol. The cron job, the rules file and the dynufw scripts are
removed as well. All other rules are kept, and [ufw] is left enabled.

  [dynufw]: https://github.com/efrecon/dynufw

## Options

### `--static`

Perform a static opening of the firewall for incoming traffic. This option can
be repeated as many times as needed, each leading to a new port opening. A
specification should be of the form `host.tld:port/proto(/d)`, where `host.tld`
is a static host name or an IP address (use `~` instead of `/` for CIDR
notations, e.g. `10.0.0.0~8`), `port` is the port (or dash-separated range of
ports) to open for incoming traffic, `proto` can be one of `tcp` or `udp`
(defaults to `tcp` when omitted) and `/d` can be added to add a dynamic rule at
the end of the specification file. When `host.tld:` is omitted, the port is
opened for all incoming traffic. This is for use when you have few rules to
add.

### `--rules`

This is the location of the rules file to be installed and used for managing dynamic host-based openings at regular intervals.

### `--dns`

DNS server to use when checking and/or opening the rules. The default is an
empty string, i.e. the DNS server available to the host.

## Environment Variables

### `PRIMER_STEP_DYNUFW_STATIC`

This environment variable is almost the same as the [`--static`](#--static)
option. It should contain a space separated specifications as described in the
option.

### `PRIMER_STEP_DYNUFW_RULES`

This environment variable is the same as the [`--rules`](#--rules) option.

### `PRIMER_STEP_DYNUFW_DNS`

This environment variable is the same as the [`--dns`](#--dns) option.

### `PRIMER_STEP_DYNUFW_BRANCH`

This environment variable contains the branch of the [ufw] project to check out
and install for regular updating of the rules. It defaults to `master`.

### `PRIMER_STEP_DYNUFW_SCHEDULE`

This environment variable contains the crontab-compatible schedule when to check
for host names changes. It defaults to `* * * * *`, meaning every once every
minute.
