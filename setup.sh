#!/bin/bash

# Set up a VM from scratch. See README.md for the steps that stay manual.
#
# Works two ways: run from a clone, or piped straight from the web, in which
# case it clones the repo first and hands over to the copy inside it. The clone
# is not a convenience — install.sh symlinks the dotfiles out of it, so the
# repo has to stay on disk.

set -euo pipefail

repo_url="${CLAUDE_SANDBOX_REPO:-https://github.com/timche/claude-sandbox.git}"
target="${CLAUDE_SANDBOX_DIR:-$HOME/claude-sandbox}"

# Empty when piped in, since there is no file backing the script.
source_path="${BASH_SOURCE[0]:-}"

if [ -z "$source_path" ] || [ ! -f "$(dirname "$source_path")/bootstrap-system.sh" ]; then
  if ! command -v git >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y git
  fi

  if [ -d "$target/.git" ]; then
    git -C "$target" pull --ff-only
  else
    git clone "$repo_url" "$target"
  fi

  # stdin is the pipe feeding this script, so hand the real terminal to the
  # clone — otherwise the key prompts and any sudo password have nowhere to go.
  # /dev/tty exists even with no controlling terminal, so opening it is the only
  # honest test; without this, a piped run on a headless box dies here.
  if (exec </dev/tty) 2>/dev/null; then
    exec "$target/setup.sh" </dev/tty
  fi

  exec "$target/setup.sh"
fi

repo="$(cd "$(dirname "$source_path")" && pwd)"

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
# the dotfiles: the shell is running on the fallback rc files.
if ! gh auth status >/dev/null 2>&1; then
  echo "  - $repo/login.sh — GitHub and tailscale, then it fetches the dotfiles"
  echo "    and hands the shell, the runtimes and ~/.claude over to them."
elif ! tailscale status >/dev/null 2>&1; then
  echo "  - sudo tailscale up — $repo/login.sh tried and did not get there."
fi

cat <<'EOF'
  - claude, then /login
  - Log out and back in so the docker group and the zsh login shell take hold.
EOF

exit "$keys_failed"
