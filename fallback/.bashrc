# claude-sandbox fallback rc
# A shell that works before the private half lands.
#
# claude-sandbox installs zsh and makes it the login shell, but everything that
# makes it pleasant — the prompt and the runtimes — comes from
# claude-dotfiles, which cannot be cloned until gh is logged in. This covers the
# gap, and a headless VM that never logs in keeps it for good.
#
# Copied rather than linked, so claude-dotfiles moves it aside to .bashrc.backup
# and takes over. Keep it minimal: everything here is a thing that has to keep
# working with nothing else underneath it.

export PATH="$HOME/.local/bin:$PATH"

BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL" ] && export PATH="$BUN_INSTALL/bin:$PATH"

FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --shell bash)"
fi

PS1='\u@\h \w \$ '
