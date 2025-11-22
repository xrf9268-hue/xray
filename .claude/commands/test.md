---
description: "Run the complete test suite (fmt, lint, unit tests)"
hints: "Use this to verify code quality before committing"
---

Run the complete test suite for this project following the mandatory standards (CLAUDE.md):

## Step 1: Format Check
```bash
make fmt
```

Report if any files were reformatted.

## Step 2: Linting
```bash
make lint
```

Report:
- Total shellcheck issues found
- Breakdown by severity (error/warning)
- Top 3 most common issues
- Files with issues (file:line format)

## Step 3: Unit Tests
```bash
make test-unit
```

Report:
- Total tests run
- Passed/failed/skipped counts
- Test execution time
- Any failing test details

## Summary

Provide a final summary:
- ✓ All checks passed / ✗ N checks failed
- Total execution time
- Suggested next steps if failures exist

If all tests pass, suggest running `git commit` workflow.
