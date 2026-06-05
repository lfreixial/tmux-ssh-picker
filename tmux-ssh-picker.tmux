#!/usr/bin/env bash

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set_default() {
  local option="$1"
  local default="$2"
  local value

  value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    tmux set-option -gq "$option" "$default"
  fi
}

set_default @ssh-picker-key S
set_default @ssh-picker-popup-width '80%'
set_default @ssh-picker-popup-height '70%'
set_default @ssh-picker-action new-window
set_default @ssh-picker-command ssh
set_default @ssh-picker-config-files "$HOME/.ssh/config"
set_default @ssh-picker-extra-hosts ''
set_default @ssh-picker-include-known-hosts on
set_default @ssh-picker-known-hosts "$HOME/.ssh/known_hosts"

key="$(tmux show-option -gqv @ssh-picker-key)"
tmux bind-key "$key" run-shell -b "sh '$CURRENT_DIR/scripts/ssh-picker.sh' popup"
