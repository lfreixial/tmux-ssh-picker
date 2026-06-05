#!/usr/bin/env sh

set -eu

ROOT_DIR="$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/ssh-picker.sh"
TMP_DIR="${TMPDIR:-/tmp}/tmux-ssh-picker-tests.$$"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP_DIR/home/.ssh" "$TMP_DIR/home/includes"

assert_eq() {
  expected="$1"
  actual="$2"
  label="$3"

  if [ "$expected" != "$actual" ]; then
    printf 'not ok - %s\n' "$label" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$label"
}

cat > "$TMP_DIR/home/.ssh/config" <<'CONFIG'
Include ~/includes/work.conf

Host *
  User ignored

Host pi
  HostName 203.0.113.10
  User pi

Host prod-api prod-db
  HostName 203.0.113.20
  User ubuntu
  Port 2222
  IdentityFile ~/.ssh/prod.pem
  ProxyJump bastion
CONFIG

cat > "$TMP_DIR/home/includes/work.conf" <<'CONFIG'
Host work-box
  HostName work.example.com
  User deploy
CONFIG

cat > "$TMP_DIR/home/.ssh/known_hosts" <<'KNOWN'
plain.example.com ssh-ed25519 AAAATEST
[port.example.com]:2222 ssh-rsa AAAATEST
|1|hashed|entry ssh-ed25519 AAAATEST
KNOWN

actual="$(env SSH_PICKER_TEST_MODE=1 HOME="$TMP_DIR/home" SSH_PICKER_CONFIG_FILES=~/.ssh/config SSH_PICKER_KNOWN_HOSTS=~/.ssh/known_hosts sh "$SCRIPT" list)"
expected="$(cat <<'EXPECTED'
work-box	deploy@work.example.com	HostName=work.example.com User=deploy 
pi	pi@203.0.113.10	HostName=203.0.113.10 User=pi 
prod-api	ubuntu@203.0.113.20	HostName=203.0.113.20 User=ubuntu Port=2222 IdentityFile=~/.ssh/prod.pem ProxyJump=bastion 
prod-db	ubuntu@203.0.113.20	HostName=203.0.113.20 User=ubuntu Port=2222 IdentityFile=~/.ssh/prod.pem ProxyJump=bastion 
plain.example.com	plain.example.com	KnownHosts=__KNOWN_HOSTS__
port.example.com	port.example.com	KnownHosts=__KNOWN_HOSTS__
EXPECTED
)"
expected="$(printf '%s\n' "$expected" | sed "s#__KNOWN_HOSTS__#$TMP_DIR/home/.ssh/known_hosts#g")"
assert_eq "$expected" "$actual" "list hosts from config includes and known_hosts"

formatted="$(printf '%s\n' "$actual" | sh "$SCRIPT" format)"
case "$formatted" in
  *"prod-api           ubuntu@203.0.113.20"*) printf 'ok - formatted columns align\n' ;;
  *)
    printf 'not ok - formatted columns align\n%s\n' "$formatted" >&2
    exit 1
    ;;
esac

save_home="$TMP_DIR/save-home"
mkdir -p "$save_home/.ssh"
cat > "$TMP_DIR/new-input" <<'INPUT'
new.example.com
newbox
admin
2200
~/.ssh/new.pem
bastion
y
n
INPUT

env SSH_PICKER_TEST_MODE=1 HOME="$save_home" SSH_PICKER_CONFIG_FILES='~/.ssh/config' sh "$SCRIPT" new < "$TMP_DIR/new-input" > "$TMP_DIR/new-output" 2> "$TMP_DIR/new-error"

expected_config="$(cat <<'CONFIG'

Host newbox
  HostName new.example.com
  User admin
  Port 2200
  IdentityFile ~/.ssh/new.pem
  ProxyJump bastion
CONFIG
)"
actual_config="$(cat "$save_home/.ssh/config")"
assert_eq "$expected_config" "$actual_config" "new connection writes ssh config"

mode="$(stat -c '%a' "$save_home/.ssh/config" 2>/dev/null || stat -f '%Lp' "$save_home/.ssh/config")"
assert_eq "600" "$mode" "new ssh config mode is private"


if env SSH_PICKER_TEST_MODE=1 HOME="$save_home" SSH_PICKER_CONFIG_FILES='~/.ssh/config' sh "$SCRIPT" new < /dev/null > "$TMP_DIR/cancel-output" 2> "$TMP_DIR/cancel-error"; then
  printf 'ok - cancelled new connection exits cleanly\n'
else
  printf 'not ok - cancelled new connection exits cleanly\n' >&2
  cat "$TMP_DIR/cancel-error" >&2
  exit 1
fi

printf 'all tests passed\n'
