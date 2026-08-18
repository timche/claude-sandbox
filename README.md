# Claude Sandbox

[![test](https://github.com/timche/claude-sandbox/actions/workflows/test.yml/badge.svg)](https://github.com/timche/claude-sandbox/actions/workflows/test.yml)

Provisioning for a Debian VM dedicated to running Claude Code, which is why the
machine runs it with `bypassPermissions` — there is nothing on it worth
guarding Claude from.

As root, which is how a VM arrives from a provider:

```sh
curl -fsSL https://raw.githubusercontent.com/timche/claude-sandbox/main/provision.sh | bash
```

That is the only entry point. It creates the account, clones this repo and runs
`setup.sh` as that user, which builds the machine and then fetches the private
`claude-dotfiles` — the shell, the prompt, the runtimes and `~/.claude`.

Afterwards: `claude` then `/login`, and log out and back in for the docker
group and the login shell.

`CLAUDE.md` has the details: the order the scripts run in, the constraints that
are not obvious from reading them, and how to test.
