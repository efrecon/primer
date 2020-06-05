# forever

`forever` loops forever doing nothing on installation.

## Description

The `forever` step will loop forever during installation, doing nothing else.
This step is mostly meant to be used from within the test suit or for CLI
testing and experimentation.

## Options

### `--sleep`

Specifies the number of seconds to sleep at each loop.

## Environment Variables

### `PRIMER_STEP_FOREVER_SLEEP`

This environment variable is the same as the [`--sleep`](#--sleep) option.
