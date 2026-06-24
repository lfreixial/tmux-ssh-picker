#!/usr/bin/env sh

set -eu

plugin_dir="$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)"

: "${SSH_PICKER_TEST_MODE:=0}"

trap 'exit 0' INT TERM HUP

tmux_option() {
  option="$1"
  default="$2"

  if [ "$SSH_PICKER_TEST_MODE" = 1 ]; then
    env_name="$(printf '%s' "$option" | sed 's/^@//' | tr '[:lower:]-' '[:upper:]_')"
    eval "value=\${$env_name:-}"
  else
    value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
  fi

  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

expand_path() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#"~/"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

option_enabled() {
  case "$1" in
    on|yes|true|1) return 0 ;;
    *) return 1 ;;
  esac
}

show_error() {
  if [ "$SSH_PICKER_TEST_MODE" = 1 ] || ! command -v tmux >/dev/null 2>&1; then
    printf 'tmux-ssh-picker: %s\n' "$1" >&2
  else
    tmux display-message "tmux-ssh-picker: $1"
  fi
}

safe_dirname() {
  dirname -- "$1"
}

config_seen() {
  file="$1"
  seen=" ${SSH_PICKER_SEEN_CONFIGS:-} "
  case "$seen" in
    *" $file "*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_include_pattern() {
  pattern="$1"
  base_dir="$2"

  # shellcheck disable=SC2088
  case "$pattern" in
    "~"|"~/"*) pattern="$(expand_path "$pattern")" ;;
    /*) ;;
    *) pattern="$base_dir/$pattern" ;;
  esac

  # shellcheck disable=SC2086
  for file in $pattern; do
    [ -r "$file" ] && printf '%s\n' "$file"
  done
}

extract_ssh_config_file() {
  config_file="$1"
  expanded_file="$(expand_path "$config_file")"
  [ -r "$expanded_file" ] || return 0

  if config_seen "$expanded_file"; then
    return 0
  fi

  SSH_PICKER_SEEN_CONFIGS="${SSH_PICKER_SEEN_CONFIGS:-} $expanded_file"
  export SSH_PICKER_SEEN_CONFIGS

  base_dir="$(safe_dirname "$expanded_file")"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|[[:space:]]|'#'*) continue ;;
    esac

    # shellcheck disable=SC2086
    set -- $line
    key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

    if [ "$key" = include ]; then
      shift
      for include_pattern in "$@"; do
        resolve_include_pattern "$include_pattern" "$base_dir" | while IFS= read -r include_file; do
          extract_ssh_config_file "$include_file"
        done
      done
    fi
  done < "$expanded_file"

  awk '
    function emit_host(alias) {
      target = hostname
      if (target == "") target = alias
      if (user != "") target = user "@" target

      details = ""
      if (hostname != "") details = details "HostName=" hostname " "
      if (user != "") details = details "User=" user " "
      if (port != "") details = details "Port=" port " "
      if (identity != "") details = details "IdentityFile=" identity " "
      if (proxyjump != "") details = details "ProxyJump=" proxyjump " "

      print alias "\t" target "\t" details
    }

    function flush_hosts() {
      for (i = 1; i <= host_count; i++) emit_host(hosts[i])
    }

    /^[[:space:]]*($|#)/ { next }
    {
      key = tolower($1)

      if (key == "host") {
        flush_hosts()
        delete hosts
        host_count = 0
        hostname = ""
        user = ""
        port = ""
        identity = ""
        proxyjump = ""

        for (i = 2; i <= NF; i++) {
          if ($i !~ /[*?!]/) hosts[++host_count] = $i
        }
      } else if (key == "include") {
        next
      } else if (host_count > 0) {
        value = $0
        sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", value)

        if (key == "hostname") hostname = value
        else if (key == "user") user = value
        else if (key == "port") port = value
        else if (key == "identityfile") identity = value
        else if (key == "proxyjump") proxyjump = value
      }
    }

    END { flush_hosts() }
  ' "$expanded_file"
}

extract_ssh_config_hosts() {
  config_files="$(tmux_option @ssh-picker-config-files "$HOME/.ssh/config")"
  SSH_PICKER_SEEN_CONFIGS=""
  export SSH_PICKER_SEEN_CONFIGS

  for config_file in $config_files; do
    extract_ssh_config_file "$config_file"
  done
}

extract_extra_hosts() {
  extra_hosts_file="$(tmux_option @ssh-picker-extra-hosts '')"
  [ -n "$extra_hosts_file" ] || return 0

  expanded_file="$(expand_path "$extra_hosts_file")"
  [ -r "$expanded_file" ] || return 0

  awk '
    /^[[:space:]]*($|#)/ { next }
    {
      host = $1
      $1 = ""
      sub(/^[[:space:]]+/, "")
      details = $0
      print host "\t" host "\t" details
    }
  ' "$expanded_file"
}

extract_known_hosts() {
  include_known_hosts="$(tmux_option @ssh-picker-include-known-hosts on)"
  case "$include_known_hosts" in
    on|yes|true|1) ;;
    *) return 0 ;;
  esac

  known_hosts_files="$(tmux_option @ssh-picker-known-hosts "$HOME/.ssh/known_hosts")"

  for known_hosts_file in $known_hosts_files; do
    expanded_file="$(expand_path "$known_hosts_file")"
    [ -r "$expanded_file" ] || continue

    awk '
      /^[[:space:]]*($|#)/ { next }
      $1 ~ /^\|/ { next }
      {
        hosts = $1
        if (hosts ~ /^@/) hosts = $2
        n = split(hosts, names, ",")

        for (i = 1; i <= n; i++) {
          host = names[i]
          if (host == "" || host ~ /^\|/) continue
          if (host ~ /^\[/) {
            sub(/^\[/, "", host)
            sub(/\]:[0-9]+$/, "", host)
          }
          if (host ~ /[*?!]/) continue
          print host "\t" host "\tKnownHosts=" FILENAME
        }
      }
    ' "$expanded_file"
  done
}

list_hosts() {
  {
    extract_ssh_config_hosts
    extract_extra_hosts
    extract_known_hosts
  } | awk -F '\t' '!seen[$1]++ && $1 != ""'
}

default_ssh_config_file() {
  config_files="$(tmux_option @ssh-picker-config-files "$HOME/.ssh/config")"

  for config_file in $config_files; do
    expand_path "$config_file"
    return 0
  done

  printf '%s/.ssh/config\n' "$HOME"
}

host_exists_in_config() {
  host_alias="$1"
  config_file="$2"
  [ -r "$config_file" ] || return 1

  awk -v wanted="$host_alias" '
    /^[[:space:]]*($|#)/ { next }
    tolower($1) == "host" {
      for (i = 2; i <= NF; i++) {
        if ($i == wanted) found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$config_file"
}

prompt_out() {
  if [ "$SSH_PICKER_TEST_MODE" = 1 ]; then
    printf '%b' "$1" >&2
  else
    printf '%b' "$1" > /dev/tty
  fi
}

read_input() {
  if [ "$SSH_PICKER_TEST_MODE" = 1 ]; then
    IFS= read -r value || return 1
  else
    IFS= read -r value < /dev/tty || return 1
  fi

  printf '%s\n' "$value"
}

read_prompt() {
  prompt="$1"
  default="${2:-}"

  if [ -n "$default" ]; then
    prompt_out "$(printf '%s [%s]: ' "$prompt" "$default")"
  else
    prompt_out "$(printf '%s: ' "$prompt")"
  fi

  value="$(read_input)" || return 1
  if [ -z "$value" ]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$value"
  fi
}

derive_alias() {
  hostname="$1"
  printf '%s\n' "$hostname" | sed 's/@.*//; s/[^A-Za-z0-9_.@%+:-]/-/g'
}

