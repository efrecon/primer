# disk

`disk` formats disks and mount them.

## Description

The `disk` step will format disk as a single big partition and mount them so
they can be used on the system. This step uses a specification file with a disk
specification per line. In the specification file, lines starting with a hash
mark `#` and empty lines are ignored. Otherwise, each line should contain a
number of fields separated by the `:` (colon) sign. These fields are, in order:

- Device to be formatted and mounted, e.g. `sdb`. This should not contain the
  leading `/dev`. Symbolic links, e.g. `disk/by-label/data`, are resolved.
- Filesystem to use on the disk, e.g. `ext4` (the default, see below). Support
  for this filesystem should be present within the OS and can be arranged
  through the [packages] step if necessary.
- Directory where to mount, defaults to `/mnt/disks/` followed by the name of
  the device.
- Comma separated mount options, defaults to `defaults,nofail`.
- Name of user owning the mount point, defaults to `root`.
- Group owning the mount point, defaults to `root`.
- Permissions for the mount point, defaults to `a+w`.

Empty fields, or missing trailing fields, take their default value, e.g. a line
with `sdb` only formats `/dev/sdb` as `ext4` and mounts it at `/mnt/disks/sdb`.

The content of devices is detected with the `blkid` of util-linux, installed
when missing on Alpine: the `blkid` of busybox does not report partition
tables. Without it, devices are left untouched, with a warning. Partitions
known to the kernel also count as a partition table.

Devices that are already mounted are left untouched. Devices that already
contain a filesystem are not reformatted, unless [`--overwrite`](#--overwrite)
is set: they are mounted using their existing filesystem type. Whole disks with
a partition table, but no filesystem, are neither formatted nor mounted, unless
[`--overwrite`](#--overwrite) is set: use one of their partitions instead. The
same goes for devices holding something else than a filesystem, e.g. encrypted
(LUKS) volumes, LVM, RAID or ZFS members, or swap. Formatting is only forced
when overwriting, so `mkfs` keeps its own safety checks otherwise. Devices are
mounted at boot through their UUID in `/etc/fstab`, replacing any previous entry
for the same mount point. When cleaning, devices are unmounted, their entries
removed from `/etc/fstab` and their (empty) mount points removed. Disks are not
erased.

## Options

### `--db`

Specifies the path to the disk specification file.

### `--overwrite`

The value of this option should be a boolean (`yes`/`no`, `true`/`false`,
`on`/`off`, an integer). When it is true, the disk will be reformatted even if
it already contains a filesystem, or a partition table.

### `--ext4`

Options to give to `mkfs.ext4`, these defaults to
`-m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard`. The step adds the
option forcing filesystem creation (`-F` for ext filesystems, `-f` for xfs and
btrfs) only when overwriting existing content, i.e. a filesystem or a partition
table, so `mkfs` keeps its own safety checks otherwise.

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
