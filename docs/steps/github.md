# github

`github` installs binaries out of project releases at [github].

  [github]: https://github.com/

## Description

### Operation

The `github` step uses a specification file to install (or later clean away)
binaries out of releases from one or several projects at [github]. Installation
will happen directly in the default primer bin directory, e.g. `/usr/local/bin`.
In the specification file, lines starting with a hash mark `#` and empty lines
are ignored. Otherwise, each line should contain a number of fields separated by
the spaces. When they have defaults, empty fields can be specified with `""` or
`''`. Recognised fields are, in order:

- The name of the project at [github], e.g. `efrecon/primer`.
- A filter to match against the name of the asset to download and extract the
  binary from. This filter can contain a number of `%`-surrounded tokens that
  will be dynamically be replaced by their value at runtime, see below. Apart
  from those token, this field follows regular globbing rules. The first
  matching asset will be considered for extraction, none other.
- A version filter matching the release name. By default, this is an empty
  string, which will lead to installing the [latest] release. When this is not
  empty, this should be a glob-style filter to match against the name of the
  release.
- The name of the binaries to find inside the asset that was picked up for
  downloading. When empty, the default, this will be the basename of the
  project. Otherwise, this is a globbing filter that will be passed further to
  `find`. Only binaries that are executable by everybody (i.e. user, group and
  others) will be considered for installation.
- The checksum of the asset, see [Checksum Verification](#checksum-verification).
  When empty, the default, the asset is installed unverified, with a warning.

Assets can be archives (`.tar`, `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`,
`.tar.Z` or `.zip`), from which the binaries are extracted, single compressed
binaries (`.gz`, `.bz2` or `.xz`), which are uncompressed, or binaries released
as-is. A single binary is installed under the name of the binary, unless that
name is a glob-filter, in which case the name of the asset (without compression
extension) is kept. Single files are only installed when they are binaries (ELF)
or scripts (starting with `#!`), not e.g. packages or checksums. When
cleaning, only binaries matching the name directly under the bin directory are
removed.

### Asset Filtering

When filtering for asset names within a selected release, this step will
recognise the following `%`-enclosed tokens:

- `%version%` is the version of the release, or to be more specific, the name of
  the release.
- `%semantic%` is a string that looks like several numbers separated by dots,
  extracted from the release name (or `%version%`).
- `%tag%` is the tag of the release, the tag that was given to git when the
  release was created. [github] has guidelines to encourage people to have a
  leading `v` letter in those tags.
- `%semtag%` is a string that looks like several numbers separated by dots,
  extracted from the tag.
- `%bits%` is the number of bits of the platform, as reported by the command
  `getconf LONG_BIT`, e.g. `32` or `64`.
- `%Kernel%` is the type of kernel, result of `uname -s`, as is. This is usually
  in camel-case, where the leading upper-case `K` comes from.
- `%kernel%` is the same as `%Kernel%`, but in lower case.
- `%Machine%` is the architecture, results of `uname -m`, as is.
- `%machine%` is the same as `%Machine%`, but in lower case.

### Checksum Verification

Assets are downloaded first, then verified against the checksum field, and only
then unpacked and installed. The checksum is that of the asset as downloaded,
e.g. the archive, not of the binaries in it. The checksum field is either:

- A sha256 or sha512 sum, in hexadecimal, recognised by its length: 64 or 128
  digits. md5 sums, which do not protect against tampering, are not supported.
- The URL of a checksum file, starting with `https://`, `http://` or `file://`.
- Otherwise, a filter (with globbing rules) for the name of the checksum file
  among the assets of the same release, e.g. `checksums.txt` or `*SHA256SUMS`.

URLs and filters can contain the same `%`-enclosed tokens as asset filters,
together with `%asset%`, the name of the asset to verify, e.g. `%asset%.sha256`
for projects publishing one checksum file per asset. In checksum files, the sum
for the asset is looked for in lines formatted as `<sum>  <name>` or
`<sum> *<name>` (as output by `sha256sum` and friends), or as
`ALGO (<name>) = <sum>` (BSD style, `shasum --tag`, or `ALGO(<name>)= <sum>` as
printed by `openssl dgst`). Names are compared without their leading
directories. A file containing a single sum and nothing else is used as is.

Other algorithms have sums of the same length as sha256 and sha512, e.g. SHA3,
BLAKE3 (64 digits) or BLAKE2b (128 digits). The algorithm of sums from checksum
files is taken, in order, from the tag of BSD-style lines, from the name of the
file (e.g. `SHA512SUMS`, `*.sha256`, `B2SUMS`, `*.md5`), and otherwise from the
length of the sum. Sums of other algorithms than sha256 and sha512, or which
length does not match their algorithm, fail the step.

When the checksum file cannot be found or downloaded, has no sum for the asset,
or when the sum does not match, nothing is installed and the step fails. When
the checksum field is empty, the asset is installed unverified, with a warning,
unless [`--verify`](#--verify) is set: the step then fails.

### Example

The following longer example helps understanding the formatting better:

```
# kubens and kubectx, verified against the checksums of the release.
ahmetb/kubectx kubectx_%version%_%kernel%_%machine%* '' '' checksums.txt
ahmetb/kubectx kubens_%version%_%kernel%_%machine%* '' kubens checksums.txt

# lazy* CUI tools. Keep an old version of lazydocker just for the sake of the
# example, verified against a sum given here.
jesseduffield/lazydocker lazydocker_%semantic%_%Kernel%_%machine%* v0.8 '' 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
jesseduffield/lazygit lazygit_%semantic%_%Kernel%_%machine%* '' '' checksums.txt

# User-friendly Console Editor, one checksum file per asset.
micro-editor/micro micro-%semantic%-%kernel%%bits%-static.tar.gz '' '' https://github.com/micro-editor/micro/releases/download/%tag%/%asset%.sha
```

The two first lines focus on installing the go binaries of the [kubectx]
project. Note the difference between the two lines, one installing the latest
`kubectx` (using the default version and binary name out of the project's name),
the second specifying `kubens` as the binary to find in the compressed tar
files. To be able to get the latest, it specifies an empty version filter
manually. All tokens in the asset filters are tweaked to the naming
[conventions] for the project.

  [kubectx]: https://github.com/ahmetb/kubectx
  [conventions]: https://github.com/ahmetb/kubectx/releases

The remaining lines show more example, including specifying a specific version
for the [lazydocker] project, and the different ways to verify the downloads.
The sum on the lazydocker line is an example, not the real one.

### Comparison to Other Steps

The [lazydocker], [micro], git, machine and docker steps download their
binaries the same way, through the same code (`libexec/github.sh`). Compared
to them, the version of the installed binaries is not verified, and checksums
only when given in the specification file. When cleaning, only binaries
identical to the ones in the release are removed: the asset is downloaded and
verified again for the comparison, binaries are kept, with a warning, when that
fails.

  [latest]: https://developer.github.com/v3/repos/releases/#get-the-latest-release

## Options

### `--projects`

Path to the projects specification file to download and install binaries from.
See above for format.

### `--verify`

A boolean (`yes`/`no`, `true`/`false`, `on`/`off`, an integer), false by
default. When true, assets without a checksum in the specification file are not
installed, and the step fails.

## Environment Variables

### `PRIMER_STEP_GITHUB_PROJECTS`

This environment variable is the same as the [`--projects`](#--projects) option.

### `PRIMER_STEP_GITHUB_VERIFY`

This environment variable is the same as the [`--verify`](#--verify) option.

## See Also

[lazydocker], [micro]

  [lazydocker]: ./lazydocker.md
  [micro]: ./micro.md
