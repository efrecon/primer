# docker

`docker` installs Docker and make it available at boot. Arranges for users be
able to access the locally installed and running Docker daemon.

## Description

The `docker` step arranges for the Docker [daemon] and CLI [client] to be
installed on the host. The daemon will be started and scheduled for start at
every boot, and a list of users can be arranged for access to the daemon. The
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

## Options

### `--registry`

This option can be specified several times, if necessary. It should point to a
remote [registry] at which to login. The format of the value should be `username:password@host`.

### `--sha256`

The value of this option is the commit SHA256 sum present at the beginning of
the convenience [script] used whenever necessary.

### `--access`

List of users already present on the host that should be given access to the
Docker [daemon].

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