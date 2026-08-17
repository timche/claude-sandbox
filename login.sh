#!/bin/bash

# The logins that need a browser: GitHub and tailscale. Split out of setup.sh
# because both want a person at the keyboard, and kept a script of its own
# because it is what you rerun when one was skipped or has since expired.
#
# Neither is fatal. By the time this runs the machine is built; what is missing
# is an account on it, and that can be sorted out later.
#
# Safe to re-run: a login already in place is left alone.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -t 0 ]; then
  echo "login.sh needs a terminal for the browser flows — run it directly." >&2
  exit 0
fi

# Whether the gh login happened here is what decides if install.sh has anything
# new to pick up at the end, so it has to be sampled before the attempt.
gh_was_authenticated=false
if gh auth status >/dev/null 2>&1; then
  gh_was_authenticated=true
fi

# GitHub

if [ "$gh_was_authenticated" = true ]; then
  echo "gh is already authenticated"
else
  cat <<'EOF'

Logging in to GitHub. There is no browser on this box, so gh prints a code and
a URL to open on whichever machine has one.

EOF

  # write:ssh_signing_key is not in the default set and the interactive flow
  # never offers it, so asking here is what saves a later 'gh auth refresh'
  # before register-signing-key.sh can do anything. https because that is how
  # this repo and its private half are cloned; asking also skips the prompt.
  gh auth login --hostname github.com --git-protocol https --web \
    --scopes write:ssh_signing_key ||
    echo "gh login did not finish — rerun $repo/login.sh to try again" >&2
fi

# tailscale

if [ ! -d /run/systemd/system ]; then
  echo "no init to run tailscaled under — skipping tailscale"
elif tailscale status >/dev/null 2>&1; then
  echo "tailscale is already up"
else
  cat <<'EOF'

Bringing tailscale up. Same again: it prints a URL to authenticate the machine
with.

EOF

  sudo tailscale up ||
    echo "tailscale up did not finish — rerun $repo/login.sh to try again" >&2
fi

# install.sh skipped its gh-authenticated half on the way here — the gh-stack
# extension, the signing key, the private dotfiles. It is idempotent, and this
# is the pass that picks them up. Only worth it if this run is what logged in;
# otherwise the earlier pass already had everything it needed.
if [ "$gh_was_authenticated" = false ] && gh auth status >/dev/null 2>&1; then
  echo
  echo "gh is logged in now — rerunning install.sh for the parts that needed it."
  echo

  "$repo/install.sh"
fi
