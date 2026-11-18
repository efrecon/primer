# compose

`compose` is deprecated and does nothing else than printing out a notice.

## Description

Docker [compose] is now a Docker CLI plugin, i.e. `docker compose` instead of
`docker-compose`. The plugin is installed (and removed) by the [docker] step,
see its [`--compose-version`][version] and [`--compose-sha256`][sha256] options.
This step is only kept for backwards compatibility: it accepts, but ignores, its
former options, printing a warning for each of them.

  [compose]: https://docs.docker.com/compose/
  [docker]: ./docker.md
  [version]: ./docker.md#--compose-version
  [sha256]: ./docker.md#--compose-sha256

## See Also

[docker]
