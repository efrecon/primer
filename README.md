# Primer

Primer is a flexible POSIX shell OS initialisation automator. The main goal is
to bring up barebone minimum OS installations to a minimal set of features for
running containerised applications. Primer automates a number of installation
steps, each of which aiming at the installation of an OS level feature with
minimum dependencies. New steps can easily be written if necessary, as they
interact with primer using a well-defined interface. As such, primer can also be
used in other domains than cloud first applications. Being written in POSIX
compatible shell makes it suitable within the embedded space, for example. The
main target OSes of primer are minimal linux OSes such as [Alpine] Linux,
[Ubuntu] cloud images or [Clear] Linux*.

  [Alpine]: https://alpinelinux.org/
  [Ubuntu]: http://cloud-images.ubuntu.com/
  [Clear]: https://clearlinux.org/

Primer will prep your system automatically with configurations that can be put
under revision control. But primer has no support for dependencies between the
various steps, nor a DSL. It tries to fill the gap between home-made
initialisation scripts and larger solutions such as [Ansible] or [puppet]

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
directory of the project is bind mounted onto the `/primer` directory in the
container (the `-v` option to docker). In that container, we make `primer` the
entrypoint (given the bind mount, `primer` is located at `/primer/primer` in the
container). All options following the name of the image `alpine` are then passed
to `primer`. In this example, we specify a single step, called `docker` and
which [implementation](./libexec/steps/docker.sh) is part of the default set of
[steps](./libexec/steps/).

The command should output something similar to the following. In your terminal,
this is most likely going to be pretty printed with a few colours instead:

```
[20200424-113514] [primer] [notice] Installing docker
[20200424-113514] [primer] [ info ] Loading docker implementation from /primer/libexec/steps/docker.sh
[20200424-113514] [primer] [ info ] Installing docker
[20200424-113514] [primer] [ info ] Installing packages: docker
[20200424-113514] [primer] [ info ] Updating OS package indices (if relevant)
[20200424-113537] [primer] [ info ] Enabling docker daemon at start
[20200424-113537] [primer] [notice] Service docker enable is not relevant in a container
[20200424-113537] [primer] [ info ] Adding root to group docker
```

Primer finds out the implementation of the step called `docker` at
`/primer/libexec/steps/docker.sh` and start requesting the implementation to
install. The implemenation at `docker.sh` is loaded into the main process on
demand. It needs to have a function called with the same name, i.e. `docker` and
that function might be called a few times under the installation procedure. By
default, the current implementation installs the Docker daemon and client, and
arranges for the daemon to start right now and autostart with the OS. This is
the only feature that actually do not work when running in a container. Finally,
the implementation makes sure that the user calling the script, i.e. `root` in
our case, since we are in an unprotected container, is made part of the group
`docker` so that it will be able to call the client with elevating privileges.
In the case of `root`, this is obviously superfluous. But all regular users can
also be made part of that group if necessary.

As the container automatically dies and disappear once `primer` has finished, it
is hard to verify what happened. You can however start the installation of
another step called `forever` after the step called `docker`. `forever` is a
dummy step that will sleep for ever when requested to be installed. It is
implemented [here](./libexec/steps/forever.sh). Modify the command example above
by giving the following option to `primer`:

```shell
-s "docker forever"
```

`primer` will executes both steps in sequence and `forever` will have the side
effect that the container remains up and running, doing mostly nothing. You
should then be able to `docker exec -it` into it from another terminal and poke
around.

The `docker` installation step can do much more. It is for example able to
register at a Docker registry for one (the caller) or all users, and would
install Docker directly using the official installation [script][install] on
other distrbutions. The script, as it is downloaded from the Internet, will be
checked for integrity and on Debian derivatives the GPG signature of the
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
passed to the `docker` function in the implemenation. So, in this case, the
function called `docker`, implemented as part of `docker.sh` will be called as
follows. Note that `registry` automatically became a double-dashed option
`--registry`.

```shell
docker options --registry youruser:XXXXX@registry.gitlab.com
```

Most steps can be communicated with this way. Modifying their behaviour can also
be done through setting environment variables that start with the same name as
the step, but in uppercase, i.e. the `docker` step can be controlled by a series
of environment variables that are called `DOCKER_`. The value of command line
options have precedence over these variables.

Primer sports a number of options to control its behaviour, but also recognises
environment variables constructed the same way, i.e. all starting with
`PRIMER_`. Of interest might be the option called `--config` which should point
to a `.env` formatted file. By default, and if it exists, primer will read the
file called `primer.env` from the current directory when it is called. As this
file can contain any number of environment variables, including `PRIMER_STEPS`
to control which steps to execute and in which order, it is able to form a
"contract" describing what to install on a particular host. Placing these file
in revision control, combined with the ability for primer not only to install,
but also clean a system, it make possible to operate on existing OS
installations in a reproducible way.

## Steps

At the time of writing, primer already have the following steps implemented.
This list will grow with personal needs, or with the help of the community. PRs
are welcome!

* `packages` upgrades the system to the latest and installs additional packages.
* `users` takes a `/etc/passwd` inspired colon separated file to create a number
  of users on the host system. Relevant groups will be created and all users can
  be made members of additional groups (e.g. `sudo`?). The module is able to
  generate strong passwords for all these users if necessary.
* `timezone` places the host at a given location.
* `ssh_keys` automatically generates strong SSH keys for the calling user. The
  target of this module is deploy keys when interacting with automated CI
  systems.
* `docker` installs the Docker daemon and client, it has been described above.
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
