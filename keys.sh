#!/bin/bash

# Install the two SSH keys that cannot live in the repo: the commit-signing key
# and the authorized_keys for the devices you connect from. Both are pasted in.
#
# Only the private signing key is asked for — its public half is derived, and
# checked against the allowed_signers this repo already tracks, so pasting the
# wrong key is caught here rather than showing up later as commits that will
# not verify.
#
# Safe to re-run: existing keys are left alone unless you say otherwise.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
signing_key="$HOME/.ssh/git-signing"
authorized_keys="$HOME/.ssh/authorized_keys"
allowed_signers="$repo/home/.ssh/allowed_signers"

if [ ! -t 0 ]; then
  echo "keys.sh needs a terminal to prompt for a paste — run it directly." >&2
  exit 0
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

confirm() {
  local answer
  read -r -p "$1 [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ]
}

# Reads pasted lines until the private key's END marker, or until EOF (ctrl-D).
read_private_key() {
  local line block=""

  while IFS= read -r line; do
    block+="$line"$'\n'
    if [[ "$line" == *END*"PRIVATE KEY"* ]]; then
      break
    fi
  done

  printf '%s' "$block"
}

# Signing key

install_signing_key() {
  if [ -f "$signing_key" ] && ! confirm "$signing_key already exists. Replace it?"; then
    echo "keeping the existing signing key"
    return
  fi

  echo
  echo "Paste the private signing key, including the BEGIN and END lines."
  echo "It ends by itself at the END line; ctrl-D also works."
  echo

  local pasted
  pasted="$(read_private_key)"

  if [ -z "${pasted//[[:space:]]/}" ]; then
    echo "nothing pasted — skipping the signing key" >&2
    return
  fi

  local staged
  staged="$(mktemp)"
  chmod 600 "$staged"
  # Command substitution above ate the trailing newline, and an OpenSSH private
  # key is rejected without one.
  printf '%s\n' "$pasted" >"$staged"

  # Deriving the public half doubles as validation: a truncated or mangled
  # paste fails here, before anything lands in ~/.ssh.
  local derived
  if ! derived="$(ssh-keygen -y -f "$staged" 2>&1)"; then
    rm -f "$staged"
    echo "that is not a usable private key:" >&2
    echo "  $derived" >&2
    return 1
  fi

  local derived_key expected_key
  derived_key="$(printf '%s' "$derived" | awk '{print $1" "$2}')"
  expected_key="$(awk 'NR==1 {print $2" "$3}' "$allowed_signers")"

  if [ "$derived_key" != "$expected_key" ]; then
    echo
    echo "warning: this key does not match allowed_signers in the repo." >&2
    echo "  pasted:   ${derived_key:0:44}..." >&2
    echo "  expected: ${expected_key:0:44}..." >&2
    echo "Commits signed with it will not verify." >&2

    if ! confirm "Install it anyway?"; then
      rm -f "$staged"
      echo "signing key not installed"
      return
    fi
  fi

  mv "$staged" "$signing_key"
  chmod 600 "$signing_key"
  printf '%s\n' "$derived" >"$signing_key.pub"
  chmod 644 "$signing_key.pub"

  echo "installed $signing_key and derived its .pub"
}

# authorized_keys

install_authorized_keys() {
  echo
  echo "Paste the public keys allowed to SSH in, one per line."
  echo "A blank line ends the list; ctrl-D also works."
  echo

  local line added=0

  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] || break

    if [ -f "$authorized_keys" ] && grep -qxF "$line" "$authorized_keys"; then
      echo "  already present, skipped"
      continue
    fi

    printf '%s\n' "$line" >>"$authorized_keys"
    added=$((added + 1))
  done

  touch "$authorized_keys"
  chmod 600 "$authorized_keys"

  if [ "$added" -gt 0 ]; then
    echo "added $added key(s) to $authorized_keys"
  else
    echo "no new keys added"
  fi
}

# A fumbled paste should not throw away the rest of the run, so the failure is
# carried to the exit status instead of aborting here.
signing_failed=0
install_signing_key || signing_failed=1

install_authorized_keys

if [ "$signing_failed" -ne 0 ]; then
  echo
  echo "The signing key was not installed. Re-run to try again." >&2
  exit 1
fi

echo
echo "Done. Check signing works with:"
echo "  git commit --allow-empty -m test && git log --format='%G?' -1"
