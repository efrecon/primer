# compose

`compose` installs Docker compose.

## Description

The `compose` step arranges for the Docker [compose] CLI to be present at the
host. The step is able to pinpoint a given version and to verify the
installation download against its sha256 sum if necessary. The step prefers to
install from the official binary releases at [github], but is also able to
install through Python packaging. In addition, bash completion is made available
to all users of the system.

  [compose]: https://docs.docker.com/compose/
  [github]: https://github.com/docker/compose/releases

On Alpine, support for glibc will automatically be added to the system, as this
is a requirement.

## Options

### `--version`

Version of Docker compose to install. This defaults to an empty string, in which
case the step will detect the latest from the releases available at [github].

### `--sha256`

This is the sha256 sum of the binary release available at [github]. When the
downloaded file does not match, the step will fail. This option is best used in
combination with a specific [`--version`](#--version).

### `--python`

Specifies when Docker compose should be installed through `pip` instead. This
should be one of `never`, `prefer` or `failure` (the default). `failure` means
that the Python method is selected if installation from the binary at [github]
failed for some reason.

## Environment Variables

### `PRIMER_STEP_COMPOSE_VERSION`

This environment variable is the same as the [`--version`](#--version) option.

### `PRIMER_STEP_COMPOSE_SHA256`

This environment variable is the same as the [`--sha256`](#--sha256) option.

### `PRIMER_STEP_COMPOSE_PYTHON`

This environment variable is the same as the [`--python`](#--python) option.

### `PRIMER_STEP_COMPOSE_GLIBC_VERSION`

This is the version of the glibc support package to install. When an empty
string (the default), this step will automatically pick up the latest one.

## See Also

[docker]

  [docker]: ./docker.md