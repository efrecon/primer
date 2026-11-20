# timezone

`timezone` places the host at a given location.

## Description

The `timezone` step links `/etc/localtime` to the timezone database entry for
the requested location, e.g. `Europe/Stockholm`. On Debian derivatives, Fedora
and Alpine, the `tzdata` package is installed first, if necessary. An existing
`/etc/localtime`, including a dangling link, is replaced. When the distribution
uses an `/etc/timezone` file, it is updated as well.

The step fails when the location is not known to the timezone database, i.e.
not a timezone file under the database directory, e.g. `zone1970.tab`, or a
location with `..` or a leading `/`. When
no location is specified, the step does nothing. Timezone information cannot
be removed, so cleaning only prints a warning.

## Options

### `--location`

The location to place the host at, as in the timezone database, e.g.
`Europe/Stockholm` or `America/New_York`. The default is empty, i.e. do nothing.

## Environment Variables

### `PRIMER_STEP_TIMEZONE_LOCATION`

This environment variable is the same as the [`--location`](#--location)
option.

### `PRIMER_STEP_TIMEZONE_ZONEINFO`

Directory containing the timezone database, defaults to `/usr/share/zoneinfo`.