validate_token() {
  label="$1"
  value="$2"
  allowed_message="$3"

  case "$value" in
    *[!A-Za-z0-9_.@%+:-]*|*'*'*|*'?'*|*'!'*)
      show_error "$label can only contain $allowed_message"
      return 1
      ;;
  esac
}

append_ssh_config_host() {
  host_alias="$1"
  hostname="$2"
  user="$3"
  port="$4"
  identity_file="$5"
  proxy_jump="$6"
  config_file="$(default_ssh_config_file)"
  config_dir="$(safe_dirname "$config_file")"

  mkdir -p "$config_dir"
  chmod 700 "$config_dir" 2>/dev/null || true

  if host_exists_in_config "$host_alias" "$config_file"; then
    show_error "Host '$host_alias' already exists in $config_file"
    return 1
  fi

  umask 077
  {
    printf '\nHost %s\n' "$host_alias"
    printf '  HostName %s\n' "$hostname"
    [ -n "$user" ] && printf '  User %s\n' "$user"
    [ -n "$port" ] && printf '  Port %s\n' "$port"
    [ -n "$identity_file" ] && printf '  IdentityFile %s\n' "$identity_file"
    [ -n "$proxy_jump" ] && printf '  ProxyJump %s\n' "$proxy_jump"
  } >> "$config_file"

  chmod 600 "$config_file" 2>/dev/null || true
  show_error "saved '$host_alias' to $config_file"
}

