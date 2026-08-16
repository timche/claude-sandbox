#!/bin/bash

# System setup for a bare Debian or Ubuntu VM: packages, docker, tailscale,
# sshd hardening. Needs sudo, and only has to run once.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

distro="$(. /etc/os-release && echo "$ID")"
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
architecture="$(dpkg --print-architecture)"

case "$distro" in
  debian | ubuntu) ;;
  *)
    echo "unsupported distribution: $distro (expected debian or ubuntu)" >&2
    exit 1
    ;;
esac

# btop lives in universe on Ubuntu, which minimal images leave off.
if [ "$distro" = ubuntu ] && ! grep -qr universe /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y universe
fi

# unzip is what bun's installer extracts with, jq is what the settings.json
# hooks parse with, and ssh-keygen out of openssh-client is what git signs
# commits with — none of the three are obvious from their names.
sudo apt-get update
sudo apt-get install -y \
  btop ca-certificates curl git jq openssh-client openssh-server sudo \
  unattended-upgrades unzip vim zsh zsh-syntax-highlighting

# Third-party repositories. Docker and tailscale publish per-distribution
# trees; the github-cli one is shared.

sudo install -d -m 0755 /etc/apt/keyrings

sudo curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/$distro
Suites: $codename
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
sudo chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$architecture signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

sudo curl -fsSL "https://pkgs.tailscale.com/stable/$distro/$codename.noarmor.gpg" \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
sudo curl -fsSL "https://pkgs.tailscale.com/stable/$distro/$codename.tailscale-keyring.list" \
  -o /etc/apt/sources.list.d/tailscale.list

sudo apt-get update
sudo apt-get install -y gh tailscale \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# System configuration

sudo install -m 0644 "$repo/system/docker/daemon.json" /etc/docker/daemon.json

sudo install -d -m 0755 /etc/ssh/sshd_config.d
sed "s/__USER__/$USER/" "$repo/system/ssh/10-hardening.conf" \
  | sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null

# Skipped inside containers, where there is no init to talk to.
if [ -d /run/systemd/system ]; then
  sudo systemctl restart docker
  sudo systemctl reload ssh || sudo systemctl restart ssh
  sudo systemctl enable --now tailscaled
fi

sudo usermod -aG docker "$USER"

zsh_path="$(command -v zsh)"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]; then
  sudo chsh -s "$zsh_path" "$USER"
fi
