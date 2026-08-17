#!/bin/bash

# Install the two SSH keys that cannot live in the repo: the commit-signing key
# and the authorized_keys for the devices you connect from.
#
# The signing key is generated here rather than carried in from somewhere else,
# so the private half never leaves this machine. Its public half is printed at
# the end — that is the copy that has to be registered, with GitHub and with the
# allowed_signers this repo tracks, before commits signed here will verify.
#
# Safe to re-run: existing keys are left alone unless you say otherwise.

set -euo pipefail

signing_key="$HOME/.ssh/git-signing"
authorized_keys="$HOME/.ssh/authorized_keys"

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

generate_signing_key() {
  if [ -f "$signing_key" ] && ! confirm "$signing_key already exists. Replace it?"; then
    echo "keeping the existing signing key"
    return
  fi

  # ssh-keygen prompts before overwriting, and there is nothing to prompt about
  # once the question above has been answered.
  rm -f "$signing_key" "$signing_key.pub"

  # The comment is what allowed_signers matches a signature against, so it has
  # to be the same identity the commits are authored under.
  local comment
  comment="$(git config --get user.email || echo "$(id -un)@$(hostname)")"

  ssh-keygen -q -t ed25519 -N '' -C "$comment" -f "$signing_key"
  chmod 600 "$signing_key"
  chmod 644 "$signing_key.pub"

  echo "generated $signing_key"
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

Nothing verifies a signature from it until that line is registered in both
places:

  - gh ssh-key add $signing_key.pub --type signing
  - home/.ssh/allowed_signers in this repo, which \$HOME/.ssh/allowed_signers
    is a symlink to

Then check signing works with:

    git commit --allow-empty -m test && git log --format='%G?' -1
EOF
fi
