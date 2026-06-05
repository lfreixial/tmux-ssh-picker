# tmux-ssh-picker

A tmux plugin for quickly SSHing into saved SSH hosts with `fzf`.

Press a tmux key binding, pick a host, and the plugin starts SSH in a new tmux window by default.

```text
+--------------------------------------------------------------+
| SSH Picker                                                   |
|                                                              |
| ssh>                                                         |
| 3/3                                                          |
| enter: connect | ctrl-n: new saved connection                |
| > web-prod      deploy@web-prod.example.com                  |
|   db-staging    admin@db-staging.example.com                 |
|   jumpbox       ops@jumpbox.example.com                      |
+--------------------------------------------------------------+
```

## Requirements

- tmux 3.2 or newer for `display-popup`
- `fzf` 0.38 or newer (for the `become` binding used by `ctrl-n`)
- `ssh`

## Install

### TPM

After this repo is published on GitHub, add this to `.tmux.conf`:

```tmux
set -g @plugin 'lfreixial/tmux-ssh-picker'
```

Then press `prefix + I`.

### Manual

Clone the plugin:

```sh
git clone https://github.com/lfreixial/tmux-ssh-picker ~/.tmux/plugins/tmux-ssh-picker
```

Load it from `.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-ssh-picker/tmux-ssh-picker.tmux
```

Reload tmux:

```sh
tmux source-file ~/.tmux.conf
```

## Usage

Default binding:

```text
prefix + S
```

Inside the picker:

```text
enter   connect to the selected host
ctrl-n  add a new saved SSH connection
```

The host list comes from:

- `~/.ssh/config`
- optional extra host files
- unhashed `~/.ssh/known_hosts` entries

Shell history is not used.

When adding a new connection, the plugin prompts for `HostName`, `Alias`, `User`, `Port`, `IdentityFile`, and `ProxyJump`. It appends the entry to the first configured SSH config file, then asks whether to connect immediately.

Example generated SSH config:

```sshconfig
Host pi
  HostName 203.0.113.10
  User pi

Host prod-api
  HostName 203.0.113.12
  User ubuntu
  IdentityFile ~/.ssh/prod.pem
```

## Options

Change the key binding:

```tmux
set -g @ssh-picker-key s
```

Choose where SSH opens:

```tmux
set -g @ssh-picker-action new-window
```

Supported actions:

- `new-window`: open SSH in a new tmux window, the default
- `current`: send `ssh host` to the current pane
- `hsplit`: open SSH in a horizontal split
- `vsplit`: open SSH in a vertical split

Change popup size:

```tmux
set -g @ssh-picker-popup-width '80%'
set -g @ssh-picker-popup-height '70%'
```

Use a custom SSH command:

```tmux
set -g @ssh-picker-command 'ssh -A'
```

Read one or more SSH config files:

```tmux
set -g @ssh-picker-config-files '~/.ssh/config ~/.ssh/work_config'
```

Add extra hosts from a plain text file:

```tmux
set -g @ssh-picker-extra-hosts '~/.ssh/hosts'
```

Each non-empty, non-comment line should start with the host to connect to:

```text
prod-db-01 primary database
ubuntu@10.0.1.50 temporary host
```

Use or disable `known_hosts` discovery:

```tmux
set -g @ssh-picker-include-known-hosts on
set -g @ssh-picker-known-hosts '~/.ssh/known_hosts'
```

Hashed `known_hosts` entries cannot be shown because SSH intentionally hides the hostname.

## Releases

Releases are created automatically from Conventional Commits when changes are merged to `main`:

- `feat!:` or `BREAKING CHANGE:` creates a major release.
- `feat:` creates a minor release.
- `fix:`, `perf:`, `docs:`, `test:`, `ci:`, `build:`, `chore:`, `refactor:`, and `style:` create patch releases.

Every merge to `main` should use one of those Conventional Commit types so the release workflow can calculate the next version.

## Development

List discovered hosts without opening `fzf`:

```sh
scripts/ssh-picker.sh list
```

Format hosts as they appear in `fzf`:

```sh
scripts/ssh-picker.sh list | scripts/ssh-picker.sh format
```

Run tests:

```sh
tests/test.sh
```

Run syntax checks:

```sh
sh -n scripts/*.sh tests/*.sh
```
