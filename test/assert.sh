#!/bin/bash

# Assertions against a machine that setup.sh has just finished with. Runs
# inside the test container as the unprivileged user; see run.sh.
#
# To add a case, add a check line: a description and a shell snippet that
# exits non-zero when the expectation is not met.

set -uo pipefail

failures=0

check() {
  local description="$1" snippet="$2"

  if bash -c "$snippet" >/dev/null 2>&1; then
    echo "  ok    $description"
  else
    echo "  FAIL  $description"
    failures=$((failures + 1))
  fi
}

# The fallback rc files, copied rather than linked so the clone stays
# disposable. Real content found at a target is kept, the way the dotfiles
# installer keeps this one.
for rc in .zshrc .bashrc; do
  check "$rc is the fallback, not a symlink" \
    "[ -f \"\$HOME/$rc\" ] && [ ! -L \"\$HOME/$rc\" ] && grep -q 'claude-sandbox fallback' \"\$HOME/$rc\""
done

check "the stock .bashrc was preserved, not overwritten" '[ -f "$HOME/.bashrc.backup" ]'

# The login shell is switched to zsh here, so the fallback has to survive being
# sourced by one — with no oh-my-zsh underneath it, which is the state a VM
# sits in until someone logs in to GitHub.
check "interactive zsh starts on the fallback"  'zsh -ic "echo ok" | grep -q ok'
check "interactive bash starts on the fallback" 'bash -ic "echo ok" | grep -q ok'

# This repo is public and holds no personal configuration at all now — the
# shell, the runtimes and ~/.claude all come from the private one. A stray dot
# directory here would be a leak.
check "no personal config in this repo" \
  '! find "$HOME/claude-sandbox" \( -name .claude -o -name home \) -not -path "*/.git/*" | grep -q .'

# System side.
check "login shell is zsh"      'getent passwd "$USER" | cut -d: -f7 | grep -q zsh'
check "user is in docker group" 'id -nG "$USER" | tr " " "\n" | grep -qx docker'
check "user is in sudo group"   'id -nG "$USER" | tr " " "\n" | grep -qx sudo'
check "docker installed"        'command -v docker'
check "gh installed"            'command -v gh'
check "tailscale installed"     'command -v tailscale'
check "btop installed"          'command -v btop'
check "unzip installed"         'command -v unzip'
check "jq installed"            'command -v jq'
check "ssh-keygen installed"    'command -v ssh-keygen'
check "sshd installed"          '[ -x /usr/sbin/sshd ]'
check "daemon.json installed"   'grep -q 127.0.0.1 /etc/docker/daemon.json'
check "unattended-upgrades switched on" \
  'grep -q "Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades'

# harden-ssh.sh holds the drop-in back until there is a key to log in with, so
# which half of this is asserted depends on whether run.sh has seeded one yet.
# Both halves matter: the refusal is what keeps a fresh VM reachable.
if [ -s "$HOME/.ssh/authorized_keys" ]; then
  check "sshd drop-in names this user" \
    'grep -qx "AllowUsers $USER" /etc/ssh/sshd_config.d/10-hardening.conf'
  check "sshd drop-in kept no placeholder" \
    '[ -f /etc/ssh/sshd_config.d/10-hardening.conf ] && ! grep -q __USER__ /etc/ssh/sshd_config.d/10-hardening.conf'
  check "sshd drop-in disables passwords" \
    'grep -qx "PasswordAuthentication no" /etc/ssh/sshd_config.d/10-hardening.conf'
  # Whether sshd will parse it is asserted from root in run.sh — reading the
  # host keys needs privileges this user may no longer have.
  check "sshd drop-in belongs to root" \
    '[ "$(stat -c "%U %a" /etc/ssh/sshd_config.d/10-hardening.conf)" = "root 644" ]'
  check "authorized_keys is not group or world readable" \
    '[ "$(stat -c %a "$HOME/.ssh/authorized_keys")" = 600 ]'
  check "authorized_keys belongs to this user" \
    '[ "$(stat -c %U "$HOME/.ssh/authorized_keys")" = "$USER" ]'
else
  check "no drop-in until there is a key to log in with" \
    '[ ! -f /etc/ssh/sshd_config.d/10-hardening.conf ]'
  check "harden-ssh.sh refuses rather than failing the run" \
    '"$HOME/claude-sandbox/harden-ssh.sh"'
fi

# keys.sh prompts for a paste. If it ever stops bailing out without a terminal,
# setup.sh blocks forever here instead of finishing.
check "keys.sh exits without a terminal" \
  '"$HOME/claude-sandbox/keys.sh" < /dev/null'

# Same again for login.sh, which drives two browser flows and would sit on the
# gh prompt forever. timeout, because the failure mode is a hang and not an
# exit status.
check "login.sh exits without a terminal" \
  'timeout 30 "$HOME/claude-sandbox/login.sh" < /dev/null'

# gh is installed here but never logged in, which is the state every fresh VM
# is in. Registering the signing key has to skip out of that, not fail the run.
check "register-signing-key.sh skips when gh cannot help" \
  '"$HOME/claude-sandbox/register-signing-key.sh"'

if [ "$failures" -gt 0 ]; then
  echo "  $failures check(s) failed"
  exit 1
fi
