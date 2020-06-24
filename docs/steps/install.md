# disk

`install` installs remote or local files/directory to the host.

## Description

The `install` step will install remote or local files/directories to the host.
The `install` step also arranges for specific permissions and ownership of the
destinations. This step takes either a bundle file path or a series of
installation specifications from the command line (or environment variable).
This step uses a specification file with an installation specification per line.
In the specification file, lines starting with a hash mark `#` and empty lines
are ignored. Otherwise, each line should contain a number of fields separated by
the `:` (colon) sign. These fields are, in order:

- The source of the resource to install. To escape special characters, e.g. `:`,
  use URL encoding, as the source will be URL decoded.
- The destination where to install on the host. The destination will also be URL
  decoded.
- Name of user owning the destination, defaults to the same user as the one
  running the script.
- Group owning the destination, defaults to the same group as the one of the
  user running the script.
- Permissions for the destination, defaults to `u+rw,g+r,g-w,o-rw`.

Copying occurs in sequence and in this order:

- First all specifications from the active lines in the file bundle are
  honoured. Copying occurs in the order of the lines in the file.
- Then are all specifications coming from the command-line (or the content of
  the `PRIMER_STEP_INSTALL_TARGETS` environment variable), in order, are
  honoured.

Having a specific order permits to copy directories, but overwrite a specific
file using host-specific information. Or to have generic file installation
specification that will be overwritten for a given host.

The `install` step uses `curl` when downloading remote resources. To access
protected resources, you can match these to the relevant curl [options] using
the `--curl` command-line option (or the `PRIMER_CURL_OPTIONS`)

  [options]: https://curl.haxx.se/docs/manpage.html#OPTIONS

## Options

### `--bundle`

Specifies the path to the specification file that should contain lines specified
as above.

### `--target`

This option can be repeated as many times as needed. Each value to this option
should be formatted as the active lines of the specification file described
above.

## Environment Variables

### `PRIMER_STEP_INSTALL_BUNDLE`

This environment variable is the same as the [`--bundle`](#--bundle) option.

### `PRIMER_STEP_INSTALL_TARGETS`

This environment variable is almost the same as the [`--target`](#--target)
option. However, it should contain a space separated list of installation
specifications.

## See Also

[packages]

  [packages]: ./packages.md
