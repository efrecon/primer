# Coding Conventions

This document provides some conventions to follow when coding the core of primer
or new installation steps:

## General Rules

+ Write in POSIX shell. It has its own and known limitations!
+ All code should pass the [shellcheck] linter. Exceptions are possible, but
  should be properly marked for linting exclusion using `# shellcheck disable=`,
  preferably with a description of the reason.
+ Make sure relevant global variables can be set from the environment and have
  good defaults.
+ Use as few dependencies as possible when calling external tools.
+ Do not expect GNU utilities installed, instead code for [busybox], alt. for
  both when the busybox implementation would be more complex or slower.
+ Document your code!
+ Write in British English: documentation, comments and messages, e.g.
  behaviour, colour, initialise, licence (the noun). Names from code, options,
  commands or external projects are kept as they are, e.g. `--color`.

  [shellcheck]: https://www.shellcheck.net/
  [busybox]: https://busybox.net/

## Core Development

+ All exported functions should start with `primer_`, contain only lowercase and
  underscores.
+ All internal functions should start with `_primer` (note the leading
  underscore), contain only lowercase and underscores.
+ Global variables that can be accessed from steps or internally in modules
  shoud start with `PRIMER_`, contain uppercase or underscores.
+ Internal modules should only container lowercase letters or underscores, no
  leading underscore.
+ No module should be called `step`.
+ Given a module named xxx
  + Its implementation should be placed directly in the directory `libexec` and
    named with the same name, followed by `.sh`, e.g. `xxx.sh`.
  + All exported functions should start with `primer_xxx_`.
  + All internal functions should start with `_primer_xxx_` (note the leading
    underscore).
  + All exported variables should start with `PRIMER_XXX_`. The `XXX` is the
    same as the name of the module, though in uppercase.
  + There should be as little exported variables as possible, preferably none.

## Developing Installation Steps

+ The name of a step can only contain lower case alphanumeric characters and
  underscores.
+ Given a step named xxx:
  + Its implementation should be named with the same name, followed by `.sh`,
    e.g. `xxx.sh`.
  + All exported functions should start with `primer_step_xxx_`.
  + All internal functions should start with `_primer_step_xxx_` (note the
    leading underscore).
  + All exported variables should start with `PRIMER_STEP_XXX_`. The `XXX` is
    the same as the name of the module, though in uppercase.
  + There should be as little exported variables as possible, preferably none.

## Tests

+ Tests live in `test/`, in files named `<name>.test.sh`. Each test is a
  function whose name starts with `test_`. `test/run.sh` discovers and runs
  them, see the [README](../README.md#testing).
+ Every function of a library module in `libexec/` has at least one unit test
  in `test/unit_<module>.test.sh`, named `test_<function>`, optionally followed
  by a suffix, e.g. `test_primer_os_packages_alpine`.
+ Every step has tests in `test/step_<step>.test.sh`.
+ Tests always run in containers, using the helpers from `test/lib.sh`:
  `in_container`, `primer_in` (the CLI) and `unit` (primer sourced in library
  mode). Images are fully qualified, e.g. `docker.io/library/alpine:3.24`, so
  they work with both docker and podman.
+ Assertions (`assert_equal`, `assert_match`, ...) run inside the containers.
  Replace external commands with `mock` (shell functions, or executables for
  names that are not valid function names) or `stub_bin` (executables, visible
  to child processes).
+ Tests that need privileged containers call `require_privileged` first, and
  `skip` explains why a test cannot run.
+ Snippets passed to the container helpers are single-quoted on purpose, as
  they expand inside the containers. Start test files with
  `# shellcheck disable=SC2016` to keep [shellcheck] quiet about this.
+ When a test exposes a bug, fix the code, not the test.

## Documentation

+ Keep Markdown lines at 80 characters at most: wrap paragraphs and list items,
  without splitting inline code or links across lines. Split long commands in
  code blocks with `\` continuations.
+ Only lines that cannot be wrapped may be longer: verbatim program output in
  code blocks, and link reference definitions whose URL alone is too long.
