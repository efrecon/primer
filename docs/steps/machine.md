# machine

`machine` installs Docker machine.

## Description

The `machine` step arranges for the Docker [machine] CLI to be present at the
host. The step is able to pinpoint a given version and to verify the
installation download against its sha256 sum if necessary. By default, it will
install the latest available at [github]. In addition, bash completion is made
available to all users of the system.

  [machine]: https://docs.docker.com/machine/overview/
  [github]: https://github.com/docker/machine/releases

## Options

### `--version`

Version of Docker machine to install. This defaults to an empty string, in which
case the step will detect the latest from the releases available at [github].

### `--sha256`

This is the sha256 sum of the binary release available at [github]. When the
downloaded file does not match, the step will fail. This option is best used in
combination with a specific [`--version`](#--version).

## Environment Variables

### `PRIMER_STEP_MACHINE_VERSION`

This environment variable is the same as the [`--version`](#--version) option.

### `PRIMER_STEP_MACHINE_SHA256`

This environment variable is the same as the [`--sha256`](#--sha256) option.

## See Also

[docker]

  [docker]: ./docker.md