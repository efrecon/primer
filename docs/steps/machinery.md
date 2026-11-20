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
default `opt` directory of `primer` so that several branches coexist. At the
time of the installation, the main script from the branch is made available
under the `bin` directory of `primer`: installing another branch clones it, and
points the link to it. Cleaning a branch removes its directory, and the link
only when it points to that branch.

The code is checked out at a fixed commit, see [`--commit`](#--commit): git
verifies that what is checked out is that commit. An existing checkout is moved
to the commit, e.g. after upgrading primer. To install a newer machinery, find
the commit at the tip of its branch, and give it to `--commit`:

```shell
git ls-remote https://github.com/efrecon/machinery.git refs/heads/master
```

  [compose]: https://docs.docker.com/machine/overview/
  [docker]: https://docs.docker.com/engine/
  [branch]: https://github.com/efrecon/machinery/branches

## Options

### `--branch`

Branch of machinery to install, also the name of the directory it is installed
in. This defaults to the master branch.

### `--commit`

Hash of the commit of machinery to install, full or short (resolved from the
history of the branch, it must be unambiguous). Tags are refused: they can move.
By default, the tip of master when this version of primer was released, for the
master branch only: other branches need a commit. An empty value installs the
tip of the branch, without verification.

## Environment Variables

### `PRIMER_STEP_MACHINERY_BRANCH`

This environment variable is the same as the [`--branch`](#--branch) option.

### `PRIMER_STEP_MACHINERY_COMMIT`

This environment variable is the same as the [`--commit`](#--commit) option.

## See Also

[docker][docker_step], [compose][compose_step], [machine][machine_step]

  [docker_step]: ./docker.md
  [compose_step]: ./compose.md
  [machine_step]: ./machine.md
