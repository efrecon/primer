# lazydocker

`lazydocker` installs [lazydocker], the Docker CUI.

  [lazydocker]: https://github.com/jesseduffield/lazydocker

## Description

The `lazydocker` step arranges for the [lazydocker] CUI to be present at the
host. The step is able to pinpoint a given version, defaulting to the latest.
Prior to installation, the sha256 sum of the local binary is checked against the
published sha256 sum. Installation will happen directly in the default primer
bin directory, e.g. `/usr/local/bin`.

## Options

### `--version`

Version of `lazydocker` to install. This defaults to an empty string, in which
case the step will detect the latest from the releases available at [github].

  [github]: https://github.com/jesseduffield/lazydocker/releases

## Environment Variables

### `PRIMER_STEP_LAZYDOCKER_VERSION`

This environment variable is the same as the [`--version`](#--version) option.

## See Also

[docker]

  [docker]: ./docker.md
