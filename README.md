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

On a VM that already has your account, as that account:

```sh
curl -fsSL https://raw.githubusercontent.com/timche/claude-sandbox/main/setup.sh | bash
```

On one that arrived as root and nothing else — a netcup or hetzner box, say —
as root:

```sh
curl -fsSL https://raw.githubusercontent.com/timche/claude-sandbox/main/provision.sh | bash
```

No authentication needed — this repo is public. Piped in like that, `setup.sh`
installs `git` if the image lacks it, clones the repo to `~/claude-sandbox`,
and hands over to the copy inside it. Re-running pulls and goes again.

The clone isn't a formality: `install.sh` symlinks your dotfiles out of the
repo, so it has to stay on disk. `~/claude-sandbox` is where it lives, or set
`CLAUDE_SANDBOX_DIR` to put it elsewhere.

If the image has no `curl` either, `sudo apt-get install -y curl` first, or
clone by hand and run `~/claude-sandbox/setup.sh` directly — both work.

### From root

`provision.sh` covers the one thing `setup.sh` cannot do for itself: exist as a
user. It creates the account (`timche`, or `CLAUDE_SANDBOX_USER`), puts it in
`sudo`, prompts for a password since `useradd` leaves the account locked and
sudo has nothing to authenticate against otherwise, and copies root's
`authorized_keys` across so you can log back in as the new user. Nothing to
copy and a terminal to ask at, and it prompts for a key instead, checking each
paste with `ssh-keygen -l`. `SSH_PUBLIC_KEYS` supplies them for runs with
nobody watching.

Then it clones the repo and runs `setup.sh` as the new user, which is where
everything else happens. The two entry points converge there deliberately —
`provision.sh` stops at the user boundary.

For the length of that run only, the user gets a `NOPASSWD` sudoers drop-in,
removed on exit: `setup.sh` sudos through a long apt run, and the password just
set would otherwise expire out of sudo's timestamp partway through.

`setup.sh` runs the halves in order:

- `bootstrap-system.sh` — needs sudo, run once. apt upgrade and packages, the
  docker, github-cli and tailscale repositories, `/etc/docker/daemon.json`,
  unattended-upgrades, docker group membership, and zsh as the login shell.
- `install.sh` — no sudo, safe to re-run. oh-my-zsh, powerlevel10k, bun, fnm
  and node, Claude Code, herdr, the `gh-stack` extension, then the symlinks.
- `keys.sh` — prompts for the SSH keys, which is the one credential step that
  can be scripted. Skipped when there is no terminal to prompt at, so
  `setup.sh` stays usable from CI.
- `harden-ssh.sh` — installs the sshd drop-in, last of all.

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

### Hardening

`harden-ssh.sh` is what turns password logins off, and it runs after `keys.sh`
rather than as part of the system bootstrap. That ordering is the whole point:
harden a fresh VM before an `authorized_keys` exists and the only way back in
is the provider's console. It refuses when the user it is hardening has no
keys, and says how to run it again once they do — `FORCE_HARDEN=true`
overrides that if you are sure of another way in.

The drop-in is validated with `sshd -t` before anything is restarted, and
removed again if sshd rejects it. It takes the user to allow as its argument,
defaulting to whoever runs it.

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
`install.sh` honest about being safe to re-run. Then it seeds an
`authorized_keys`, runs `harden-ssh.sh` and asserts once more, so both the
refusal and the drop-in are covered.

A second container per image covers `provision.sh` from the other end: nothing
but root, a key handed in through `SSH_PUBLIC_KEYS`, and the same assertions
against the user it creates. That one clones rather than copying, so it sees
the last commit and not the working tree — `run.sh` says so when they differ.

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
`/run/systemd/system` is absent, so `systemctl restart docker`, the `ssh`
restart and `enable --now tailscaled` are the one part no container can cover.

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
