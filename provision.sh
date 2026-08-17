#!/bin/bash

# Provision a VM the way a fresh one arrives from a provider: root over SSH, no
# unprivileged account yet. Creates that account, gives it the keys root is
# already reachable with, and hands everything else to setup.sh running as it.
#
#   curl -fsSL https://raw.githubusercontent.com/timche/claude-sandbox/main/provision.sh | bash
#
# Nothing here duplicates setup.sh. Once the user exists, the two paths are the
# same path — which is why this script is short and setup.sh is not.
#
# Safe to re-run: an existing user is reused, and keys are merged rather than
# replaced.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

user="${CLAUDE_SANDBOX_USER:-timche}"
repo_url="${CLAUDE_SANDBOX_REPO:-https://github.com/timche/claude-sandbox.git}"

# Extra keys to authorize, one per line, for runs with nobody at the keyboard.
extra_keys="${SSH_PUBLIC_KEYS:-}"

root_keys=/root/.ssh/authorized_keys
sudoers_drop_in="/etc/sudoers.d/90-claude-sandbox-provision"

if [ "$(id -u)" -ne 0 ]; then
  echo "provision.sh has to run as root — it creates the user. Already have" >&2
  echo "an account? Run setup.sh as that account instead." >&2
  exit 1
fi

distro="$(. /etc/os-release && echo "$ID")"
case "$distro" in
  debian | ubuntu) ;;
  *)
    echo "unsupported distribution: $distro (expected debian or ubuntu)" >&2
    exit 1
    ;;
esac

# Enough to create the user and clone the repo. bootstrap-system.sh, running
# later as the user, is what installs the rest.
apt-get update
apt-get install -y ca-certificates curl git openssh-client sudo

# User

if ! id -u "$user" >/dev/null 2>&1; then
  # bootstrap-system.sh switches this to zsh once zsh exists.
  useradd -m -s /bin/bash "$user"
  echo "created $user"
fi

usermod -aG sudo "$user"

home="$(getent passwd "$user" | cut -d: -f6)"

# useradd leaves the account locked, so sudo has nothing to authenticate
# against later. Group membership alone is useless without this.
if [ "$(passwd -S "$user" | awk '{print $2}')" != "P" ]; then
  if [ -t 0 ]; then
    echo
    echo "Set a password for $user — sudo needs one after this run finishes."
    passwd "$user"
  else
    echo "warning: no terminal to set a password at. Run 'passwd $user'," >&2
    echo "         or sudo will be unusable for $user." >&2
  fi
fi

# SSH keys

# The directory has to be user-owned either way, or the VM cannot write
# known_hosts, which breaks git over SSH from inside it.
install -d -m 0700 -o "$user" -g "$user" "$home/.ssh"

authorized_keys="$home/.ssh/authorized_keys"
staged="$(mktemp)"
trap 'rm -f "$staged" "$staged.one"' EXIT

# Whatever is already there stays: cloud-init's key, or a previous run's.
[ -f "$authorized_keys" ] && cat "$authorized_keys" >>"$staged"
[ -s "$root_keys" ] && cat "$root_keys" >>"$staged"
[ -n "$extra_keys" ] && printf '%s\n' "$extra_keys" >>"$staged"

collect_keys() {
  grep -Ev '^[[:space:]]*(#|$)' "$staged" | sort -u >"$staged.one" || true
  mv "$staged.one" "$staged"
}

collect_keys

# Nothing to inherit and someone is watching, so ask rather than quietly leave
# the account unreachable.
if [ ! -s "$staged" ] && [ -t 0 ]; then
  echo
  echo "No SSH public key found for $user, and root has none to inherit."
  echo "Paste one, e.g. 'ssh-ed25519 AAAA... tim@macbook'."
  echo "Enter on an empty line moves on."

  while :; do
    read -r -p "key> " pasted || break
    [ -n "$pasted" ] || break

    printf '%s\n' "$pasted" >"$staged.one"

    if ssh-keygen -l -f "$staged.one" >/dev/null 2>&1; then
      cat "$staged.one" >>"$staged"
      echo "  ok — paste another, or Enter to move on."
    else
      echo "  that does not parse as a public key; try again." >&2
    fi

    rm -f "$staged.one"
  done

  collect_keys
fi

if [ -s "$staged" ]; then
  # install(1) sets owner and mode as it creates, so the file is never
  # world-readable in between.
  install -m 0600 -o "$user" -g "$user" "$staged" "$authorized_keys"
  echo "authorized $(wc -l <"$authorized_keys") key(s) for $user"
else
  # setup.sh reaches keys.sh later, and harden-ssh.sh holds off until then.
  echo "no keys authorized yet for $user — keys.sh will ask"
fi

# The repo

target="$home/claude-sandbox"

if [ -d "$target/.git" ]; then
  sudo -u "$user" git -C "$target" pull --ff-only
else
  sudo -u "$user" git clone "$repo_url" "$target"
fi

# Hand over

# setup.sh sudos its way through a long apt run as $user, and the password just
# set would expire out of sudo's timestamp partway through. Lift the
# requirement for the length of this run only — the trap goes on first, so a
# rejected sudoers file cannot leave a standing grant behind.
trap 'rm -f "$staged" "$staged.one" "$sudoers_drop_in"' EXIT

cat >"$sudoers_drop_in" <<EOF
$user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 "$sudoers_drop_in"
visudo -cf "$sudoers_drop_in" >/dev/null

# bootstrap-system.sh makes zsh the login shell, so a second run would hand
# setup.sh to a shell whose rc files expect a terminal. -s keeps it bash.
#
# stdin may also be the curl pipe feeding this script, so pass the real
# terminal along — setup.sh's key prompts have nowhere to go otherwise.
if (exec </dev/tty) 2>/dev/null; then
  su - "$user" -s /bin/bash -c "$target/setup.sh" </dev/tty
else
  su - "$user" -s /bin/bash -c "$target/setup.sh"
fi

cat <<EOF

Provisioned. Before closing this session, from a second terminal:

    ssh $user@<host>
    sudo -v && docker ps && claude --version

One more thing worth knowing: docker writes its own iptables rules and goes
around a host firewall, so a firewall at the provider is the one that counts.
EOF
