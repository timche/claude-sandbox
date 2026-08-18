# Claude Sandbox

[![test](https://github.com/timche/claude-sandbox/actions/workflows/test.yml/badge.svg)](https://github.com/timche/claude-sandbox/actions/workflows/test.yml)

> Setup for `claude`, a Debian sandbox VM dedicated to running Claude Code

The VM exists to run Claude Code and nothing else, which is why the machine
runs it with `bypassPermissions` — there is nothing on it worth guarding
Claude from.

Everything here is machine setup and safe to publish: packages, docker, sshd,
the account. Everything personal — the shell, the prompt, the runtimes, and all
of `~/.claude` — lives in a private companion repo, `claude-dotfiles`, which
this one clones as soon as `gh` is logged in.

The line between them is *works before you can authenticate* against *needs an
account*, and it means this repo exposes nothing but the shape of the machine.
A test asserts no personal path can appear here.

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

Nothing symlinks out of this clone, so it is disposable once the run is done —
`harden-ssh.sh` is the only script that still reads a file from it. It lives at
`~/claude-sandbox`, or set `CLAUDE_SANDBOX_DIR` to put it elsewhere. The
private clone is the one that has to stay on disk.

If the image has no `curl` either, `sudo apt-get install -y curl` first, or
clone by hand and run `~/claude-sandbox/setup.sh` directly — both work.

### From root

`provision.sh` covers the one thing `setup.sh` cannot do for itself: exist as a
user. It creates the account (`claude`, or `CLAUDE_SANDBOX_USER`), puts it in
`sudo`, generates a password since `useradd` leaves the account locked and sudo
has nothing to authenticate against otherwise, and copies root's
`authorized_keys` across so you can log back in as the new user. Nothing to
copy and a terminal to ask at, and it prompts for a key instead, checking each
paste with `ssh-keygen -l`. `SSH_PUBLIC_KEYS` supplies them for runs with
nobody watching.

The password is printed at the end of the run and stored nowhere, so a headless
provision ends with a usable sudo too. Write it down before closing the
session. On a re-run it asks before replacing a password that is already set,
the way `keys.sh` asks before replacing a signing key.

Then it clones the repo and runs `setup.sh` as the new user, which is where
everything else happens. The two entry points converge there deliberately —
`provision.sh` stops at the user boundary.

For the length of that run only, the user gets a `NOPASSWD` sudoers drop-in,
removed on exit: `setup.sh` sudos through a long apt run, and the password just
set would otherwise expire out of sudo's timestamp partway through.

`setup.sh` runs the halves in order:

- `bootstrap-system.sh` — needs sudo, run once. apt upgrade and packages, the
  docker, github-cli and tailscale repositories, `/etc/docker/daemon.json`,
  unattended-upgrades, docker group membership, zsh as the login shell, and the
  fallback rc files that make that shell usable until the real ones arrive.
- `install.sh` — clones `claude-dotfiles` and runs its installer, which is what
  brings the shell, the prompt, the runtimes and `~/.claude`. Needs an
  authenticated `gh`, so on a fresh VM it says so and returns.
- `login.sh` — `gh auth login` and `sudo tailscale up`, then `install.sh`
  again, now that there is a token. Skipped without a terminal.
- `keys.sh` — prompts for the commit-signing key and the `authorized_keys`.
  After `login.sh`, because the `allowed_signers` principal is read from the
  `.gitconfig` the dotfiles carry. Skipped without a terminal too, so
  `setup.sh` stays usable from CI.
- `harden-ssh.sh` — installs the sshd drop-in, last of all.

`register-signing-key.sh` is called by `install.sh` and `keys.sh` rather than
by `setup.sh`, and runs on its own too.

Debian only, and anything else is refused up front. Docker and tailscale
publish a package tree per release, so those repository URLs are built from
`VERSION_CODENAME` in `/etc/os-release`. Verified end to end on `debian:13`.

### SSH keys

`keys.sh` runs as part of `setup.sh`, or on its own at any time. Paste the
private signing key when it asks — the public half is derived with
`ssh-keygen -y`, so there is only one thing to paste, and deriving it doubles
as validation: a truncated paste fails before anything is written.

The same key goes on every VM, which is the point: one key registered with
GitHub once, and commits verify wherever they were made. The cost is that the
private half travels, so a compromised box means rotating it everywhere.
Agent forwarding would avoid that, but sessions here outlive the connection
that started them and a detached agent with no forwarded socket cannot sign.

`keys.sh` then writes `~/.ssh/allowed_signers` — the trust list git checks a
signature against — so local verification works as soon as it finishes. That
file is not tracked here: it is derived from a private key, and deriving it
locally costs nothing. `keys.sh` also unlinks the symlink earlier versions
installed, so an upgrading box does not write back into tracked content.

GitHub is the other half, and `register-signing-key.sh` does it once `gh` can.
Both `install.sh` and `keys.sh` call it, and it is runnable on its own:

```sh
gh auth refresh -h github.com -s write:ssh_signing_key
~/claude-sandbox/register-signing-key.sh
```

That scope is separate from `admin:public_key` — GitHub keeps signing keys and
authentication keys in different collections, and the interactive `gh auth
login` asks for neither, which is why `login.sh` passes it explicitly and the
refresh above is only for a login made some other way. Everything that stops
the script is a skip rather than a failure, and it says which one: no key, no
`gh`, not logged in, or no scope. So the first pass of a fresh VM always skips
it, and the `install.sh` rerun at the end of `login.sh` is what picks it up.

The key is added under the machine's hostname, and a key already on the
account is left alone. Until it lands, GitHub shows the commits unverified even
though `git log --format='%G?'` reports `G` on the box itself.

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

`login.sh` runs at the end of `setup.sh` and drives the two account logins for
you: `gh auth login` with the signing-key scope already requested, then
`sudo tailscale up`. Both print a code and a URL to open on whichever machine
has a browser — this one has none. Then it reruns `install.sh`, which is what
finally installs `gh-stack`, registers the signing key and fetches
`claude-dotfiles`.

That leaves two:

1. `claude`, then `/login`
2. Log out and back in for the docker group and login shell.

`login.sh` is also the script to rerun on its own if a login was skipped or has
since expired.

## Layout

`system/` mirrors `/etc`, and `fallback/` mirrors `$HOME`.

| Path | Goes to | |
| --- | --- | --- |
| `fallback/.zshrc` `.bashrc` | `$HOME`, copied | A working shell until the dotfiles land |
| `system/docker/daemon.json` | `/etc/docker/` | Binds to localhost, caps log size |
| `system/ssh/10-hardening.conf` | `/etc/ssh/sshd_config.d/` | Keys only, no root, `AllowUsers` |

The rc files are copied, not linked, which is what makes this clone
disposable — and they carry a marker line so a re-run can tell its own file
from a stock one. `claude-dotfiles` moves them aside to `<name>.backup` when it
takes over.

Paths use `$HOME` rather than a hardcoded home directory, and the sshd
drop-in's `__USER__` placeholder is substituted at install time, so nothing
here depends on the account being named `claude`.

## Tests

`test/run.sh` provisions a throwaway container per image, runs
`setup.sh` in it as an unprivileged sudo user, asserts the result, then runs
`install.sh` a second time and asserts again — the repeat is what keeps
`install.sh` honest about being safe to re-run. Then it seeds an
`authorized_keys`, runs `harden-ssh.sh` and asserts once more, so both the
refusal and the drop-in are covered.

What no container reaches is the private half: `gh` is never logged in, so
`install.sh` always takes its skip path and the dotfiles never arrive. The
assertions for those — the symlinks, the tooling, the interactive shell — live
in `claude-dotfiles`, which has a suite of the same shape.

A second container per image covers `provision.sh` from the other end: nothing
but root, a key handed in through `SSH_PUBLIC_KEYS`, and the same assertions
against the user it creates. That one clones rather than copying, so it sees
the last commit and not the working tree — `run.sh` says so when they differ.

```sh
test/run.sh                  # debian:13
test/run.sh debian:12        # another release
KEEP=1 test/run.sh           # leave the containers up to poke at
```

Nothing touches the machine it runs on; every change lands inside the
container. Failures print the last 40 lines of output and keep the full log.

`test/assert.sh` holds the checks and runs inside the container. Adding one is
a single `check` line — a description and a snippet that exits non-zero when
the expectation is not met. Prefer assertions that would catch a real
regression: that an interactive shell resolves `node`, not merely that a file
exists.

The same image runs in CI on every push and pull request
(`.github/workflows/test.yml`). Service management is skipped where
`/run/systemd/system` is absent, so `systemctl restart docker`, the `ssh`
restart and `enable --now tailscaled` are the one part no container can cover.

## What's deliberately left out

Credentials, obviously: `~/.config/gh/hosts.yml` is a `gh auth login` away, and
the SSH keys are `keys.sh`'s business — the signing key and the
`authorized_keys` pasted in, `allowed_signers` derived there. `btop.conf` is
left out too — it is all defaults, which btop rewrites on exit.

Anything personal belongs in `claude-dotfiles`, not here — `~/.claude`, the
shell, the prompt, the runtimes.

## The private half

It is fetched by `install.sh` once `gh` is logged in, which in a normal run
means the pass `login.sh` makes on the way through. By hand it is:

```sh
gh repo clone claude-dotfiles ~/claude-dotfiles
~/claude-dotfiles/install.sh
```

Being private is the whole reason it cannot happen earlier. `CLAUDE_DOTFILES_REPO`
and `CLAUDE_DOTFILES_DIR` move it elsewhere, and a clone that fails — which is
what it does for anyone who is not its owner — is a message, not a failed run.

That repo installs oh-my-zsh, powerlevel10k, bun, fnm and node, Claude Code
and herdr; links `home/` into `$HOME`; links `CLAUDE.md`, `settings.json`,
`skills/` and per-project memory into `~/.claude`; and carries the `PostToolUse`
hook that keeps memory synced back to it.
