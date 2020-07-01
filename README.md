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

Primer is perhaps best explained through an example, scroll past this section
for documentation. As you probably do not want to pollute your host system just
for testing primer, the example is a little bit more convoluted than necessary
to confine primer to a Docker container and not harm the main host. Let's
simulate the installation of the Docker daemon and client on an [Alpine] host by
running primer in an [Alpine] container. To do this, run the following command
from the main directory of the project:

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
would install Docker directly using the official installation
[script][install-docker] on other distributions. The script, as it is downloaded
from the Internet, will be checked for integrity and on Debian derivatives the
GPG signature of the official Docker repository that it adds to the system will
be validated. Provided you have an account at gitlab.com, the following would
install Docker in an ubuntu container instead, and login the main user (again
`root` in the case of a container) at gitlab (you will have to provide your
credentials!). Note the default is to verify the commit signature of the Docker
installation script against the one hard-coded into the `docker.sh`
implementation. If the official Docker script changes, the `docker` step in
`primer` will fail.

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

  [install-docker]: https://get.docker.com/

In the command above, note the specially formatted option `--docker:registry`.
This option is parsed by primer so that what appears before the separating `:`
(colon sign) is the name of a step to be looked up (in our case, the same step
as above, i.e. `docker`). The remaining forms an option that will be blindly
passed to the `primer_step_docker` function in the implementation. So, in this
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
* [`git`][git] installs git on the system, with [LFS] support. 
* [`dynufw`][dynufw] installs [ufw] and a simplification wrapper on top of ufw.
  The wrapper is able to track host names that would change their pointed IP
  with time (dynamic DNS).
* `timezone` places the host at a given location.
* [`sshkeys`][sshkeys] automatically generates strong SSH keys for the calling
  user. The target of this module are deploy keys when interacting with
  automated CI systems.
* [`docker`][docker] installs the Docker daemon and client, it has been
  described above.
* [`compose`][compose] installs Docker compose at the latest or a specific
  version, together with bash completion. The binary integrity can be verified
  before installation.
* [`machine`][machine] installs Docker machine at the latest or a specific
  version, together with bash completion. The binary integrity can be verified
  before installation.
* [`machinery`][machinery] installs machinery from a given branch (defaults to
  `master`).
* [`lazydocker`][lazydocker] installs lazydocker at the latest or a specific
  version. Lazydocker is a CUI for Docker. Binary integrity is verified before
  installation.
* [`micro`][micro] installs micro at the latest or a specific version. micro is
  a modern editor for the terminal.
