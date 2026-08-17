#!/bin/bash

# User-level setup: install the tooling, then link home/ into $HOME.
#
# Safe to re-run. Tools already present are skipped, and anything real found at
# a link target is moved aside to <name>.backup first.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tooling

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

powerlevel10k="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$powerlevel10k"
fi

# The installer only serves stable; this VM tracks canary deliberately.
if [ ! -d "$HOME/.bun" ]; then
  curl -fsSL https://bun.sh/install | bash
  "$HOME/.bun/bin/bun" upgrade --canary
fi

if [ ! -d "$HOME/.local/share/fnm" ]; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
eval "$(fnm env --shell bash)"
fnm install --lts
fnm default lts-latest

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

if ! command -v herdr >/dev/null 2>&1; then
  curl -fsSL https://herdr.dev/install.sh | sh
fi

# Needs an authenticated gh, so it is skipped rather than failing the run.
if gh auth status >/dev/null 2>&1; then
  if ! gh extension list 2>/dev/null | grep -q gh-stack; then
    gh extension install github/gh-stack
  fi
else
  echo "gh is not authenticated — run 'gh auth login', then rerun to get gh-stack" >&2
fi

# Symlinks

link() {
  local target="$HOME/$1"

  mkdir -p "$(dirname "$target")"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.backup"
    echo "moved aside $target -> $target.backup"
  fi

  ln -sfn "$repo/home/$1" "$target"
  echo "linked $target"
}

link .bashrc
link .gitconfig
link .p10k.zsh
link .zshrc
link .config/herdr/config.toml
link .terminfo/x/xterm-ghostty
