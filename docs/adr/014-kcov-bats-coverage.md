# ADR-014: kcov Coverage for Bash with bats-core

**Date**: 2026-03-03
**Status**: Accepted

## Problem

Shell coverage with kcov and bats-core is unreliable in CI:

1. **Prebuilt kcov binaries break** — they link against specific shared library versions (e.g., `libopcodes-2.38`) that may not match the GitHub Actions runner image. This causes silent failures or missing coverage.
2. **kcov exits non-zero with bats** — both tools use the bash `DEBUG` trap. kcov uses it for line-level instrumentation; bats-core uses it for test assertions. The conflict causes kcov to return exit code 1 even when all tests pass.

## Decision

1. **Build kcov from source** in CI rather than downloading prebuilt binaries. Cache the build artifact (`~/.local/bin/kcov`) keyed on the kcov version to avoid rebuilding on every run.
2. **Tolerate kcov's non-zero exit code** by capturing it (`|| kcov_rc=$?`) and proceeding to parse `coverage.json` in a separate step. The coverage gate decision is based on the JSON data, not kcov's exit code.
3. **Avoid Python f-string backslashes** in inline CI scripts — Ubuntu 22.04 ships Python 3.10 which does not support backslash escapes inside f-string expressions (added in Python 3.12). Use `%`-formatting or variable assignment instead.

## Rationale

- Building from source guarantees ABI compatibility with the runner's libraries.
- The DEBUG trap conflict is a known upstream issue between kcov and bats-core. Despite the non-zero exit, kcov still produces valid coverage data (confirmed: 65.68% across 35 source files).
- The coverage gate (`coverage.json` threshold check) is the authoritative pass/fail signal, not kcov's exit code.

## Impact

- First CI run after cache expiry takes ~40s extra to build kcov from source.
- Coverage timeout increased from 20 to 30 minutes to accommodate the build step.
- `test_github_metadata.bats` updated to expect `coverage:30` timeout.
