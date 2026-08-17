#!/bin/bash

# Install the two SSH keys that cannot live in the repo: the commit-signing key
# and the authorized_keys for the devices you connect from.
#
# The signing key is generated here rather than carried in from somewhere else,
# so the private half never leaves this machine. The allowed_signers git
# verifies against is written here too, for the same reason: every machine has
# a different key, so a copy tracked in the repo would be a trust list none of
# them agrees with.
#
# What is left over is the half only you can do — registering the public key
# with GitHub. It is printed at the end.
#
# Safe to re-run: existing keys are left alone unless you say otherwise.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
signing_key="$HOME/.ssh/git-signing"
authorized_keys="$HOME/.ssh/authorized_keys"
allowed_signers="$HOME/.ssh/allowed_signers"

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

# Signing key

signer_identity() {
  # The principal has to be the address the commits are authored under, or the
  # signature verifies against nothing.
  git config --get user.email || echo "$(id -un)@$(hostname)"
}

# The trust list is a plain file here, not the symlink into the repo earlier
# versions installed — writing through that link would put a key that exists on
# one machine into content shared by all of them.
unlink_tracked_allowed_signers() {
  if [ -L "$allowed_signers" ]; then
    rm -f "$allowed_signers"
    echo "unlinked $allowed_signers from the copy in the repo"
  fi
}

# Drops the line for a key that is about to be replaced, so the trust list does
# not collect keys this machine no longer holds.
forget_signer() {
  local key="$1"

  [ -f "$allowed_signers" ] || return 0

  local kept
  kept="$(mktemp)"
  grep -vF "$key" "$allowed_signers" >"$kept" || true
  mv "$kept" "$allowed_signers"
  chmod 644 "$allowed_signers"
}

trust_signer() {
  [ -f "$signing_key.pub" ] || return 0

  local line
  line="$(signer_identity) $(awk '{print $1" "$2}' "$signing_key.pub")"

  if [ -f "$allowed_signers" ] && grep -qxF "$line" "$allowed_signers"; then
    return 0
  fi

  printf '%s\n' "$line" >>"$allowed_signers"
  chmod 644 "$allowed_signers"

  echo "trusted the signing key in $allowed_signers"
}

generate_signing_key() {
  unlink_tracked_allowed_signers

  if [ -f "$signing_key" ] && ! confirm "$signing_key already exists. Replace it?"; then
    echo "keeping the existing signing key"
    trust_signer
    return
  fi

  if [ -f "$signing_key.pub" ]; then
    forget_signer "$(awk '{print $1" "$2}' "$signing_key.pub")"
  fi

  # ssh-keygen prompts before overwriting, and there is nothing to prompt about
  # once the question above has been answered.
  rm -f "$signing_key" "$signing_key.pub"

  ssh-keygen -q -t ed25519 -N '' -C "$(signer_identity)" -f "$signing_key"
  chmod 600 "$signing_key"
  chmod 644 "$signing_key.pub"

  echo "generated $signing_key"

  trust_signer
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

# A failure here should not throw away the rest of the run, so it is carried to
# the exit status instead of aborting.
signing_failed=0
generate_signing_key || signing_failed=1

install_authorized_keys

if [ "$signing_failed" -ne 0 ]; then
  echo
  echo "The signing key was not generated. Re-run to try again." >&2
  exit 1
fi

if [ -f "$signing_key.pub" ]; then
  cat <<EOF

The signing key, public half:

$(sed 's/^/    /' "$signing_key.pub")

This machine already trusts it. GitHub is the other half — registered here when
gh is logged in, and by install.sh once it is:
EOF

  # Generating a key here after install.sh has already run means install.sh
  # registered the key this one replaces, so the attempt belongs on both paths.
  "$repo/register-signing-key.sh" "$signing_key.pub"

  cat <<'EOF'

Locally, check signing works with:

    git commit --allow-empty -m test && git log --format='%G?' -1
EOF
fi
