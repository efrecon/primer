# micro

`micro` installs [micro], a lightweight modern editor for the terminal.

  [micro]: https://micro-editor.github.io/

## Description

The `micro` step arranges for the [micro] terminal editor to be present at the
host. The step is able to pinpoint a given version, defaulting to the latest.
Prior to installation, the download is verified against the sha256 sum
published next to it (the `.sha` file of the release). The step fails,
installing nothing, when the download or its verification fails, or when the
latest version cannot be found. Installation will happen directly in the
default primer bin directory, e.g. `/usr/local/bin`.

## Options

### `--version`

Version of `micro` to install. This defaults to an empty string, in which case
the step will detect the latest semantic version from the releases available at
[github].

  [github]: https://github.com/micro-editor/micro/releases

## Environment Variables

### `PRIMER_STEP_MICRO_VERSION`

This environment variable is the same as the [`--version`](#--version) option.
