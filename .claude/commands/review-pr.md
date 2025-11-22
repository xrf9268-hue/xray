---
description: "Review a pull request following project standards"
hints: "Usage: /review-pr <number>. Checks code quality, security, testing, and documentation."
---

Review pull request #$1 following xray-fusion standards:

## Step 1: Fetch PR Information

```bash
# Get PR details (if gh CLI available)
gh pr view $1

# OR ask user to provide:
# - PR title and description
# - Branch name
# - Files changed
```

## Step 2: Checkout and Examine

```bash
# Checkout PR branch (if gh CLI available)
gh pr checkout $1

# OR manually:
git fetch origin pull/$1/head:pr-$1
git checkout pr-$1

# Review changes
git diff main...HEAD
git log main..HEAD --oneline
```

## Step 3: Code Quality Review

### 3.1 Coding Standards (AGENTS.md)

Check:
- [ ] Functions follow `namespace::function` naming
- [ ] Variables: lowercase local, UPPER_SNAKE for exported
- [ ] Indentation: 2 spaces (verify with `make fmt`)
- [ ] All files use `set -euo pipefail` (where applicable)
- [ ] Logging uses `core::log` (not `echo`)
- [ ] Atomic writes use `io::atomic_write`
- [ ] Error handling on all critical paths

### 3.2 Code Reuse (AGENTS.md)

Check:
- [ ] No duplicated logic (threshold: 2+ uses)
- [ ] Proper use of shared utilities (core::, io::, validators::, xray::)
- [ ] Standalone scripts use lightweight compatible versions
- [ ] No reinventing existing functions

### 3.3 Function Documentation (AGENTS.md)

Check:
- [ ] All public functions have ShellDoc comments
- [ ] Arguments documented with type and requirement
- [ ] Returns section documents all exit codes
- [ ] Security section for security-sensitive functions
- [ ] Examples for complex functions

## Step 4: Security Review

Check for CWE issues (see AGENTS.md "Security Best Practices"):

- [ ] **CWE-78**: Command injection (unquoted variables in eval, system calls)
- [ ] **CWE-362**: TOCTOU race conditions (file operations without locking)
- [ ] **CWE-494**: Download without integrity verification
- [ ] **CWE-283**: Unverified ownership (lock files, shared resources)
- [ ] **CWE-59**: Predictable temp file names (use mktemp with XXXXXX)
- [ ] **CWE-20**: Input validation (domain, port, version parameters)

Report any security issues with:
- CWE reference and severity
- File:line location
- Suggested fix

## Step 5: Testing Review

### 5.1 Test Coverage

Check:
- [ ] New functions have corresponding unit tests
- [ ] Tests cover happy path and error cases
- [ ] Tests verify all documented exit codes
- [ ] Tests validate security properties (if applicable)

### 5.2 Run Tests

```bash
make fmt           # Should pass
make lint          # Should pass
make test-unit     # Should pass
```

Report:
- Test results (passed/failed/skipped)
- Code coverage (approximate)
- Missing test cases

## Step 6: Documentation Review

Check:
- [ ] CLAUDE.md updated if architectural change (ADR added)
- [ ] AGENTS.md updated if new coding standard
- [ ] .claude/README.md updated if new hooks/commands
- [ ] Function documentation complete (ShellDoc)
- [ ] Commit messages follow project conventions

## Step 7: Review Summary

Provide comprehensive review:

### Summary of Changes
- Brief description of what the PR does
- Key files modified
- Lines added/removed

### Code Quality Assessment
- ✓ Strengths: What's done well
- ⚠ Minor Issues: Non-blocking improvements
- ✗ Blocking Issues: Must be fixed before merge

### Security Assessment
- Security issues found (if any) with CWE references
- Recommended fixes

### Testing Assessment
- Test coverage status
- Missing tests (if any)
- Test results

### Documentation Assessment
- Documentation completeness
- Suggested improvements

### Approval Status

Choose one:
- **✅ APPROVE**: Code meets all standards, ready to merge
- **💬 COMMENT**: Suggestions for improvement, not blocking
- **🔄 REQUEST CHANGES**: Blocking issues must be addressed

### Action Items
1. [Blocking] Fix security issue CWE-X in file:line
2. [Blocking] Add unit tests for function Y
3. [Optional] Consider refactoring Z for better readability
4. ...

### Specific Feedback

Provide file:line specific comments:
- file.sh:123: Consider using `io::atomic_write` instead of `cat > file`
- lib/core.sh:456: Missing ShellDoc documentation
- tests/unit/test_foo.bats:789: Add test for error case

## Step 8: Post-Review Actions

```bash
# Return to original branch
git checkout -

# If approved, suggest merge command
# If changes requested, wait for author to address feedback
```
