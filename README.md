# Claude Sandbox

[![test](https://github.com/timche/claude-sandbox/actions/workflows/test.yml/badge.svg)](https://github.com/timche/claude-sandbox/actions/workflows/test.yml)

> Setup for `claude`, a Debian or Ubuntu sandbox VM dedicated to running Claude Code

The VM exists to run Claude Code and nothing else, which is why the machine
runs it with `bypassPermissions` — there is nothing on it worth guarding
Claude from.

Everything here is machine setup and safe to publish. The Claude Code
configuration — instructions, skills, and per-project memory — lives in a
private companion repo, `claude-dotfiles`, because the memory files describe
infrastructure on private projects. Splitting on the `~/.claude` boundary means
no memory path can end up in this repo by construction, and there is a test
asserting exactly that.

## Usage

On a fresh Debian or Ubuntu VM:

```sh
sudo apt-get install -y git
git clone https://github.com/timche/claude-sandbox.git ~/claude-sandbox
~/claude-sandbox/setup.sh
```

No authentication needed — this repo is public, and `git` is the only thing a
bare image is missing. `setup.sh` installs `gh` along the way, which is what
you then use to fetch the private half.

`setup.sh` runs both halves:

- `bootstrap-system.sh` — needs sudo, run once. apt packages, the docker,
  github-cli and tailscale repositories, `/etc/docker/daemon.json`, the sshd
  hardening drop-in, docker group membership, and zsh as the login shell.
- `install.sh` — no sudo, safe to re-run. oh-my-zsh, powerlevel10k, bun, fnm
  and node, Claude Code, herdr, the `gh-stack` extension, then the symlinks.
- `keys.sh` — prompts for the SSH keys, which is the one credential step that
  can be scripted. Skipped when there is no terminal to prompt at, so
  `setup.sh` stays usable from CI.

Both distributions are supported from the same scripts. Docker and tailscale
publish separate package trees, so the repository URLs are built from `ID` and
`VERSION_CODENAME` in `/etc/os-release`; anything other than `debian` or
`ubuntu` is refused up front. On Ubuntu, `universe` is enabled first when
missing, since `btop` lives there. Verified end to end on `debian:13` and
`ubuntu:24.04`.

### SSH keys

`keys.sh` runs as part of `setup.sh`, or on its own at any time. Paste the
private signing key when it asks — the public half is derived with
`ssh-keygen -y`, so there is only one thing to paste, and deriving it doubles
as validation: a truncated paste fails before anything is written. The result
is checked against the `allowed_signers` this repo tracks, so pasting the wrong
key is caught here rather than surfacing later as commits that will not verify.

Then paste the public keys allowed to SSH in, one per line. Existing entries
are not duplicated, and modes are set to 600 / 644 / 600.

### What stays manual

Anything needing a browser or a login:

1. `gh auth login`, then rerun `install.sh` for the `gh-stack` extension.
2. `sudo tailscale up`
3. `claude`, then `/login`
4. Log out and back in for the docker group and login shell.

## Layout

`home/` mirrors `$HOME` and `system/` mirrors `/etc`.

| Path | Links to | |
| --- | --- | --- |
| `home/.zshrc` `.p10k.zsh` `.bashrc` | `$HOME` | Shell, prompt, bun and fnm on `PATH` |
| `home/.gitconfig` | `$HOME` | SSH-signed commits, `gh` as the credential helper |
| `home/.config/herdr/config.toml` | `$HOME` | Toast delivery and agent panel sort |
| `home/.ssh/allowed_signers` | `$HOME` | Public half of the signing key |
| `home/.terminfo/x/xterm-ghostty` | `$HOME` | Ghostty terminfo for SSH sessions |
| `system/docker/daemon.json` | `/etc/docker/` | Binds to localhost, caps log size |
| `system/ssh/10-hardening.conf` | `/etc/ssh/sshd_config.d/` | Keys only, no root, `AllowUsers` |

Paths use `$HOME` rather than a hardcoded home directory, and the sshd
drop-in's `__USER__` placeholder is substituted at install time, so nothing
here depends on the account being named `timche`.

## Tests

`test/run.sh` provisions a throwaway container per distribution, runs
`setup.sh` in it as an unprivileged sudo user, asserts the result, then runs
`install.sh` a second time and asserts again — the repeat is what keeps
`install.sh` honest about being safe to re-run.

```sh
test/run.sh                  # debian:13 and ubuntu:24.04
test/run.sh ubuntu:22.04     # one image
KEEP=1 test/run.sh           # leave the containers up to poke at
```

Nothing touches the machine it runs on; every change lands inside the
container. Failures print the last 40 lines of output and keep the full log.

`test/assert.sh` holds the checks and runs inside the container. Adding one is
a single `check` line — a description and a snippet that exits non-zero when
the expectation is not met. Prefer assertions that would catch a real
regression: that an interactive shell resolves `node`, not merely that a file
exists.

The same two images run in CI on every push and pull request
(`.github/workflows/test.yml`). Service management is skipped where
`/run/systemd/system` is absent, so `systemctl restart docker`, `reload ssh`
and `enable --now tailscaled` are the one part no container can cover.

## What's deliberately left out

Credentials, obviously: `~/.config/gh/hosts.yml` is a `gh auth login` away, and
the SSH keys are pasted in by `keys.sh`. `btop.conf` is left out too — it is all
defaults, which btop rewrites on exit.

Anything under `~/.claude` belongs in `claude-dotfiles`, not here.

## The private half

Once this repo has finished, fetch the Claude Code configuration:

```sh
gh auth login
gh repo clone claude-dotfiles ~/claude-dotfiles
~/claude-dotfiles/install.sh
```

That repo links `CLAUDE.md`, `settings.json`, `skills/` and per-project memory
into `~/.claude`, and carries the `PostToolUse` hook that keeps memory synced
back to it.
