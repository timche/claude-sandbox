#!/bin/bash

# Install the sshd hardening drop-in, naming one user in AllowUsers. Kept out
# of bootstrap-system.sh and run last, because it is the step that turns
# password logins off: hardening before there is an authorized_keys to log in
# with leaves a box only reachable from the provider's console.
#
# So it refuses when the user has no keys. FORCE_HARDEN=true overrides that,
# for the case where you are certain of another way in.
#
# Safe to re-run, and takes the user to allow as its argument, defaulting to
# whoever runs it.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user="${1:-$USER}"
drop_in=/etc/ssh/sshd_config.d/10-hardening.conf

home="$(getent passwd "$user" | cut -d: -f6)"
if [ -z "$home" ]; then
  echo "no such user: $user" >&2
  exit 1
fi

if [ ! -s "$home/.ssh/authorized_keys" ] && [ "${FORCE_HARDEN:-false}" != true ]; then
  echo
  echo "Skipped ssh hardening: $user has no authorized_keys, so disabling" >&2
  echo "password logins now would lock you out. Install a key, then run" >&2
  echo "  $repo/harden-ssh.sh $user" >&2
  exit 0
fi

if [ ! -s "$home/.ssh/authorized_keys" ]; then
  echo "warning: hardening with no key installed (FORCE_HARDEN=true)." >&2
fi

staged="$(mktemp)"
sed "s/__USER__/$user/" "$repo/system/ssh/10-hardening.conf" >"$staged"

sudo install -d -m 0755 /etc/ssh/sshd_config.d
sudo install -m 0644 "$staged" "$drop_in"
rm -f "$staged"

# sshd -t refuses to get as far as the config when its privilege separation
# directory is missing, which it is anywhere sshd has not run yet. Creating it
# is what the package does; here it keeps a missing runtime directory from
# reading as a broken config.
sudo install -d -m 0755 /run/sshd

# A drop-in sshd will not parse is worse than none at all, so take it back out
# rather than leave it for the next restart to trip over.
if ! sudo /usr/sbin/sshd -t; then
  sudo rm -f "$drop_in"
  echo "sshd rejected the drop-in; removed it and left the running config alone" >&2
  exit 1
fi

# Skipped inside containers, where there is no init to talk to.
if [ -d /run/systemd/system ]; then
  # On trixie ssh.socket can hold port 22, and then restarting ssh.service
  # fails with "Cannot bind any address".
  if systemctl is-active --quiet ssh.socket; then
    sudo systemctl restart ssh.socket
  else
    sudo systemctl restart ssh.service
  fi
fi

echo "ssh hardened: keys only, no root, AllowUsers $user"
