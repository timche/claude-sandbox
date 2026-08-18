# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Machine provisioning for a Debian VM dedicated to running Claude Code. No
build, no lint, no package manager — the deliverable is the scripts themselves.

This repo is public and holds nothing personal: the shell, the prompt, the
runtimes and everything under `~/.claude` live in the private
`claude-dotfiles`, which `install.sh` clones once `gh` is logged in. The line
between the two is *works before you can authenticate* against *needs an
account*.

## Testing

```sh
test/run.sh                  # debian:13, the supported release
test/run.sh debian:12        # another release
KEEP=1 test/run.sh           # leave the containers up to poke at
```

Everything happens inside throwaway containers; the host is never touched. A
run takes several minutes (apt upgrade, bun, node, claude), so start it in the
background.

There is no single-test runner. `test/assert.sh` is a flat list of `check`
lines — a description and a snippet that exits non-zero on failure — and it
runs inside the container, so a new assertion is one line there. Prefer
assertions that would catch a real regression: that an interactive shell
resolves `node`, not merely that a file exists.

`test/run.sh` builds two containers per image. The first copies the working
tree in and runs `setup.sh`, then `install.sh` a second time to prove
idempotency, then seeds an `authorized_keys` and runs `harden-ssh.sh`. The
second runs `provision.sh` from bare root — and that one **clones the repo, so
it tests HEAD and not the working tree**. Commit before trusting its result;
`run.sh` prints a note when they differ.

CI (`.github/workflows/test.yml`) runs `test/run.sh debian:13` on every push
and PR.

Nothing here covers the private half — `gh` is never authenticated inside a
container, so `install.sh` always takes its skip path. The assertions for the
dotfiles, the tooling and the interactive shell live in `claude-dotfiles`,
which has a suite of the same shape.

## Architecture

Two entry points converge on `setup.sh`:

- `provision.sh` — runs as **root** on a VM that has nothing but root. Creates
  the user, generates its password, inherits root's `authorized_keys`, clones
  the repo, then hands over to `setup.sh` as that user. It deliberately does
  nothing `setup.sh` could do for itself, which is why it stops at the user
  boundary.
- `setup.sh` — runs as the **user**. Works from a clone or piped from the web,
  in which case it clones first and re-execs the copy inside. Calls the halves
  in order: `bootstrap-system.sh` (sudo, system packages, docker/gh/tailscale
  repos, login shell, fallback rc files), `install.sh` (clones
  `claude-dotfiles` and runs its installer), `login.sh`, `keys.sh`,
  `harden-ssh.sh`.

`system/` mirrors `/etc`, and `fallback/` mirrors `$HOME` — but its two rc
files are **copied**, not linked, so that this clone stays disposable. Only
`harden-ssh.sh` still reads out of it at runtime.

### Ordering constraints that are not obvious

- `harden-ssh.sh` runs **last** because it turns password logins off. It
  refuses when the target user has no `authorized_keys`, since hardening a
  fresh VM before a key exists leaves it reachable only from the provider's
  console. `FORCE_HARDEN=true` overrides.
- `keys.sh`, `login.sh` and the interactive prompts in `provision.sh` are gated
  on `[ -t 0 ]`. Without a terminal they skip rather than block, which is what
  keeps `setup.sh` usable from CI. If either script ever stops bailing out
  headlessly, the suite hangs instead of failing — `assert.sh` runs `login.sh`
  under `timeout` for exactly that reason.
- `login.sh` runs **before** `keys.sh`, not last: `keys.sh` reads `user.email`
  for the `allowed_signers` principal out of the `.gitconfig` that only arrives
  with the dotfiles, and `login.sh` is what fetches them. It ends by rerunning
  `install.sh`, which is the only way the private half is reached on a fresh
  VM. Nothing in the test suite covers that: `gh` is never logged in inside a
  container.
- The fallback rc files exist because `bootstrap-system.sh` makes zsh the login
  shell long before the real ones can be cloned. They are copied, carry a
  `claude-sandbox fallback` marker line so a re-run can tell its own file from
  a stock one, and the dotfiles installer moves them aside to `<name>.backup`
  when it takes over.
- `provision.sh` lends the user a `NOPASSWD` sudoers drop-in for the length of
  the run only, removed by an EXIT trap, because the fresh password would
  otherwise expire out of sudo's timestamp partway through a long apt run.
- Service management is skipped where `/run/systemd/system` is absent, so
  `systemctl restart docker`, the `ssh` restart and `enable --now tailscaled`
  are the one part no container covers.

## Conventions

Every script is `set -euo pipefail`, idempotent, and opens with a comment
explaining *why* it exists and what would break if it ran elsewhere in the
order. Match that: the comments here carry reasoning, not description.

Nothing may depend on the account being named `claude` — paths go through
`$HOME` or `getent passwd`, and the sshd drop-in's `__USER__` placeholder is
substituted at install time.

Debian only. Anything else is refused up front, and the docker and tailscale
repository URLs are built from `VERSION_CODENAME` in `/etc/os-release`.

**Nothing personal ships from this repo.** It is public; the shell, the
prompt, the runtimes and the Claude Code configuration all live in the private
`claude-dotfiles`, and `assert.sh` fails if a `home/` or `.claude` path appears
here. `install.sh` clones that repo and runs its installer, but only with an
authenticated `gh` — and a clone that fails is a message, not a failed run,
since nobody but the owner can read it.

## Credentials

The account password is generated by `provision.sh` and printed once at the end
of the run, never stored.

The commit-signing key is the opposite: pasted into `keys.sh`, the same key on
every VM, so one registration with GitHub covers all of them. `keys.sh` derives
the `.pub` with `ssh-keygen -y`, which is also how it validates the paste.

`~/.ssh/allowed_signers` — the trust list, not the key — is written by
`keys.sh` rather than tracked here, since it is derived from a private key and
deriving it locally is free. It also removes the symlink earlier versions
installed, so an upgraded box does not write back into tracked content.

`register-signing-key.sh` puts the public half on the GitHub account. It needs
the `write:ssh_signing_key` scope, which is separate from `admin:public_key`
and which `gh auth login` does not request. Every blocker — no key, no `gh`,
not logged in, no scope — exits 0 with a message, because on a fresh VM all of
them are true when `setup.sh` runs and the run has to carry on. `install.sh`
and `keys.sh` both call it: the first because it is the script that runs once
`gh` works, the second because pasting a key there orphans the one already
registered.

## Environment knobs

`CLAUDE_SANDBOX_USER`, `CLAUDE_SANDBOX_REPO`, `CLAUDE_SANDBOX_DIR`,
`CLAUDE_DOTFILES_REPO`, `CLAUDE_DOTFILES_DIR`, `SSH_PUBLIC_KEYS` (headless key
handoff to `provision.sh`), `FORCE_HARDEN`, `KEEP`.
