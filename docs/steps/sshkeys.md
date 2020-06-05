# sshkeys

`sshkeys` creates/removes password-less ssh keys in the account of the caller.

## Description

The `sshkeys` step will create/remove SSH keys in the account of the caller
using `ssh-keygen`. These keys are password-less as `primer` is meant to be run
from (semi-)automated setups. These keys are can be used for accessing remote
code repositories. The default is to create the most secure keys, as known at
the time of writing.

On generation, the keys are created in the `.ssh` subdirectory of the home
directory and will be named with `id_` followed by the type of the key, i.e. as
of the current default for the `ssh-keygen` program.

## Options

### `--type`

Specify the type of SSH keys to generate. The default is to generate
[`ed25519`][ed25519] keys. Other possible types depend slightly on the OpenSSH
installation. Common older types are: `dsa`, `ecdsa` or `rsa`

  [ed25519]: https://en.wikipedia.org/wiki/EdDSA#Ed25519

## Environment Variables

### `PRIMER_STEP_SSHKEYS_TYPE`

This environment variable is the same as the [`--type`](#--type) option.

### `PRIMER_STEP_SSHKEYS_RSA_LEN`

This environment variable is the length in bits when generated `rsa` keys. It
defaults to `4096`.

### `PRIMER_STEP_SSHKEYS_ECDSA_LEN`

This environment variable is the length in bits when generated `ecdsa` keys. It
defaults to `521` (yes, not 512!).
