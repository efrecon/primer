# freeform

`freeform` finds and executes files for freeform, manual install/clean
operations.

## Description

The `freeform` step executes all matching executable files under a root
directory, in alphabetical order to perform freeform operations. The root
directory should have two sub-directories, called `install` and `clean` and
executable files will be searched for directly under these during installation
or cleaning. By default, executables are run with administrative privileges as
this is meant for installation/removal of system components.

## Options

### `--root`

Path to root directory. This directory should have two sub-directories called
`install` and `clean` under which executables will be searched for. Executable
lookup is **not** recursive, they have to be found directly under the relevant
directory at installation or clean time.

### `--filter`

Filter to match against the name of the executables to lookup. All executable
files found in the relevant directory will be executed, in alphabetical order.
By default, this is `*.sh`.

### `--sudo`

The value of this option should be a boolean (`yes`/`no`, `true`/`false`,
`on`/`off`, an integer). When it is true, the default, the executables should be
run as an administrator.

## Environment Variables

### `PRIMER_STEP_FREEFORM_ROOT`

This environment variable is the same as the [`--root`](#--root) option.

### `PRIMER_STEP_FREEFORM_FILTER`

This environment variable is the same as the [`--filter`](#--filter) option.

### `PRIMER_STEP_FREEFORM_SUDO`

This environment variable is the same as the [`--sudo`](#--sudo) option.
