# machinery

`machinery` installs [machinery], a CLI to create and manage Docker [machine]
clusters.

  [machinery]: http://docker-machinery.com/
  [machine]: https://docs.docker.com/machine/overview/

## Description

The `machinery` step arranges for the Docker [machinery] CLI to be present at
the host. [machinery] combines [machine], [compose] and [docker] to create and
manage clusters and their applications lifecycles. The step is able to pinpoint
a given [branch] from the git repo. The branch will be checked out under the
default `opt` directory of `primer` so that several branches could coexist. At
the time of the installation, the main script from the branch is made available
under the `bin` directory of `primer`.

  [compose]: https://docs.docker.com/machine/overview/
  [docker]: https://docs.docker.com/engine/
  [branch]: https://github.com/efrecon/machinery/branches

## Options

### `--bramch`

Version of machinery to install. This defaults to the master branch.

## Environment Variables

### `PRIMER_STEP_MACHINERY_BRANCH`

This environment variable is the same as the [`--branch`](#--branch) option.

## See Also

[docker][docker_step], [compose][compose_step], [machine][machine_step]

  [docker_step]: ./docker.md
  [compose_step]: ./compose.md
  [machine_step]: ./machine.md
