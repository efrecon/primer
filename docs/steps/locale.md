# locale

`locale` sets the locale of the system.

## Description

The `locale` step sets the `LC_ALL` variable in `/etc/environment` to the
locale requested. Any previous `LC_ALL` setting in that file is replaced, so the
step can be run several times. When cleaning, the `LC_ALL` line for the locale
is removed from `/etc/environment`, other lines are kept.

When the distribution supports it, the locale is also generated:

+ On Debian, the `locales` package is installed, the locale is enabled in
  `/etc/locale.gen` and `locale-gen` is run. Locales not listed in
  `/etc/locale.gen` are added, with the charset from the list of supported
  locales, or from their name, e.g. `UTF-8` for `sv_SE.UTF-8`; they are not
  generated when the charset is unknown. The built-in `C` and `POSIX` locales
  need no generation.
+ On Ubuntu, the `locales` package is installed and `locale-gen` is run with
  the locale.
+ On other distributions, `locale-gen` is run with the locale when it exists.
  Alpine (musl) has no locale generation.

## Options

### `--locale`

The locale to set, e.g. `sv_SE.UTF-8`. The default is `en_US.UTF-8`.

## Environment Variables

### `PRIMER_STEP_LOCALE_LOCALE`

This environment variable is the same as the [`--locale`](#--locale) option.