* [`github`][github] installs binaries from project releases (assets) at github.
* [`disk`][disk] formats and mounts attached disks.
* [`install`][install] installs (recursively) remote or local files onto the
  host. `install` benefits from the [`--curl`](#curl) option for authenticated
  access to remote resources, when necessary.
* [`freeform`][freeform] looks up and executes binaries in alphabetical order to
  perform free-form installation/removal operations.

  [cc]: https://github.com/canonical/cloud-init/tree/master/cloudinit/config
  [packages]: ./docs/steps/packages.md
  [users]: ./docs/steps/users.md
  [git]: ./docs/steps/git.md
  [LFS]: https://git-lfs.github.com/
  [dynufw]: ./docs/steps/dynufw.md
  [sshkeys]: ./docs/steps/sshkeys.md
  [docker]: ./docs/steps/docker.md
  [compose]: ./docs/steps/compose.md
  [machine]: ./docs/steps/machine.md
  [machinery]: ./docs/steps/machinery.md
  [lazydocker]: ./docs/steps/lazydocker.md
  [micro]: ./docs/steps/micro.md
  [github]: ./docs/steps/github.md
  [disk]: ./docs/steps/disk.md
  [install]: ./docs/steps/install.md
  [freeform]: ./docs/steps/freeform.md
  [ufw]: https://wiki.ubuntu.com/UncomplicatedFirewall

## Options, Environment and Commands

### Options

Primer recognises both single-dash led short options and double-dash led long
options. Long options can be separated from their values using both a space or
an equal sign. After all options come a [command](#commands) instructing Primer
what to do, the default being to perform installation of all steps, no questions
asked. As an example of setting options, all styles, consider the following
invocations that are all equivalent and set verbosity to debug before printing
the help:

```shell
./primer -v debug help
./primer --verbose debug help
./primer --verbose=debug help
```

#### `-p` or `--path`

Colon separated list of directories where to look for the implementation of
steps. The default is the `steps` directory in the `libexec` directory. Note
that when [amalgamated](#packaging), the default is empty as all standard steps
are already part of the amalgamation.

#### `-c` or `--config`

Space separated list of paths to configuration files to read in order, in `.env`
format. These files should contain a number of environment variables to specify
the steps (and their order) that primer will perform, together with variables to
change the options of these steps. In those files, all empty lines or lines
starting with a `#` (hash mark) will be ignored. Variables should be separated
from their values by an equal sign `=` and values should not be quoted. The
default is to [substitute](#no-subst) the value of existing (or set through the
file) variables by their value. Substitution uses an almost eval-safe
[implementation][subst] for security and supports all POSIX [expansion] formats.

The default for this option is to read:

* The file `primer.env` in the current working directory, if present.
* The file `primer_<mac>.env` in the current working directory, if present. It
  will be read on "top" of the previous file. In that filename, at run time,
  `<mac>` will be the MAC address of the main Ethernet interface of the host, in
  lower-case and without any field separators.

Primer is not only able to read files, but also remote resources. To access
protected resources, you can combine with using the [`--curl`](#--curl) option.
In path or resource specifications passed to `--config`, a number of tokens will
automatically be replaced by their value at run time. These are:

* `%mac%` will be replaced with the MAC address of the host, in lower case,
  without any separator signs.
* `%host%` and `%hostname%` will be replaced with the hostname of the host, as
  reported by the command `hostname`.

These defaults and tokens allow to use common primer settings across several
(similar) host installations and in networked settings. Generic options for all
hosts would be placed in the main `primer.env` file, while host-specific options
would be present in the resources using the `%mac%` token. To discover the MAC
address that primer believes is the one of the main Ethernet interface, you can
run the following command:

```shell
./primer -v notice env|grep -E '\s+mac:'|awk '{print $2}'|tr -d ':'
```

  [subst]: https://github.com/YanziNetworks/yu.sh/blob/fc4504e334133fe6d78531ed65301fa64e8b8193/multi-arch.sh#L19
  [expansion]: https://pubs.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html#tag_02_06_02

#### `-no-subst`

When this flag is present, references to environment variables in `.env` files
will not be expanded to their value at run time.

#### `-s` or `--steps`

The value of this option should be the space separated list of steps to
consider. When installing or cleaning, steps will be run in that order, and the
value of this option would override any value that would come from an
environment variable, e.g. read as a [`.env`](#-c-or---config) file.

#### `--curl`

The value of this option is the path to a file matching URLs to their curl
options. In this file, blank lines and lines starting with a `#` (hash mark)
will be ignored. Otherwise, the first item of the line should be an extended
regular expression to match against a URL, and the remaining options that will
be blindly passed to `curl` when it is used to download URLs matching the
expression. The expression itself can be URL encoded to arrange for all special
characters, including possible spaces. This feature can be used, for example,
for debugging purposes, or to provide authentication details to `curl` to access
URLs.

#### `--<step>:<opt>`

Any long option that looks like the above, where `<step>` is the name of an
existing step, and `<opt>` is one of the options supported by the implementation
of the step will be passed further as `--<opt>` to the main function in the
implementation of the step. These values have precedence over any value that
would have been set through environment variables, e.g. read through an
[`.env`](#-c-or---config) file.

#### `-v` or `--verbose`

Change verbosity. Available levels are, from most to least verbose, and as of
the [yu.sh][logging] implementation:

* `trace`
* `debug`
* `info` (default)
* `notice`
* `warn`
* `error`

  [logging]: https://github.com/YanziNetworks/yu.sh/blob/fc4504e334133fe6d78531ed65301fa64e8b8193/log.sh#L46

#### `-h` or `--help`

Print help and exit.

### Commands

Apart from the options, Primer takes a trailing command. The trailing command
blindly defaults to `install`, meaning that the default behaviour will be to
install as specified per the `--steps` command-line option or `PRIMER_STEPS`
environment variable. Primer accepts a number of aliases to those commands:

* `install`, `up`: This is the default command, it will perform all the
  installation steps specified through the `PRIMER_STEPS` environment variable
  or the `--steps` option.
* `clean`, `remove`, `down`: Uninstall the steps specified as for the `install`
  command.
* `env`, `environment`: List all known and accessible steps, together with the
  options and environment variables that can be used to modify their behaviour.
  This also prints out host information, e.g. hostname, MAC address (of the
  primary ethernet interface), name of distribution, version, etc.
* `info`: List all options and environment variables that can be used to modify
  the behaviour of the steps to be run. The list of steps can be specified as
  for the `install` command
* `help`: Print help and exit.

### Environment Variables

Primer recognises a number of environment variables, some of which associated to
its command-line [options](#options). Command-line options always have
precedence over the value coming from environment variables. All variables start
with `PRIMER_`. They are:

* `PRIMER_PATH` is the same as the [`--path`](#-p-or---path) option.
* `PRIMER_EXTS` is a space-separated list of dot-led extensions to add to the
  name of the step when looking for their implementations within `PRIMER_PATH`.
  It defaults to `.sh`.
* `PRIMER_STEPS` is the same as the [`--steps`](#-s-or---steps) option.
* `PRIMER_CONFIG` is the same as the [`--config`](#-c-or---config) option.
* `PRIMER_LOCAL` is the root directory to use as `/usr/local` when manuall
  installing contrib packages of various sorts. It defaults to `/usr/local`.
* `PRIMER_BINDIR` is the `bin` directory under `PRIMER_LOCAL`.
* `PRIMER_LIBDIR` is the `lib` directory under `PRIMER_LOCAL`.
* `PRIMER_OPTDIR` is the `opt` directory under `PRIMER_LOCAL`.
* `PRIMER_CURL_OPTIONS` is the same as the [`--curl`](#--curl) option.

In addition, steps will also recognise environment variables, these all start
with `PRIMER_STEP_`. More details are available in the [conventions] document.

  [conventions]: ./docs/CONVENTIONS.md

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