new_connection() {
  if [ "$SSH_PICKER_TEST_MODE" != 1 ]; then
    printf '\033[2J\033[H' > /dev/tty
  fi
  prompt_out 'New SSH connection\n\n'

  hostname="$(read_prompt 'HostName')" || exit 0
  [ -n "$hostname" ] || exit 0
  validate_token HostName "$hostname" 'letters, numbers, dots, dashes, underscores, @, %, +, and :' || exit 1

  default_alias="$(derive_alias "$hostname")"
  host_alias="$(read_prompt 'Alias' "$default_alias")" || exit 0
  [ -n "$host_alias" ] || exit 0
  validate_token Alias "$host_alias" 'letters, numbers, dots, dashes, underscores, @, %, +, and :' || exit 1

  user="$(read_prompt 'User (optional)')" || exit 0
  [ -z "$user" ] || validate_token User "$user" 'letters, numbers, dots, dashes, underscores, @, %, +, and :' || exit 1

  port="$(read_prompt 'Port (optional)')" || exit 0
  case "$port" in
    ''|*[!0-9]*)
      if [ -n "$port" ]; then
        show_error "port must be numeric"
        exit 1
      fi
      ;;
  esac

  identity_file="$(read_prompt 'IdentityFile (optional)')" || exit 0
  proxy_jump="$(read_prompt 'ProxyJump (optional)')" || exit 0

  config_file="$(default_ssh_config_file)"
  prompt_out "$(printf '\nSave this entry to %s? [Y/n]: ' "$config_file")"
  confirm="$(read_input)" || exit 0
  case "$confirm" in
    n|N|no|NO|No) exit 0 ;;
  esac

  append_ssh_config_host "$host_alias" "$hostname" "$user" "$port" "$identity_file" "$proxy_jump" || exit 1

  prompt_out 'Connect now? [Y/n]: '
  connect_now="$(read_input)" || exit 0
  case "$connect_now" in
    n|N|no|NO|No) exit 0 ;;
  esac

  run_connection "$host_alias"
}

run_connection() {
  host="$1"
  action="${2:-$(tmux_option @ssh-picker-action new-window)}"
  ssh_command="$(tmux_option @ssh-picker-command ssh)"
  rename_window="$(tmux_option @ssh-picker-rename-window on)"
  target_pane="${SSH_PICKER_TARGET_PANE:-}"
  quoted_host="$(shell_quote "$host")"
  command="$ssh_command $quoted_host"

  window_name=""
  if option_enabled "$rename_window"; then
    window_name="${ssh_command%% *} | $host"
  fi

  if [ "$SSH_PICKER_TEST_MODE" = 1 ]; then
    printf '%s %s\n' "$action" "$command"
    [ -z "$window_name" ] || printf 'window-name: %s\n' "$window_name"
    return 0
  fi

  case "$action" in
    current)
      pane="${target_pane:-$(tmux display-message -p '#{pane_id}')}"
      tmux send-keys -t "$pane" "$command" C-m
      ;;
    new-window)
      pane="$(tmux new-window -P -F '#{pane_id}' "$command")"
      ;;
    hsplit)
      if [ -n "$target_pane" ]; then
        pane="$(tmux split-window -t "$target_pane" -h -P -F '#{pane_id}' "$command")"
      else
        pane="$(tmux split-window -h -P -F '#{pane_id}' "$command")"
      fi
      ;;
    vsplit)
      if [ -n "$target_pane" ]; then
        pane="$(tmux split-window -t "$target_pane" -v -P -F '#{pane_id}' "$command")"
      else
        pane="$(tmux split-window -v -P -F '#{pane_id}' "$command")"
      fi
      ;;
    *)
      show_error "unknown @ssh-picker-action '$action'"
      exit 1
      ;;
  esac

  if [ -n "$window_name" ]; then
    window="$(tmux display-message -p -t "$pane" '#{window_id}')"
    tmux set-window-option -t "$window" automatic-rename off
    tmux rename-window -t "$window" "$window_name"
  fi
}

