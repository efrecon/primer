# users

`users` creates/removes users and associate them to groups.

## Description

The `users` step will create/remove users on the system using a DB file with a
format directly inspired from the `/etc/passwd` file. All necessary groups
pointed at by the specification of users will be created and users made members
of the relevant groups. The `users` step is able to create strong passwords for
the users, and to store those passwords in a read-only, protected for access
file aside the original users specification file. This file is meant to be
shredded once users have accessed the system and changed their passwords. This
step will not change the password of existing users that are also present in the
specification file.

In the specification file, lines starting with a hash mark `#` and empty lines
are ignored. Otherwise, each line should contain a number of fields separated by
the `:` (colon) sign. These fields are, in order:

- Name of the user to create
- Password to use. When the letter `x` a password will be generated at user
  creation and printed in the log.There is no other way to get hold of the
  password.
- Comma separated list of groups that the user should belong to. The first group
  is the main group
- [GECOS] fields (comma separated) for user
- Login shell, ensure that the shell exists on the machine, empty for a good
  default, i.e. the default shell on that distribution.

  [GECOS]: https://en.wikipedia.org/wiki/Gecos_field

## Options

### `--db`

Specifies the path to the user specification file.

### `--save`

The value of this option should be a boolean (`yes`/`no`, `true`/`false`,
`on`/`off`, an integer). When it is true, the a companion file will be created
in the same directory and with the same basename than the specification file,
albeit with the `.pwd` [extension](#--extension). The file will automatically be
only readable by the script caller and protected for access from other users on
the system. By default, no such file will be created, meaning that the only
place to get hold of the generated passwords is from the log of `primer` when
users are created.

### `--ext`

Extension to use for the companion file containing the generated passwords.

## Environment Variables

### `PRIMER_STEP_USERS_DB`

This environment variable is the same as the [`--db`](#--db) option.

### `PRIMER_STEP_USERS_GROUPS`

This environment variable contains a comma-separated list of groups that all
users created by this step should also become a member of. The groups are
created if they do not exist.

### `PRIMER_STEP_USERS_PWSAVE`

This environment variable is the same as the [`--save`](#--save) option.

### `PRIMER_STEP_USERS_PWEXT`

This environment variable is the same as the [`--ext`](#--ext) option.

### `PRIMER_STEP_USERS_PWLEN`

This environment variable contains the length of the generated strong passwords,
it defaults to `12`.
