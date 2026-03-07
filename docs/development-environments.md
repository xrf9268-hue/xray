# Development Environments

This repository supports multiple development modes. The project workflow must
remain usable even when the optional shared shell layer is not available.

## Supported Modes

### Host Shell (default)

Use the host shell as the baseline workflow:

- Linux or macOS local shell
- Windows through a WSL Linux distribution

Use this mode when:

- You need direct access to host Docker
- You are iterating on installation or lifecycle tests
- You want the least moving parts

## Optional Shared Shell: thin-devbox-shell

[`thin-devbox-shell`](https://github.com/xrf9268-hue/thin-devbox-shell) is an
optional, thin Docker shell that can provide a reproducible command-line
environment for the current repository or worktree.

Use it when:

- You want a stable shell with common CLI tools
- You are switching between Windows WSL and macOS and want a similar shell
- The task only needs the repository workspace plus standard CLI tooling

Do not rely on it for:

- Project runtime installation
- Project dependency bootstrap
- Docker-in-Docker assumptions
- Long-lived service orchestration

Treat it as a consumer-side shell contract only. This repository still owns its
setup, validation, CI, and agent workflow rules, and it must still document and
support host-shell development directly.

## Platform Notes

### Windows

- Prefer the WSL Linux filesystem for active worktrees.
- Open the repository or worktree from its WSL path in Codex.
- Run host Docker commands from WSL when validating lifecycle and online
  installation flows.

### macOS

- Use a local shell in the checked-out repository or worktree.
- Run host Docker commands from the same working copy.

## Task-to-Environment Guidance

### Good fit for host shell

- Branch and worktree management
- Docker lifecycle smoke tests
- Online install / reinstall / uninstall validation
- CI log triage and follow-up fixes

### Good fit for thin-devbox-shell

- General repository exploration
- Formatting and linting
- Unit test execution when the task does not require host Docker
- Reproducible shell access across machines

## Worktree Guidance

When another task is already in flight, create a new worktree from `origin/main`
and a new `codex/*` branch before making changes.

Example:

```bash
git fetch origin
git worktree add -b codex/my-task ../xray-my-task origin/main
cd ../xray-my-task
```

## Docker Test Guidance

- Use fresh containers for lifecycle and online-install tests.
- Do not reuse the container used for development shell access.
- Treat online-install validation as a host Docker workflow even if normal
  editing happens inside `devbox`.
