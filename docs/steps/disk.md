# disk

`disk` formats disks and mount them.

## Description

The `disk` step will format disk as a single big partition and mount them so
they can be used on the system. This step uses a specification file with a disk
specification per line. In the specification file, lines starting with a hash
mark `#` and empty lines are ignored. Otherwise, each line should contain a
number of fields separated by the `:` (colon) sign. These fields are, in order:

- Device to be formatted and mounted, e.g. `sdb`. This should not contain the
  leading `/dev`.
- Filesystem to use on the disk, e.g. `ext4` (the default, see below). Support
  for this filesystem should be present within the OS and can be arranged
  through the [packages] step if necessary.
- Directory where to mount, defaults to `/mnt/disks/` followed by the name of
  the device.
- Colon separated mount options, defaults to `defaults,discard,nofail`.
- Name of user owning the mount point, defaults to `root`.
- Group owning the mount point, defaults to `root`.
- Permissions for the mount point, defaults to `a+w`.

## Options

### `--db`

Specifies the path to the disk specification file.

### `--overwrite`

The value of this option should be a boolean (`yes`/`no`, `true`/`false`,
`on`/`off`, an integer). When it is true, the disk will be reformatted even if
it already contains a filesystem.

### `--ext4`

Options to give to `mkfs.ext4`, these defaults to
`-m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard`.

## Environment Variables

### `PRIMER_STEP_DISK_DB`

This environment variable is the same as the [`--db`](#--db) option.

### `PRIMER_STEP_DISK_OVERWRITE`

This environment variable is the same as the [`--overwrite`](#--overwrite)
option.

### `PRIMER_STEP_DISK_EXT4`

This environment variable is the same as the [`--ext4`](#--ext4) option. The
name of this variable is constructed out of the filesystem chosen for disk
initialisation, converted to uppercase. So, if the chosen filesystem was `xfs`,
the value of `PRIMER_STEP_DISK_XFS`, if present, would be given as a set of
options to `mkfs.xfs`.

### `PRIMER_STEP_DISK_FORMAT`

The filesystem type to use when formatting the disk, defaults to `ext4`.
Supports for this filesystem has to exist on the host OS.

## See Also

[packages]

  [packages]: ./packages.md
