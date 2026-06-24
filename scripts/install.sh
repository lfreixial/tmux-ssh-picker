#!/usr/bin/env sh

set -eu

socket_path="$1"
plugin_dir="$2"

tmuxc() {
  if [ -n "$socket_path" ]; then
    tmux -S "$socket_path" "$@"
  else
    tmux "$@"
  fi
}

tmux_get() {
  tmuxc show-option -gqv "$1" 2>/dev/null || true
}

tmux_set_default() {
  option="$1"
  default="$2"

  if [ -z "$(tmux_get "$option")" ]; then
    tmuxc set-option -gq "$option" "$default"
  fi
}

tmux_set_default @ssh-picker-key S
tmux_set_default @ssh-picker-popup-width '80%'
tmux_set_default @ssh-picker-popup-height '70%'
tmux_set_default @ssh-picker-action new-window
tmux_set_default @ssh-picker-rename-window on
tmux_set_default @ssh-picker-command ssh
tmux_set_default @ssh-picker-config-files "$HOME/.ssh/config"
tmux_set_default @ssh-picker-extra-hosts ''
tmux_set_default @ssh-picker-include-known-hosts on
tmux_set_default @ssh-picker-known-hosts "$HOME/.ssh/known_hosts"

key="$(tmux_get @ssh-picker-key)"
tmuxc bind-key "$key" run-shell -b "sh '$plugin_dir/scripts/ssh-picker.sh' popup"
