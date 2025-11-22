---
description: "Perform code quality audit following AGENTS.md standards"
hints: "Checks code reuse, documentation, security, testing, and standards compliance"
---

Perform a comprehensive code quality audit following AGENTS.md guidelines:

## 1. Code Reuse Analysis

Search for duplicated logic across the codebase:

**Threshold**: Functions used 2+ times should be extracted to shared libraries

**Check**:
- [ ] lib/ modules for duplicated utility functions
- [ ] modules/ for duplicated helper logic
- [ ] services/ for duplicated domain-specific code
- [ ] Standalone scripts for inline implementations of shared functions

**Report**:
- Duplicated functions found (with file:line references)
- Suggested extraction locations (lib/core.sh, modules/io.sh, etc.)
- Estimated lines of code reduction

## 2. Documentation Audit

Verify ShellDoc compliance (see AGENTS.md "Function Documentation Standard"):

**Check**:
- [ ] All public functions in lib/ have ShellDoc comments
- [ ] All public functions in modules/ have ShellDoc comments
- [ ] All public functions in services/ have ShellDoc comments
- [ ] Security-sensitive functions have Security section with CWE references
- [ ] Complex functions have Examples section

**Report**:
- Undocumented functions (file:line:function)
- Missing sections (Arguments, Returns, Security, etc.)
- Suggested documentation improvements

## 3. Security Audit

Check for common security issues (see AGENTS.md "Security Best Practices"):

**CWE Checks**:
- [ ] CWE-78: Command Injection (unquoted variables in command execution)
- [ ] CWE-362: TOCTOU (race conditions in file operations)
- [ ] CWE-494: Download without integrity check
- [ ] CWE-283: Unverified ownership (lock file permissions)
- [ ] CWE-59: Improper link resolution (predictable temp files)

**Report**:
- Security issues found (severity: High/Medium/Low)
- CWE reference and explanation
- File:line references
- Suggested fixes

## 4. Testing Coverage

Identify untested functions:

**Check**:
- [ ] Compare functions in lib/ vs tests/unit/lib/
- [ ] Compare functions in modules/ vs tests/unit/modules/
- [ ] Compare functions in services/ vs tests/unit/services/

**Report**:
- Test coverage percentage (approximate)
- Untested functions (file:function)
- Priority for testing (critical functions first)
- Suggested test cases

## 5. Standards Compliance

Verify adherence to AGENTS.md coding standards:

**Check**:
- [ ] All files use `set -euo pipefail` (where applicable)
- [ ] All logging uses `core::log` (not `echo`)
- [ ] All atomic writes use `io::atomic_write`
- [ ] All lock operations use `core::with_flock`
- [ ] All domain validation uses `validators::domain`
- [ ] All shortId generation uses `xray::generate_shortid`

**Report**:
- Non-compliant patterns (file:line)
- Suggested replacements
- Estimated refactoring effort

## Summary Report

Provide executive summary:

**Code Reuse**: N duplications found, M lines reducible
**Documentation**: N functions missing docs
**Security**: N issues (High: X, Medium: Y, Low: Z)
**Testing**: N% coverage, M untested functions
**Standards**: N violations found

**Priority Actions** (ranked by impact):
1. [High] Fix security issue X (CWE-Y)
2. [High] Document critical function Z
3. [Medium] Extract duplicated logic from A, B
4. ...

**Estimated Effort**: X hours
