#!/bin/bash

# The logins that need a browser: GitHub, tailscale and Claude Code. Split out
# of setup.sh because each wants a person at the keyboard, and kept a script of
# its own because it is what you rerun when one was skipped or has since
# expired.
#
# None of them is fatal. By the time this runs the machine is built; what is
# missing is an account on it, and that can be sorted out later.
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

# --ssh has tailscaled answer SSH on the tailnet itself. That is a second way
# in, one that survives losing the key sshd wants or the provider's firewall
# closing over port 22 — and it is why harden-ssh.sh can be as strict as it is.
#
# Advertising is all this does. Nothing connects until the tailnet policy has
# an ssh rule for the machine, which is a console job; and that policy, not
# 10-hardening.conf, is what governs the tailscale path, since sshd never sees
# it. setup.sh says so at the end of the run.
if [ ! -d /run/systemd/system ]; then
  echo "no init to run tailscaled under — skipping tailscale"
elif tailscale status >/dev/null 2>&1; then
  echo "tailscale is already up"

  # It may well be up from before this script advertised SSH. set is how you
  # turn it on afterwards without taking the machine off the tailnet first.
  sudo tailscale set --ssh ||
    echo "could not advertise ssh — run 'sudo tailscale set --ssh'" >&2
else
  cat <<'EOF'

Bringing tailscale up, advertising SSH. Same again: it prints a URL to
authenticate the machine with.

EOF

  sudo tailscale up --ssh ||
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

# Claude Code

# Last, because claude arrives with the dotfiles the rerun above fetches, and it
# lands in ~/.local/bin, which this shell has no reason to have on PATH.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v claude >/dev/null 2>&1; then
  echo "claude is not installed, so it was not logged in — it comes with the" >&2
  echo "dotfiles, so sort those out and rerun $repo/login.sh" >&2
elif claude auth status >/dev/null 2>&1; then
  echo "claude is already authenticated"
else
  cat <<'EOF'

Logging in to Claude Code. Same as the others: a URL to open on whichever
machine has a browser.

EOF

  claude auth login ||
    echo "claude login did not finish — rerun $repo/login.sh to try again" >&2
fi
