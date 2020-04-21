# primer

Primer is a flexible POSIX shell OS initialisation automator. More help will
come once ready for some more prime-time.

## Testing

Primer comes with a test suite, based on [shellspec]. Provided you have
installed [shellspec] and it is in your path, run the following command from the
main directory of the project to run the test suite. The test suite requires
that you have [docker] installed on your machine and that your user is able to
call the `docker` client without elevated privileges. Running inside [docker]
allows to perform OS-wide modifications in the context of containers so as to
not pollute your main system.

```shell
shellspec
```

  [shellspec]: https://shellspec.info/
  [docker]: https://docker.com/