format_hosts_for_fzf() {
  awk -F '\t' '
    {
      rows[++count] = $0
      if (length($1) > alias_width) alias_width = length($1)
    }
    END {
      if (alias_width < 12) alias_width = 12
      if (alias_width > 32) alias_width = 32

      for (i = 1; i <= count; i++) {
        split(rows[i], fields, "\t")
        alias = fields[1]
        target = fields[2]
        details = fields[3]
        display_alias = alias
        if (length(display_alias) > alias_width) {
          display_alias = substr(display_alias, 1, alias_width - 1) "~"
        }
        display = sprintf("%-*s  %s", alias_width, display_alias, target)
        print alias "\t" target "\t" details "\t" display
      }
    }
  '
}

select_host() {
  if ! command -v fzf >/dev/null 2>&1; then
    show_error "fzf is required"
    exit 1
  fi

  hosts_file="${TMPDIR:-/tmp}/tmux-ssh-picker-hosts.$$"
  trap 'rm -f "$hosts_file"' EXIT INT TERM

  list_hosts | format_hosts_for_fzf > "$hosts_file"

  header='enter: default | C-w: window | C-s: hsplit | C-v: vsplit | C-x: here | C-n: new'
  if [ ! -s "$hosts_file" ]; then
    header="no hosts found -- press ctrl-n to add one"
  fi

  output="$(
    fzf \
      --prompt='ssh> ' \
      --header="$header" \
      --height=100% \
      --layout=reverse \
      --border \
      --delimiter="$(printf '\t')" \
      --with-nth=4 \
      --expect=ctrl-w,ctrl-s,ctrl-v,ctrl-x \
      --bind="ctrl-n:become(sh $(shell_quote "$plugin_dir/scripts/ssh-picker.sh") new)" \
      --preview='printf "%s\n\n%s\n\n%s\n" {1} {2} {3}' \
      --preview-window='right:50%:wrap' \
      < "$hosts_file"
  )" || exit 0

  # With --expect, the first line is the key pressed (empty for plain enter),
  # the second line is the selected row.
  key="$(printf '%s\n' "$output" | sed -n '1p')"
  selected="$(printf '%s\n' "$output" | sed -n '2p')"

  host="$(printf '%s\n' "$selected" | awk -F '\t' '{ print $1 }')"
  [ -n "$host" ] || exit 0

  case "$key" in
    ctrl-w) action=new-window ;;
    ctrl-s) action=hsplit ;;
    ctrl-v) action=vsplit ;;
    ctrl-x) action=current ;;
    *) action="" ;;
  esac

  run_connection "$host" "$action"
}

open_popup() {
  width="$(tmux_option @ssh-picker-popup-width '80%')"
  height="$(tmux_option @ssh-picker-popup-height '70%')"
  target_pane="$(tmux display-message -p '#{pane_id}')"

  if ! command -v fzf >/dev/null 2>&1; then
    show_error "fzf is required"
    exit 1
  fi

  tmux display-popup \
    -E \
    -w "$width" \
    -h "$height" \
    -T " SSH Picker " \
    "SSH_PICKER_TARGET_PANE=$(shell_quote "$target_pane") sh $(shell_quote "$plugin_dir/scripts/ssh-picker.sh") select" || exit 0
}

case "${1:-popup}" in
  popup) open_popup ;;
  select) select_host ;;
  new) new_connection ;;
  connect) shift; [ "$#" -ge 1 ] || { show_error "connect requires a host"; exit 1; }; run_connection "$1" "${2:-}" ;;
  list) list_hosts ;;
  format) format_hosts_for_fzf ;;
  *) show_error "unknown command '$1'"; exit 1 ;;
esac
