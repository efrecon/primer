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

This step can run the convenience [script] for installation. The script served
at `get.docker.com` changes with every commit to its [repository][install],
which has no tags. So the step downloads the script from the repository at a
fixed commit instead (see [`--commit`](#--commit)), and only runs it when the
sha256 sum of the whole file matches [`--sha256`](#--sha256). It never runs an
unverified script, and fails instead. The script at the commit is the same as
the one that `get.docker.com` served for that commit, except for the commit it
prints, which the step gives to the script at runtime. A fixed script still
installs the latest stable Docker packages, but an old script might not know a
recent distribution release: [move to a newer commit](#moving-to-a-newer-script)
then.

  [script]: https://get.docker.com/
  [install]: https://github.com/docker/docker-install

The step implements a preference-based logic for how to install the daemon and
CLI when reverting to distribution packages. The default, `auto` will take into
account the distribution and its version to take the most optimal solution.

The step also arranges for the Docker [compose] and [buildx] CLI plugins to be
installed, so that `docker compose` is available and `docker build` uses
[BuildKit]. When a plugin is not already present, e.g. installed by the
convenience [script], the step prefers distribution packages and falls back to
installing the binary from the official releases at github ([compose][github]
and [buildx][buildx-github]) into `/usr/local/lib/docker/cli-plugins`.
Downloaded binaries are always verified against their sha256 sum, and the step
fails, installing nothing, when the verification fails. On Debian derivatives,
the native `docker-compose` package is only used when it is the v2 plugin.
Specifying a version or a sha256 sum forces installation from the binary
releases. When cleaning, downloaded plugins are only removed at the version that
the step installs: the one specified, or the latest release. Pass the same
options as when installing.

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

### `--commit`

Commit of the [repository][install] of the convenience [script] to download the
script from, e.g. `8ad27bd3ac871feabe62f1d926c4067800c1732f`. Change it together
with [`--sha256`](#--sha256).

### `--sha256`

The sha256 sum of the convenience [script], as downloaded. The script only runs
when its sum matches. The default is the sum of the script at the default
[commit](#--commit). An empty sum never runs the script. A value of 40
characters is a git commit, as in older versions of this step, and fails: give
it to [`--commit`](#--commit) instead.

### `--access`

All regular (non-system) users already present on the host that have a name
matching this extended regular expression should be given access to the Docker
[daemon]. They are also given the credentials of the [registries](#--registry),
in a `~/.docker` directory that they own. When empty, the default, only root
has access, and credentials stay with root.

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

### `PRIMER_STEP_DOCKER_INSTALL_COMMIT`

This environment variable is the same as the [`--commit`](#--commit) option.

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
package repository to use on Debian derivatives, i.e. the last 8 hexadecimal
digits of the fingerprint of its key, e.g. `0EBFCD88`. When set, the
convenience [script] only sets up the repository (`--setup-repo`), and its key
is checked before any package is installed from it: the keyring given to
`signed-by` in `/etc/apt/sources.list.d/docker.list`, read with `gpg`
(installed when missing). The step then installs the packages the script would
install: `docker-ce`, `docker-ce-cli`, `containerd.io`,
`docker-ce-rootless-extras`, `docker-compose-plugin` and `docker-buildx-plugin`.
With the wrong key, the repository and its key are removed, nothing is
installed, and the step fails. When empty, the script installs everything, and
the key of the repository is not checked.

### `PRIMER_STEP_DOCKER_GET_URL`

This environment variable is the URL at which to find the convenience [script]
to use when this installation method is relevant. When empty, the default, the
script is downloaded from its [repository][install] at the
[commit](#--commit). As described above the script is verified against
[`--sha256`](#--sha256) before it is run, and, on Debian derivatives, some of
its results are also verified.

### `PRIMER_STEP_DOCKER_PACKAGING`

This environment variable specifies the packaging mode to use when using
distribution-specific packages. It can be:

+ `native`: distribution native packaging will be used.
+ `docker`: Docker repositories will be preferred.
+ `auto` (the default): One of the above will be used depending on the
  distribution and its version.

## Moving to a Newer Script

To use the convenience [script] of a newer commit, find the latest commit of the
[repository][install], review the changes made to `install.sh` since the commit
in use, then compute the sum of the script at the new commit:

```shell
git ls-remote https://github.com/docker/docker-install refs/heads/master
curl -fsSL \
  https://raw.githubusercontent.com/docker/docker-install/<commit>/install.sh \
  | sha256sum
```

Pass both with [`--commit`](#--commit) and [`--sha256`](#--sha256), or change
the defaults at the top of `libexec/steps/docker.sh`.

## See Also

[users]

  [users]: ./users.md