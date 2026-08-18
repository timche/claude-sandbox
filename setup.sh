#!/bin/bash

# The per-user half of the run: everything from a working account onwards. See
# README.md for the steps that stay manual.
#
# Not an entry point. provision.sh is, and it runs as root because a VM arrives
# with nothing else — it creates the account and calls this as it. Rerunning
# this by hand from the clone is fine and is how you pick up a change; running
# it as root is not, since every path here belongs to one user.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "setup.sh runs as the user it is setting up, not as root — everything" >&2
  echo "here lands in \$HOME. On a bare VM start with provision.sh instead," >&2
  echo "which creates the account and calls this from it." >&2
  exit 1
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$repo/bootstrap-system.sh"
"$repo/install.sh"

# Before keys.sh, because that reads user.email out of the .gitconfig only the
# dotfiles carry, and login.sh is what fetches them. Needs a terminal for the
# browser flow.
if [ -t 0 ]; then
  "$repo/login.sh"
else
  echo
  echo "Skipped login.sh — no terminal. Run $repo/login.sh to log in to GitHub"
  echo "and tailscale, and to fetch the dotfiles."
fi

keys_failed=0

# Prompts for a paste, so there has to be a terminal to prompt at.
if [ -t 0 ]; then
  "$repo/keys.sh" || keys_failed=1
else
  echo
  echo "Skipped keys.sh — no terminal. Run $repo/keys.sh to install the SSH keys."
fi

# Last, because it is the step that turns password logins off. It skips itself
# when there is no authorized_keys yet, rather than locking you out.
"$repo/harden-ssh.sh"

echo
echo "Done. What is left:"
echo

# Still not logged in means login.sh was skipped or did not finish, and with it
# the dotfiles and the Claude Code login: the account is still on bash with
# nothing but Debian's rc.
if ! gh auth status >/dev/null 2>&1; then
  echo "  - $repo/login.sh — GitHub, tailscale and Claude Code, and the rerun"
  echo "    that fetches the dotfiles in between."
elif ! tailscale status >/dev/null 2>&1; then
  echo "  - sudo tailscale up — $repo/login.sh tried and did not get there."
fi

cat <<'EOF'
  - Log out and back in so the docker group and the zsh login shell take hold.
EOF

exit "$keys_failed"
