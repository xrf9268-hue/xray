# Agent Session Template

Use this template when starting a new Codex or agent session for this
repository. It is designed to stay portable across Windows WSL, macOS, host
shell workflows, and optional `thin-devbox-shell` usage.

## Goal

Continue work on this repository without assuming a machine-specific path or a
single shell implementation.

## Startup Template

```text
You are continuing work in the xray repository.

Start by:
1. Reading AGENTS.md, CONTRIBUTING.md, Makefile, tests/README.md,
   scripts/e2e/install-lifecycle-smoke.sh, and .github/workflows/test.yml.
2. Fetching origin/main.
3. Creating a new git worktree and a new codex/* branch unless the user
   explicitly wants the current branch.
4. Choosing the execution mode that best fits the task:
   - host shell (default baseline)
   - optional thin-devbox-shell for a reproducible shell layer

Environment rules:
- Do not assume devbox is required.
- Do not assume Docker is available inside a devbox container.
- Run Docker lifecycle and online-install tests from fresh host Docker
  containers.
- Keep the workflow valid on Windows via WSL and on macOS local shells.

Task goals may include one or more of:
- add or update a feature
- fix a bug
- add unit tests
- extend end-to-end or lifecycle coverage
- validate online installation, reinstall, uninstall, and reinstall again

Minimum process:
1. Inspect the current code and tests before editing.
2. Make targeted changes.
3. Run validation relevant to the changed area.
4. If Docker install flows changed, run fresh-container lifecycle tests.
5. Push the branch and monitor GitHub Actions until required checks finish.
6. If CI fails, fix the issue, rerun local validation, and push again until CI
   passes.

Report back with:
- summary of changes
- local validation performed
- Docker lifecycle / online-install validation performed
- GitHub Actions run URL and final status
- remaining risks or follow-ups
```

## Validation Matrix

Use the smallest set that matches the change:

- Shell logic and libraries: `make fmt && make lint && make test-unit`
- Changed bats files: run the specific bats file, then `make test-unit`
- Broader behavior changes: `make test`
- Lifecycle script changes: `bash scripts/e2e/install-lifecycle-smoke.sh`
- Online install changes: fresh Docker container install -> reinstall ->
  uninstall -> reinstall

## Notes

- Prefer scripts and `make` targets over repeating long hand-written procedures.
- When `thin-devbox-shell` is used, treat it only as an execution layer. Keep
  repository workflow decisions in this repository's docs and scripts.
- Keep prompts short and rely on repository docs for the stable rules.
- Update this template if the repository workflow changes materially.
