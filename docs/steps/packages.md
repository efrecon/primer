# packages

`packages` freshens the OS installation and installs additional packages.

## Description

The `packages` step will install/remove a number of packages for the underlying
OS. Portability across distriburions is impaired by the fact that similar
packages are not called the same in all distributions. By default and when
installing, the list of packages currently installed on the operating system is
both updated and upgraded to their latest versions. This means, that specifying
this step will automatically upgrade your system to the latest versions of all
packages, thus providing for security patches.

## Options

### `--packages`

Specifies the list of packages to be installed. Package names in the list should
be separated by white-spaces. The default is an empty list.

### `--fresh`

The value of this option should be a boolean (`yes`/`no`, `true`/`false`,
`on`/`off`, an integer). When it is true (the default), the list of packages on
the system will be updated and all packages will be upgraded.

## Environment Variables

### `PRIMER_STEP_PACKAGES_PACKAGES`

This environment variable is the same as the [`--packages`](#--packages) option.
It contains twice the word `PACKAGES` in order to respect the naming
conventions, i.e. once for the name of the step itself, and once for what it
targets, i.e. the list of packages.

### `PRIMER_STEP_PACKAGES_FRESH`

This environment variable is the same as the [`--fresh`](#--fresh) option.
