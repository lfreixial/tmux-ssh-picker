# Contributing

Run the local checks before opening a pull request:

```sh
sh -n scripts/*.sh tests/*.sh
tests/test.sh
```

If `shellcheck` is installed, also run:

```sh
shellcheck scripts/*.sh tests/*.sh
```
