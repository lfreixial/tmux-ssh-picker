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

## Commit Messages

This repo uses Conventional Commits to create releases automatically when changes land on `main`.

Use these commit types for version bumps:

- `feat!: ...`, `fix!: ...`, or a commit body containing `BREAKING CHANGE:` creates a major release, for example `v2.0.0`.
- `feat: ...` creates a minor release, for example `v1.1.0`.
- `fix: ...`, `perf: ...`, `docs: ...`, `test: ...`, `ci: ...`, `build: ...`, `chore: ...`, `refactor: ...`, and `style: ...` create patch releases, for example `v1.0.1`.

Examples:

```text
fix: handle cancelled new connection prompts
feat: open ssh sessions in new tmux windows by default
feat!: rename ssh picker tmux options
```

Every merge to `main` should use one of the listed Conventional Commit types. Unknown commit types may not produce a release.

