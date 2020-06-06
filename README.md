# Primer

Primer is a flexible OS initialisation automator in pure POSIX shell. The main
goal is to bring up barebone minimum OS installations to a minimal set of
features for running containerised applications. Primer automates a number of
installation steps, each of which aiming at the installation of an OS level
feature with minimum dependencies. New steps can easily be written if necessary,
as they interact with primer using a well-defined interface. As such, primer can
also be used in other domains than cloud first applications. Being written in
POSIX compatible shell makes it suitable within the embedded space, for example.

The main target OSes of primer are minimal linux OSes such as [Alpine] Linux,
Ubuntu [cloud] or [server] images or [Clear] Linux*. Primer is probably best
fitted for initialising "on the metal", rather than VMs where [cloud-init] often
fills such a role.

  [Alpine]: https://alpinelinux.org/
  [cloud]: http://cloud-images.ubuntu.com/
  [server]: https://ubuntu.com/download/server
  [Clear]: https://clearlinux.org/
  [cloud-init]: https://cloudinit.readthedocs.io/en/latest/index.html

Primer will prep your system automatically with configuration descriptions that
can be put under revision control. However, primer has no support for
dependencies between the various steps, nor has a DSL: it rather express machine
configuration through a set of environment variables. Primer tries to fill the
gap between home-made initialisation scripts and larger solutions such as
[Ansible], [puppet] or [cloud-init].

  [Ansible]: https://github.com/ansible/ansible
  [puppet]: https://puppet.com/open-source/#osp

**Note**: Primer is still under development and a little bit of a moving target.
But it has reached enough stability to start being used on real (or virtual)
hosts, rather that test containers. Please raise [issues], or even better, fix
bugs through [PR]s.

  [issues]: https://github.com/efrecon/primer/issues
  [PR]: https://github.com/efrecon/primer/pulls

## Example

Primer is perhaps best explained through an example. As you probably do not want
to pollute your host system just for testing primer, the example is a little bit
more convoluted than necessary to confine primer to a Docker container and not
harm the main host. Let's simulate the installation of the Docker daemon and
client on an [Alpine] host by running primer in an [Alpine] container. To do
this, run the following command from the main directory of the project:

```shell
docker run \
  -it \
  --rm \
  -v $(pwd):/primer:ro \
  --entrypoint /primer/primer \
  alpine \
  -s "docker"
```

This works by creating a transient `alpine` Docker container, in which the main
directory of the project is bind-mounted onto the `/primer` directory in the
container (the `-v` option to docker). In that container, we make `primer` the
entrypoint (given the bind-mount, `primer` is located at `/primer/primer` in the
container). All options following the name of the image `alpine` are then passed
to `primer`. In this example, we specify a single step, called `docker`. Its
[implementation](./libexec/steps/docker.sh) is part of the default set of
[steps](./libexec/steps/).

The command should output something similar to the following. In your terminal,
this is most likely going to be pretty printed with a few colours instead:

```console
[20200428-200338] [primer] [notice] Installing steps: docker
[20200428-200338] [primer] [ info ] Loading docker implementation from /primer/libexec/steps/docker.sh
[20200428-200338] [primer] [ info ] Primer step install>>> docker
[20200428-200338] [primer] [ info ] Installing packages: docker
[20200428-200338] [primer] [ info ] Updating OS package indices (if relevant)
[20200428-200354] [primer] [ info ] Starting Docker daemon
[20200428-200354] [primer] [notice] Service docker start is not relevant in a container
[20200428-200354] [primer] [ info ] Enabling docker daemon at start
[20200428-200354] [primer] [notice] Service docker enable is not relevant in a container
```

Primer finds out the implementation of the step called [`docker`][docker] at
`/primer/libexec/steps/docker.sh` and start requesting the implementation to
install. The implementation at `docker.sh` is loaded into the main process on
demand. It needs to have a function called with the same name, prefixed with
`primer_step_`, i.e. `primer_step_docker`. The function might be called a few
times under the installation procedure. By default, the current implementation
installs the Docker daemon and client, and arranges for the daemon to start
right now and autostart with the OS. This is the only feature that actually do
not work when running in a container. Finally, the implementation makes sure
that the user calling the script, if not `root` is made part of the group
`docker` so that it will be able to call the client with elevating privileges.
All other regular users in the system can also be made part of that group if
necessary. This is a security risk, but is optional and relevant when operating
on unmanned servers.

As the container automatically dies and disappear once `primer` has finished, it
is hard to verify what happened. You can however start the installation of
another step called `forever` after the step called `docker`.
[`forever`][forever] is a dummy step that will sleep forever when requested to
be installed. It is implemented [here](./libexec/steps/forever.sh). Modify the
command example above by giving the following option to `primer`:

```shell
-s "docker forever"
```

  [forever]: ./docs/steps/forever.md

`primer` will executes both steps in sequence and `forever` will have the side
effect that the container remains up and running, doing mostly nothing. You
should then be able to `docker exec -it` into it from another terminal and poke
around.

The `docker` installation step can do much more. It is for example able to
register at a Docker registry for one (the caller) or some seleted users, and
would install Docker directly using the official installation [script][install]
on other distributions. The script, as it is downloaded from the Internet, will
be checked for integrity and on Debian derivatives the GPG signature of the
official Docker repository that it adds to the system will be validated.
Provided you have an account at gitlab.com, the following would install Docker
in an ubuntu container instead, and login the main user (again `root` in the
case of a container) at gitlab (you will have to provide your credentials!).
Note the default is to verify the commit signature of the Docker installation
script against the one hard-coded into the `docker.sh` implementation. If the
official Docker script changes, the `docker` step in `primer` will fail.

