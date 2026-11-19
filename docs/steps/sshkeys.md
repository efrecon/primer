# sshkeys

`sshkeys` creates/removes password-less ssh keys in the account of the caller.

## Description

The `sshkeys` step will create/remove SSH keys in the account of the caller
using `ssh-keygen`. These keys are password-less as `primer` is meant to be run
from (semi-)automated setups. These keys are can be used for accessing remote
code repositories. The default is to create the most secure keys, as known at
the time of writing.

The `ssh-keygen` program is installed when missing, from the package providing
it on the distribution (e.g. `openssh-client` on Debian derivatives,
`openssh-keygen` on Alpine). On generation, the keys are created in the `.ssh`
subdirectory of the home directory, which is created when missing, and will be
named with `id_` followed by the type of the key, i.e. as of the current default
for the `ssh-keygen` program. Existing keys are kept.

Generated keys have a comment ending with `(primer)`. When cleaning, only keys
carrying this marker are removed: keys that existed before, or were created by
other means, are kept.

## Options

### `--type`

Specify the type of SSH keys to generate. The default is to generate
[`ed25519`][ed25519] keys. Other possible types depend slightly on the OpenSSH
installation. Other common types are `ecdsa` or `rsa` (`dsa` is no longer
supported by recent OpenSSH versions).

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
