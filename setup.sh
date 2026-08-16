#!/bin/bash

# Set up a VM from scratch. See README.md for the steps that stay manual.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$repo/bootstrap-system.sh"
"$repo/install.sh"

# Prompts for a paste, so there has to be a terminal to prompt at.
if [ -t 0 ]; then
  "$repo/keys.sh"
else
  echo
  echo "Skipped keys.sh — no terminal. Run $repo/keys.sh to install the SSH keys."
fi

echo
echo "Done. What is left needs a browser or a login:"
echo

# This repo clones without authentication, so gh usually is not logged in yet —
# but it will be if you came back here after fetching claude-dotfiles.
if ! gh auth status >/dev/null 2>&1; then
  echo "  - gh auth login, then rerun install.sh so it can add the gh-stack extension."
fi

cat <<'EOF'
  - sudo tailscale up
  - claude, then /login
  - Log out and back in so the docker group and the zsh login shell take hold.
EOF
