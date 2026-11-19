# docker

`docker` installs Docker and make it available at boot. Arranges for users be
able to access the locally installed and running Docker daemon.

## Description

The `docker` step arranges for the Docker [daemon] and CLI [client] to be
installed on the host. The daemon will be started and scheduled for start at
every boot, and some users can be arranged for access to the daemon. The
`docker` step can arrange for those users to automatically be able to access a
number of remote [registries][registry].

  [daemon]: https://docs.docker.com/engine/reference/commandline/dockerd/
  [client]: https://docs.docker.com/engine/reference/commandline/cli/
  [registry]: https://docs.docker.com/registry/

This step prefers running a convenience [script] for installation, but the
commit SHA256 of the script is verified before running it for improved security.
As this script might change with time, it is then possible for this step to
fail. The step implements a preference-based logic for how to install the daemon
and CLI when reverting to distribution packages. The default, `auto` will take
into account the distribution and its version to take the most optimal solution.

  [script]: https://get.docker.com/

The step also arranges for the Docker [compose] and [buildx] CLI plugins to be
installed, so that `docker compose` is available and `docker build` uses
[BuildKit]. When a plugin is not already present, e.g. installed by the
convenience [script], the step prefers distribution packages and falls back to
installing the binary from the official releases at github ([compose][github]
and [buildx][buildx-github]) into `/usr/local/lib/docker/cli-plugins`.
Downloaded binaries are always verified against their sha256 sum. On Debian
derivatives, the native `docker-compose` package is only used when it is the v2
plugin. Specifying a version or a sha256 sum forces installation from the binary
releases.

  [compose]: https://docs.docker.com/compose/
  [github]: https://github.com/docker/compose/releases
  [buildx]: https://docs.docker.com/build/concepts/overview/#buildx
  [BuildKit]: https://docs.docker.com/build/buildkit/
  [buildx-github]: https://github.com/docker/buildx/releases

## Options

### `--registry`

This option can be specified several times, if necessary. It should point to a
remote [registry] at which to login. The format of the value should be
`username:password@host`.

### `--sha256`

The value of this option is the commit SHA256 sum present at the beginning of
the convenience [script] used whenever necessary.

### `--access`

All regular (non-system) users already present on the host that have a name
matching this extended regular expression should be given access to the Docker
[daemon].

### `--compose-version`

Version of the Docker [compose] plugin to install from the releases at [github],
e.g. `v5.8.0`. This defaults to an empty string, in which case the plugin is
installed from distribution packages, if possible, or the latest release at
[github] otherwise.

### `--compose-sha256`

This is the sha256 sum of the binary release of the [compose] plugin available
at [github]. When the downloaded file does not match, the plugin will not be
installed. This option is best used in combination with a specific
[`--compose-version`](#--compose-version). When empty, the default, the sum is
read from the `checksums.txt` file of the release instead, so downloaded
binaries are always verified.

### `--buildx-version`

Version of the Docker [buildx] plugin to install from the releases at
[github][buildx-github], e.g. `v0.39.0`. This defaults to an empty string, in
which case the plugin is installed from distribution packages, if possible, or
the latest release at [github][buildx-github] otherwise.

### `--buildx-sha256`

This is the sha256 sum of the binary release of the [buildx] plugin available at
[github][buildx-github]. When the downloaded file does not match, the plugin
will not be installed. This option is best used in combination with a specific
[`--buildx-version`](#--buildx-version). When empty, the default, the sum is
read from the `checksums.txt` file of the release instead, so downloaded
binaries are always verified.

## Environment Variables

### `PRIMER_STEP_DOCKER_REGISTRY`

This environment variable should contain a space separated list of Docker
registries at which users specified for Docker daemon access should be logged
in. In the value of the variable, each registry access should be formatted as
the [`--registry`](#--registry) option

### `PRIMER_STEP_DOCKER_INSTALL_SHA256`

This environment variable is the same as the [`--sha256`](#--sha256) option.

### `PRIMER_STEP_DOCKER_ACCESS`

This environment variable is the same as the [`--access`](#--access) option.

### `PRIMER_STEP_DOCKER_COMPOSE_VERSION`

This environment variable is the same as the
[`--compose-version`](#--compose-version) option.

### `PRIMER_STEP_DOCKER_COMPOSE_SHA256`

This environment variable is the same as the
[`--compose-sha256`](#--compose-sha256) option.

### `PRIMER_STEP_DOCKER_BUILDX_VERSION`

This environment variable is the same as the
[`--buildx-version`](#--buildx-version) option.

### `PRIMER_STEP_DOCKER_BUILDX_SHA256`

This environment variable is the same as the
[`--buildx-sha256`](#--buildx-sha256) option.

### `PRIMER_STEP_DOCKER_PLUGINS_DIR`

Directory where to install the [compose] and [buildx] plugins when downloaded
from github.
This defaults to `/usr/local/lib/docker/cli-plugins`, a system-wide location
where the Docker CLI looks for plugins.

### `PRIMER_STEP_DOCKER_APT_GPG`

This environment variable should contain the short GPG signature of the Docker
package repository to use on Debian derivatives. This step will fail when the
convenience [script] installed access to the wrong repository.

### `PRIMER_STEP_DOCKER_GET_URL`

This environment variable is the URL at which to find the convenience [script]
to use when this installation method is relevant. It defaults to
`https://get.docker.com/`. As described above the script is verified before it
is run, and, on Debian derivatives, some of its results are also verified.

### `PRIMER_STEP_DOCKER_PACKAGING`

This environment variable specifies the packaging mode to use when using
distribution-specific packages. It can be:

+ `native`: distribution native packaging will be used.
+ `docker`: Docker repositories will be preferred.
+ `auto` (the default): One of the above will be used depending on the
  distribution and its version.

## See Also

[users]

  [users]: ./users.md