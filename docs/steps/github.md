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

### Example

The following longer example helps understanding the formatting better:

```
# kubens and kubectx
ahmetb/kubectx kubectx_%version%_%kernel%_%machine%*
ahmetb/kubectx kubens_%version%_%kernel%_%machine%* '' kubens

# lazy* CUI tools. Keep an old version of lazydocker just for the sake of the
# example.
jesseduffield/lazydocker lazydocker_%semantic%_%Kernel%_%machine%* v0.8
jesseduffield/lazygit lazygit_%semantic%_%Kernel%_%machine%*

# User-friendly Console Editor
zyedidia/micro micro-%semantic%-%kernel%%bits%*
```

The two first lines focus on installing the go binaries of the [kubectx] project.
Note the difference between the two lines, one installing the latest `kubectx`
(using the default version and binary name out of the project's name), the
second specifying `kubens` as the binary to find in the compressed tar files. To
be able to get the latest, it specifies an empty version filter manually. All
tokens in the asset filters are tweaked to the naming [conventions] for the
project.

  [kubectx]: https://github.com/ahmetb/kubectx
  [conventions]: https://github.com/ahmetb/kubectx/releases

The remaining lines show more example, including specifying a specific version
for the [lazydocker] project.

### Comparison to Other Steps

Note that compared to other more complete steps such as [lazydocker] or [micro],
this does not perform any verification on the binaries being downloaded. The
checksums will not be verified, neither would the version of the downloaded
binary.

  [latest]: https://developer.github.com/v3/repos/releases/#get-the-latest-release

## Options

### `--projects`

Path to the projects specification file to download and install binaries from.
See above for format.

## Environment Variables

### `PRIMER_STEP_GITHUB_PROJECTS`

This environment variable is the same as the [`--projects`](#--projects) option.

## See Also

[lazydocker], [micro]

  [lazydocker]: ./lazydocker.md
  [micro]: ./micro.md
