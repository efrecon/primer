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

  [shellcheck]: https://www.shellcheck.net/
  [busybox]: https://busybox.net/

## Core Development

+ All exported functions should start with `primer_`
+ All internal functions should start with `_primer` (note the leading
  underscore).
+ Global variables that can be accessed from steps or internally in modules
  shoud start with `PRIMER_`.
+ Internal modules should only container lowercase letters or underscores, no
  leading underscore.
+ Given a module named xxx
  + Its implementation should be placed directly in the directory `libexec` and
    named with the same name, followed by `.sh`, e.g. `xxx.sh`.
  + All exported functions should start with `primer_xxx_`.
  + All internal functions should start with `_primer_xxx_` (note the leading
    underscore).
  + All exported variables should start with `PRIMER_XXX_`. The `XXX` is the
    same as the name of the module, though in uppercase.
  + There should be as little as exported variables as possible, preferably
    none.
