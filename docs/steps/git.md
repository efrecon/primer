# git

`git` installs git with LFS support.

## Description

The `git` step arranges for the installation of [git] and [LFS]. [git] is
installed directly as packaged by the OS distribution, but the step is able to
pinpoint a given version of LFS. By default, the latest official release will be
installed. LFS downloads are verified before installation. By default, this step
will make git LFS available to all regular users of the system, but this can be
changed.

  [git]: https://git-scm.com/
  [LFS]: https://git-lfs.github.com/

## Options

### `--lfs-version`

Version of git LFS to install. This defaults to an empty string, in which
case the step will detect the latest from the releases available at [github].

  [github]: https://github.com/git-lfs/git-lfs/releases

### `--lfs-install`

This is a regular expression to be matched against the name of all regular users
of the system for which git LFS support should be installed. The default is
`.*`, meaning all regular users.

## Environment Variables

### `PRIMER_STEP_GIT_LFS_VERSION`

This environment variable is the same as the [`--lfs-version`](#--lfs-version)
option.

### `PRIMER_STEP_GIT_LFS_INSTALL`

This environment variable is the same as the [`--lfs-install`](#--lfs-install)
option.
