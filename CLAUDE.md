# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Shell provisioning for a Debian VM dedicated to running Claude Code. No build,
no lint, no package manager — the deliverable is the scripts themselves plus
the dotfiles they link.

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

`assert.sh` pins the Node major (`^v24\.`) because `install.sh` runs
`fnm install --lts`. That pin needs bumping whenever the LTS line moves.

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
  repos, login shell), `install.sh` (no sudo, user tooling and the symlinks),
  `keys.sh`, `harden-ssh.sh`.

`home/` mirrors `$HOME` and `system/` mirrors `/etc`. `install.sh` symlinks out
of `home/`, so the clone has to stay on disk — it is not a scratch copy.

### Ordering constraints that are not obvious

- `harden-ssh.sh` runs **last** because it turns password logins off. It
  refuses when the target user has no `authorized_keys`, since hardening a
  fresh VM before a key exists leaves it reachable only from the provider's
  console. `FORCE_HARDEN=true` overrides.
- `keys.sh` and the interactive prompts in `provision.sh` are gated on
  `[ -t 0 ]`. Without a terminal they skip rather than block, which is what
  keeps `setup.sh` usable from CI. If `keys.sh` ever stops bailing out
  headlessly, the suite hangs instead of failing.
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

**Nothing under `~/.claude` ships from this repo.** It is public; the Claude
Code configuration lives in the private `claude-dotfiles` repo, and
`assert.sh` fails if `home/.claude` appears here.

## Credentials

Both are generated on the box and printed once at the end of the run, never
stored:

- the commit-signing key, by `keys.sh` (`ssh-keygen -t ed25519` into
  `~/.ssh/git-signing`)
- the account password, by `provision.sh`

A generated signing key means `home/.ssh/allowed_signers` is a per-machine
list appended to by hand, not a single tracked key. `keys.sh` prints the line
and the two places it has to go (GitHub, and that file) but writes to neither.
Until both are done, `git log --format='%G?'` reports `N`.

## Environment knobs

`CLAUDE_SANDBOX_USER`, `CLAUDE_SANDBOX_REPO`, `CLAUDE_SANDBOX_DIR`,
`SSH_PUBLIC_KEYS` (headless key handoff to `provision.sh`), `FORCE_HARDEN`,
`KEEP`.