```shell
docker run \
  -it \
  --rm \
  -v $(pwd):/primer:ro \
  --entrypoint /primer/primer \
  ubuntu \
  -s "docker" \
  --docker:registry youruser:XXXXX@registry.gitlab.com
```

  [install]: https://get.docker.com/

In the command above, note the specially formatted option `--docker:registry`.
This option is parsed by primer so that what appears before the separating `:`
(colon sign) is the name of a step to be looked up (in our case, the same step
as above, i.e. `docker`). The remaining forms an option that will be blindly
passed to the `primer_step_docker` function in the implemenation. So, in this
case, the function called `primer_step_docker`, implemented as part of
`docker.sh` will be called as follows. Note that `registry` automatically became
a double-dashed option `--registry`.

```shell
primer_step_docker option --registry youruser:XXXXX@registry.gitlab.com
```

Most steps can be communicated with this way. Modifying their behaviour can also
be done through setting environment variables that start with the same name as
the step, but in uppercase, i.e. the `docker` step can be controlled by a series
of environment variables that are called `PRIMER_STEP_DOCKER_`. The value of
command line options have precedence over these variables.

To finish your exploration of the possibilities of primer, run the following
command instead. It creates a few users on the system, they will be made part of
the `docker` group automatically as part of the `docker` step. In this example,
primer takes the list of steps to perform from the `PRIMER_STEPS` environment
variable instead.

```shell
PRIMER_STEPS="users docker" \
docker run \
  -it \
  --rm \
  -e PRIMER_STEPS \
  -v $(pwd):/primer:ro \
  --entrypoint /primer/primer \
  ubuntu \
  --users:db /primer/spec/support/data/users.db \
  --docker:access ".*"
```

Primer sports a number of options to control its behaviour, but also recognises
environment variables constructed the same way, i.e. all starting with
`PRIMER_`. Of interest might be the option called `--config` which should point
to a `.env` formatted file. By default, and if it exists, primer will read the
file called `primer.env` from the current directory when it is called. As this
file can contain any number of environment variables, including `PRIMER_STEPS`
to control which steps to execute and in which order, the file forms a
"contract" describing what to install on a particular host. Placing relevant
`.env` formatted files under revision control, combined with the ability for
primer not only to install, but also clean a system, makes it possible to
operate on existing OS installations in a reproducible way.

## Steps

At the time of writing, primer already have the following steps implemented.
This list will grow with personal needs, or with the help of the community.
[PR]s are welcome! Some inspiration can be taken from the [config][cc]
implementation in [cloud-init].

* [`packages`][packages] upgrades the system to the latest and installs
  additional packages.
* [`users`][users] takes a `/etc/passwd` inspired colon separated file to create
  a number of users on the host system. Relevant groups will be created and all
  users can be made members of additional groups (e.g. `sudo`?). The module is
  able to generate strong passwords for all these users if necessary.
* `timezone` places the host at a given location.
* [`sshkeys`][sshkeys] automatically generates strong SSH keys for the calling
  user. The target of this module are deploy keys when interacting with
  automated CI systems.
* [`docker`][docker] installs the Docker daemon and client, it has been described above.
* `compose` installs Docker compose at the latest or a specific version,
  together with bash completion. The binary integrity can be verified before
  installation.
* `machine` installs Docker machine at the latest or a specific version,
  together with bash completion. The binary integrity can be verified before
  installation.
* `machinery` installs machinery from a given branch (defaults to `master`).
* `lazydocker` installs lazydocker at the latest or a specific version.
  Lazydocker is a CUI for Docker. Binary integrity is verified before
  installation.
* `micro` installs lazydocker at the latest or a specific version. micro is a
  modern editor for the terminal.

  [cc]: https://github.com/canonical/cloud-init/tree/master/cloudinit/config
  [packages]: ./docs/steps/packages.md
  [users]: ./docs/steps/users.md
  [sshkeys]: ./docs/steps/sshkeys.md
  [docker]: ./docs/steps/docker.md

## Packaging

The current implementation depends on a number of internal modules, on the
utility library [yu.sh] and a predefined set of [steps](#steps), even though it
is possible to create and integrate more steps. To make it easier to ship the
script to "raw" servers, primer supports [amalgamation]. To create a single
binary that can easily be copied to a target machine, run the following commands
from the root directory of the project:

```shell
./libexec/yu.sh/bin/amalgamation.sh primer > primer.sh
chmod a+x ./primer.sh
```

  [amalgamation]: https://www.sqlite.org/amalgamation.html
  [yu.sh]: https://github.com/YanziNetworks/yu.sh

## Testing

Primer comes with a test suite, based on [shellspec]. Provided you have
installed [shellspec] and it is in your path, run the following command from the
main directory of the project to run the test suite. The test suite requires
that you have [docker] installed on your machine and that your user is able to
call the `docker` client without elevated privileges. Running inside [docker]
allows to perform OS-wide modifications in the context of containers so as to
not pollute your main system.

```shell
shellspec
```

  [shellspec]: https://shellspec.info/
  [docker]: https://docker.com/

## Contributing

You are more than welcome to contribute through [PR]s. New steps will not be
accepted without minimal test rules or documentation. There are a few coding
[conventions](./docs/CONVENTIONS.md) to follow for all contributors.

## Credits

The original idea for this utility comes from a number of projects at [Yanzi],
including some of the code. The code has since then, undergone large
modifications up to a point where little of the original is left.

Most of the design, refactoring and rewriting has been done on my free-time. A
few enhancements have been sponsored by [Lindborg Systems AB][lsys].

  [Yanzi]: https://github.com/YanziNetworks
  [lsys]: https://lsys.se/