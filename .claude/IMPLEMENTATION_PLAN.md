# Claude Code Hooks Implementation Plan

**Project**: xray-fusion
**Date**: 2025-11-22
**Feature Branch**: `claude/research-claude-hooks-011YvSkWHWyS17mbdfeTivKr`

## Overview

This document outlines a phased approach to implementing Claude Code hooks following official documentation and best practices.

**Official Documentation References**:
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)

---

## Phase 1: PostToolUse Hook (Auto-Format/Lint)

**Priority**: HIGH (⭐⭐⭐⭐⭐)
**Estimated Time**: 2-3 hours
**Status**: Pending

### Objectives

1. ✅ Automatically format shell scripts after Edit/Write operations
2. ✅ Automatically lint shell scripts with shellcheck
3. ✅ Provide non-blocking feedback on code quality
4. ✅ Reduce pre-commit check failures

### Tasks

#### 1.1 Create PostToolUse Hook Script

**File**: `.claude/scripts/format-and-lint-shell.sh`

**Requirements** (per official docs):
- ✅ Read hook input from stdin (JSON format)
- ✅ Extract file path from `params.file_path` or `params.path`
- ✅ Validate file extension (`.sh` files only)
- ✅ Sequential processing (format → lint, NOT parallel)
- ✅ Non-blocking exit codes (0 or 1, NEVER block continuation)
- ✅ Graceful degradation if tools missing
- ✅ Minimal output (use `suppressOutput: true` when appropriate)

**Best Practices**:
- Use `set -euo pipefail` for strict error handling
- Check `jq` availability (required for JSON parsing)
- Show one-time warnings for missing tools (use `/tmp/.tool-warning-shown` flags)
- Exit 0 for success or missing tools (non-blocking)
- Exit 1 for lint issues (still non-blocking, just reports)

**Implementation**:
```bash
#!/usr/bin/env bash
##
# PostToolUse Hook: Auto-format and lint shell scripts
#
# Official Docs: https://code.claude.com/docs/en/hooks#posttooluse
#
# Triggered: After Edit/Write operations on shell scripts
# Actions:
#   1. Format with shfmt (project standard: -i 2 -bn -ci -sr -kp)
#   2. Lint with shellcheck (warning level, exclude SC2250)
#
# Exit Codes:
#   0 - Success or tools unavailable (non-blocking)
#   1 - Linting issues detected (non-blocking, reports only)
#
# Security:
#   - Validates file existence before processing (prevent TOCTOU)
#   - Only processes .sh files (prevent unintended execution)
##

set -euo pipefail

# Check jq availability (required for JSON parsing)
if ! command -v jq >/dev/null 2>&1; then
  echo '{"suppressOutput": true}' >&2
  exit 0
fi

# Read hook input from stdin (official format)
# Example: {"params":{"file_path":"/path/to/file.sh"},"tool":"Edit"}
input=$(cat)

# Extract file path (try both params.file_path and params.path)
file=$(echo "${input}" | jq -r '.params.file_path // .params.path // empty')

# Validate file path exists
if [[ -z "${file}" ]]; then
  echo '{"suppressOutput": true}' >&2
  exit 0
fi

# Only process shell scripts (.sh extension or install.sh)
if [[ ! "${file}" =~ \.sh$ ]] && [[ "${file}" != *"/install.sh" ]]; then
  echo '{"suppressOutput": true}' >&2
  exit 0
fi

# Verify file exists (prevent TOCTOU - CWE-362)
if [[ ! -f "${file}" ]]; then
  echo '{"suppressOutput": true}' >&2
  exit 0
fi

echo "[PostToolUse] Processing shell script: ${file}" >&2

# PHASE 1: Format with shfmt (MUST run before lint)
# Official shfmt flags:
#   -i 2    : 2-space indentation
#   -bn     : Binary ops like && and | may start a line
#   -ci     : Switch cases are indented
#   -sr     : Redirect operators are followed by a space
#   -kp     : Keep column alignment padding
if command -v shfmt >/dev/null 2>&1; then
  # Check if formatting needed (dry-run with -d flag)
  if ! shfmt -i 2 -bn -ci -sr -kp -d "${file}" >/dev/null 2>&1; then
    echo "[PostToolUse] Formatting ${file}..." >&2
    if shfmt -i 2 -bn -ci -sr -kp -w "${file}" 2>&1; then
      echo "[PostToolUse] ✓ Formatted successfully" >&2
    else
      echo "[PostToolUse] ✗ Formatting failed" >&2
    fi
  else
    echo "[PostToolUse] ✓ Already formatted" >&2
  fi
else
  # Show one-time warning
  if [[ ! -f /tmp/.shfmt-warning-shown ]]; then
    echo "[PostToolUse] ⚠ shfmt not found - install via SessionStart hook" >&2
    touch /tmp/.shfmt-warning-shown
  fi
fi

# PHASE 2: Lint with shellcheck (MUST run after format)
# Official shellcheck flags:
#   -S warning : Show warnings and errors (exclude info/style)
#   -e SC2250  : Exclude specific rule (project-specific)
if command -v shellcheck >/dev/null 2>&1; then
  echo "[PostToolUse] Linting ${file}..." >&2

  # Run shellcheck (capture output)
  if output=$(shellcheck -S warning -e SC2250 "${file}" 2>&1); then
    echo "[PostToolUse] ✓ No linting issues" >&2
    exit 0
  else
    # Count issues (lines starting with "In <file> line N:")
    issue_count=$(echo "${output}" | grep -c "^In.*line" || echo "0")
    echo "[PostToolUse] ✗ Found ${issue_count} linting issue(s):" >&2
    echo "${output}" >&2
    echo "" >&2
    echo "[PostToolUse] How to fix:" >&2
    echo "  - Run 'make lint' for detailed analysis" >&2
    echo "  - Disable specific rules: # shellcheck disable=SC####" >&2
    echo "  - See AGENTS.md for coding standards" >&2

    # Exit 1 (non-blocking, just reports issues)
    exit 1
  fi
else
  # Show one-time warning
  if [[ ! -f /tmp/.shellcheck-warning-shown ]]; then
    echo "[PostToolUse] ⚠ shellcheck not found - install via SessionStart hook" >&2
    touch /tmp/.shellcheck-warning-shown
  fi
  exit 0
fi
```

**Checklist**:
- [ ] Script created at `.claude/scripts/format-and-lint-shell.sh`
- [ ] Executable permissions set (`chmod +x`)
- [ ] ShellDoc documentation complete
- [ ] Follows AGENTS.md shell programming best practices
- [ ] No trap usage (utility function, not main script)
- [ ] Proper error handling on all paths

#### 1.2 Update Hook Configuration

**File**: `.claude/settings.json`

**Requirements** (per official docs):
- ✅ Use regex matcher `"Edit|Write"` to trigger on both tools
- ✅ Set reasonable timeout (15 seconds recommended)
- ✅ Use `$CLAUDE_PROJECT_DIR` for portable paths
- ✅ Single hook per matcher (avoid race conditions)

**Implementation**:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/session-start.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/format-and-lint-shell.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

**Best Practices Applied**:
- ✅ **Single hook per matcher**: Format+lint in ONE script (not two parallel hooks)
- ✅ **Timeout set**: 15 seconds prevents hanging on large files
- ✅ **Portable path**: `$CLAUDE_PROJECT_DIR` works across environments
- ✅ **Regex matcher**: `Edit|Write` catches both edit and create operations

**Checklist**:
- [ ] settings.json updated with PostToolUse configuration
- [ ] JSON syntax validated (`jq . .claude/settings.json`)
- [ ] Timeout set to 15 seconds
- [ ] Matcher uses regex (Edit|Write)

#### 1.3 Testing

**Test Cases**:

**Test 1.3.1: Unformatted Script**
```bash
# Create unformatted test file
cat > /tmp/test-unformatted.sh << 'EOF'
#!/usr/bin/env bash
if [ -f file ];then
echo "test"
fi
EOF

# Test hook manually
echo '{"params":{"file_path":"/tmp/test-unformatted.sh"},"tool":"Edit"}' | \
  .claude/scripts/format-and-lint-shell.sh

# Verify: File should be formatted with proper spacing
cat /tmp/test-unformatted.sh
# Expected:
# #!/usr/bin/env bash
# if [ -f file ]; then
#   echo "test"
# fi
```

**Test 1.3.2: Lint Issues**
```bash
# Create script with shellcheck issues
cat > /tmp/test-lint-issues.sh << 'EOF'
#!/usr/bin/env bash
file=$1
rm -rf $file  # Unquoted variable
EOF

# Test hook
echo '{"params":{"file_path":"/tmp/test-lint-issues.sh"},"tool":"Write"}' | \
  .claude/scripts/format-and-lint-shell.sh

# Expected output:
# [PostToolUse] Processing shell script: /tmp/test-lint-issues.sh
# [PostToolUse] ✓ Already formatted
# [PostToolUse] Linting /tmp/test-lint-issues.sh...
# [PostToolUse] ✗ Found 1 linting issue(s):
# In /tmp/test-lint-issues.sh line 3:
# rm -rf $file  # Unquoted variable
#        ^----^ SC2086: Double quote to prevent globbing...
```

**Test 1.3.3: Already Clean Script**
```bash
# Create properly formatted script
cat > /tmp/test-clean.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

main() {
  local file="${1}"
  echo "Processing: ${file}"
}

main "$@"
EOF

# Test hook
echo '{"params":{"file_path":"/tmp/test-clean.sh"},"tool":"Edit"}' | \
  .claude/scripts/format-and-lint-shell.sh

# Expected output:
# [PostToolUse] Processing shell script: /tmp/test-clean.sh
# [PostToolUse] ✓ Already formatted
# [PostToolUse] Linting /tmp/test-clean.sh...
# [PostToolUse] ✓ No linting issues
```

**Test 1.3.4: Non-Shell File (Should Skip)**
```bash
# Test with non-shell file
echo '{"params":{"file_path":"/tmp/test.txt"},"tool":"Write"}' | \
  .claude/scripts/format-and-lint-shell.sh

# Expected: Silent exit (suppressOutput: true)
echo $?  # Should be 0
```

**Test 1.3.5: Missing Tools (Graceful Degradation)**
```bash
# Temporarily hide shfmt/shellcheck
mkdir /tmp/bin-backup
mv ~/.local/bin/shfmt /tmp/bin-backup/ 2>/dev/null || true
mv ~/.local/bin/shellcheck /tmp/bin-backup/ 2>/dev/null || true

# Test hook
echo '{"params":{"file_path":"/tmp/test-clean.sh"},"tool":"Edit"}' | \
  .claude/scripts/format-and-lint-shell.sh

# Expected output:
# [PostToolUse] Processing shell script: /tmp/test-clean.sh
# [PostToolUse] ⚠ shfmt not found - install via SessionStart hook
# [PostToolUse] ⚠ shellcheck not found - install via SessionStart hook

# Restore tools
mv /tmp/bin-backup/* ~/.local/bin/ 2>/dev/null || true
rmdir /tmp/bin-backup 2>/dev/null || true
```

**Test 1.3.6: Integration Test (Real Edit)**
```bash
# Edit a real project file
# This test requires Claude Code session

# 1. Edit bin/xrf (add a space somewhere)
# 2. Observe hook output in session
# 3. Verify file is auto-formatted
# 4. Verify no lint issues reported
```

**Checklist**:
- [ ] All 6 test cases pass
- [ ] Hook exits 0 for success/missing tools
- [ ] Hook exits 1 for lint issues (non-blocking)
- [ ] Formatting applied correctly
- [ ] Lint issues reported with actionable guidance
- [ ] Non-shell files skipped silently
- [ ] Missing tools handled gracefully

#### 1.4 Phase 1 Completion Criteria

- [ ] Script created and executable
- [ ] settings.json updated
- [ ] All 6 tests pass
- [ ] Manual integration test successful
- [ ] No regression in existing SessionStart hook

---

## Phase 2: Stop Hook (Git Status Check)

**Priority**: HIGH (⭐⭐⭐⭐)
**Estimated Time**: 1-2 hours
**Status**: Pending

### Objectives

1. ✅ Prevent ending sessions with uncommitted changes
2. ✅ Warn about unpushed commits
3. ✅ Remind to update documentation (CLAUDE.md/AGENTS.md)
4. ✅ Enforce clean git hygiene

### Tasks

#### 2.1 Create Stop Hook Script

**File**: `.claude/scripts/stop-hook-git-check.sh`

**Requirements** (per official docs):
- ✅ Read hook input from stdin (JSON format)
- ✅ Exit 0 for clean state (allow stop)
- ✅ Exit 2 for blocking scenarios (uncommitted changes)
- ✅ Provide actionable error messages
- ✅ Output JSON with `approved` field

**Best Practices**:
- Block ONLY for uncommitted changes (hard blocker)
- Warn (but allow) for unpushed commits (soft reminder)
- Suggest documentation updates after significant work
- Show clear remediation steps

**Implementation**:
```bash
#!/usr/bin/env bash
##
# Stop Hook: Git status verification
#
# Official Docs: https://code.claude.com/docs/en/hooks#stop
#
# Triggered: Before Claude Code session ends
# Actions:
#   1. Check for uncommitted changes (BLOCKS if found)
#   2. Check for unpushed commits (WARNS if found)
#   3. Remind to update CLAUDE.md/AGENTS.md if needed
#
# Exit Codes:
#   0 - Clean git state, allow stop
#   2 - Uncommitted changes detected, block stop
#
# Output:
#   JSON with approved: true/false and optional reason
##

set -euo pipefail

# Navigate to project directory
cd "${CLAUDE_PROJECT_DIR:-/home/user/xray}"

echo "[Stop] Checking git status..." >&2

# BLOCKER 1: Uncommitted changes (modified, added, deleted files)
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  uncommitted_files=$(git status --short)

  echo "[Stop] ✗ Uncommitted changes detected:" >&2
  echo "${uncommitted_files}" >&2
  echo "" >&2
  echo "[Stop] Please commit or stash changes before ending session:" >&2
  echo "  # Commit changes:" >&2
  echo "  git add -A" >&2
  echo "  git commit -m 'Your descriptive message'" >&2
  echo "" >&2
  echo "  # OR stash changes:" >&2
  echo "  git stash push -m 'WIP: description'" >&2
  echo "" >&2

  # Output JSON (official format)
  echo '{"approved": false, "reason": "Uncommitted changes detected - commit or stash before stopping"}' >&2
  exit 2  # Block stopping
fi

# Check for untracked files
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  untracked_files=$(git ls-files --others --exclude-standard | head -5)
  untracked_count=$(git ls-files --others --exclude-standard | wc -l)

  echo "[Stop] ⚠ ${untracked_count} untracked file(s) detected:" >&2
  echo "${untracked_files}" >&2
  [[ ${untracked_count} -gt 5 ]] && echo "... and $((untracked_count - 5)) more" >&2
  echo "" >&2
  echo "[Stop] Consider tracking these files:" >&2
  echo "  git add <file>  # Add specific file" >&2
  echo "  git add .       # Add all files" >&2
  echo "  # OR add to .gitignore if not needed" >&2
  echo "" >&2

  # Warn but don't block (untracked files are not critical)
fi

# WARNING 1: Unpushed commits
if git status | grep -q "Your branch is ahead"; then
  current_branch=$(git branch --show-current)
  ahead_count=$(git rev-list --count origin/"${current_branch}"..HEAD 2>/dev/null || echo "?")

  echo "[Stop] ⚠ ${ahead_count} unpushed commit(s) on branch '${current_branch}'" >&2
  echo "[Stop] Consider pushing to remote:" >&2
  echo "  git push -u origin ${current_branch}" >&2
  echo "" >&2
fi

# REMINDER: Documentation updates (heuristic: 3+ commits in last hour)
commit_count=$(git log --oneline --since='1 hour ago' | wc -l)
if [[ ${commit_count} -ge 3 ]]; then
  echo "[Stop] 💡 Reminder: You made ${commit_count} commits in the last hour" >&2
  echo "[Stop] Consider updating project documentation:" >&2
  echo "  - CLAUDE.md: Add ADR for architectural decisions" >&2
  echo "  - AGENTS.md: Update coding standards or best practices" >&2
  echo "  - .claude/README.md: Document new hooks or commands" >&2
  echo "" >&2
fi

# Clean git state - allow stop
echo "[Stop] ✓ Git status clean, safe to end session" >&2
echo '{"approved": true}' >&2
exit 0
```

**Checklist**:
- [ ] Script created at `.claude/scripts/stop-hook-git-check.sh`
- [ ] Executable permissions set (`chmod +x`)
- [ ] ShellDoc documentation complete
- [ ] Blocks ONLY for uncommitted changes
- [ ] Warns (but allows) for unpushed commits
- [ ] JSON output format correct

#### 2.2 Update Hook Configuration

**File**: `.claude/settings.json`

**Requirements** (per official docs):
- ✅ Empty matcher `""` (applies to all stop events)
- ✅ Set reasonable timeout (10 seconds recommended)
- ✅ Use `$CLAUDE_PROJECT_DIR` for portable paths

**Implementation**:
```json
{
  "hooks": {
    "SessionStart": [...],
    "PostToolUse": [...],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/stop-hook-git-check.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Best Practices Applied**:
- ✅ **Empty matcher**: Applies to all stop events (no filtering needed)
- ✅ **Timeout set**: 10 seconds (git operations are fast)
- ✅ **Blocking capability**: Exit 2 blocks session end (official behavior)

**Checklist**:
- [ ] settings.json updated with Stop configuration
- [ ] JSON syntax validated
- [ ] Timeout set to 10 seconds
- [ ] Matcher is empty string (applies to all)

#### 2.3 Testing

**Test Cases**:

**Test 2.3.1: Clean Git State (Should Allow)**
```bash
# Ensure clean state
git status  # Verify no changes

# Test hook
echo '{}' | .claude/scripts/stop-hook-git-check.sh

# Expected output:
# [Stop] Checking git status...
# [Stop] ✓ Git status clean, safe to end session
# {"approved": true}

# Verify exit code
echo $?  # Should be 0
```

**Test 2.3.2: Uncommitted Changes (Should Block)**
```bash
# Create uncommitted change
echo "test" >> /tmp/test-file.txt
git add /tmp/test-file.txt

# Test hook
echo '{}' | .claude/scripts/stop-hook-git-check.sh

# Expected output:
# [Stop] Checking git status...
# [Stop] ✗ Uncommitted changes detected:
# A  /tmp/test-file.txt
#
# [Stop] Please commit or stash changes before ending session:
#   git add -A
#   git commit -m 'Your descriptive message'
#   ...
# {"approved": false, "reason": "Uncommitted changes detected..."}

# Verify exit code
echo $?  # Should be 2 (blocking)

# Cleanup
git reset HEAD /tmp/test-file.txt
rm /tmp/test-file.txt
```

**Test 2.3.3: Untracked Files (Should Warn, Allow)**
```bash
# Create untracked file
echo "test" > untracked-file.txt

# Test hook
echo '{}' | .claude/scripts/stop-hook-git-check.sh

# Expected output:
# [Stop] Checking git status...
# [Stop] ⚠ 1 untracked file(s) detected:
# untracked-file.txt
#
# [Stop] Consider tracking these files:
#   git add <file>
#   ...
# [Stop] ✓ Git status clean, safe to end session
# {"approved": true}

# Verify exit code
echo $?  # Should be 0 (allows stop despite untracked files)

# Cleanup
rm untracked-file.txt
```

**Test 2.3.4: Unpushed Commits (Should Warn, Allow)**
```bash
# Create empty commit (won't push)
git commit --allow-empty -m "Test commit for Stop hook"

# Test hook
echo '{}' | .claude/scripts/stop-hook-git-check.sh

# Expected output:
# [Stop] Checking git status...
# [Stop] ⚠ 1 unpushed commit(s) on branch 'claude/research-...'
# [Stop] Consider pushing to remote:
#   git push -u origin claude/research-...
#
# [Stop] ✓ Git status clean, safe to end session
# {"approved": true}

# Verify exit code
echo $?  # Should be 0 (allows stop despite unpushed commits)

# Cleanup
git reset HEAD~1
```

**Test 2.3.5: Recent Commits (Should Remind, Allow)**
```bash
# Create 3+ commits in quick succession
git commit --allow-empty -m "Commit 1"
git commit --allow-empty -m "Commit 2"
git commit --allow-empty -m "Commit 3"

# Test hook
echo '{}' | .claude/scripts/stop-hook-git-check.sh

# Expected output:
# [Stop] Checking git status...
# [Stop] ⚠ 3 unpushed commit(s) on branch '...'
# ...
# [Stop] 💡 Reminder: You made 3 commits in the last hour
# [Stop] Consider updating project documentation:
#   - CLAUDE.md: Add ADR for architectural decisions
#   ...
# [Stop] ✓ Git status clean, safe to end session
# {"approved": true}

# Verify exit code
echo $?  # Should be 0

# Cleanup
git reset HEAD~3
```

**Checklist**:
- [ ] All 5 test cases pass
- [ ] Hook blocks ONLY for uncommitted changes (exit 2)
- [ ] Hook allows with warnings for other scenarios (exit 0)
- [ ] JSON output correct for both approved and blocked
- [ ] Remediation steps clear and actionable

#### 2.4 Phase 2 Completion Criteria

- [ ] Script created and executable
- [ ] settings.json updated
- [ ] All 5 tests pass
- [ ] Blocking behavior verified (uncommitted changes)
- [ ] Warning behavior verified (unpushed commits, untracked files)

---

## Phase 3: Custom Slash Commands

**Priority**: MEDIUM (⭐⭐⭐)
**Estimated Time**: 2-3 hours
**Status**: Pending

### Objectives

1. ✅ Create 5 essential slash commands for common workflows
2. ✅ Improve developer productivity
3. ✅ Standardize team workflows
4. ✅ Improve discoverability (`/help` lists all)

### Tasks

#### 3.1 Create Commands Directory

**Structure**:
```
.claude/
├── commands/
│   ├── test.md           # Run complete test suite
│   ├── lint-fix.md       # Auto-fix linting issues
│   ├── audit.md          # Code quality audit
│   ├── commit.md         # Create well-formatted commit
│   └── review-pr.md      # Review pull request
```

**Checklist**:
- [ ] Directory created at `.claude/commands/`
- [ ] 5 command files created
- [ ] Each file has YAML frontmatter with description

#### 3.2 Command: `/test`

**File**: `.claude/commands/test.md`

**Purpose**: Run complete test suite (fmt + lint + unit tests)

**Implementation**:
```markdown
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
```

**Checklist**:
- [ ] File created with frontmatter
- [ ] Description clear and concise
- [ ] Workflow follows CLAUDE.md standards
- [ ] Output format specified

#### 3.3 Command: `/lint-fix`

**File**: `.claude/commands/lint-fix.md`

**Purpose**: Auto-fix shellcheck linting issues

**Implementation**:
```markdown
---
description: "Auto-fix shellcheck linting issues"
hints: "Fixes common issues like unquoted variables, use of [[ ]] over [ ]"
---

Auto-fix linting issues in shell scripts following AGENTS.md standards:

## Step 1: Identify Issues
```bash
make lint
```

Parse output and categorize issues:
- **Auto-fixable**: Quoting, [[ ]] usage, local declarations
- **Requires review**: Logic errors, security issues
- **False positives**: May need shellcheck disable comments

## Step 2: Apply Automatic Fixes

For each auto-fixable issue:
1. Read the affected file
2. Apply the fix (quote variables, use [[ ]], etc.)
3. Verify syntax with `bash -n <file>`
4. Re-run `make lint` on the file

**Common Fixes**:
- SC2086: Quote variable → `"${var}"`
- SC2006: Use $() instead of backticks → `$(command)`
- SC2155: Separate declaration and assignment → Split into two lines
- SC2034: Unused variable → Remove or use underscore prefix `_var`

## Step 3: Document Justified Suppressions

For issues that cannot be auto-fixed but are intentional:
1. Add shellcheck disable comment with justification
2. Document in code why the warning is suppressed

Example:
```bash
# shellcheck disable=SC2086  # Word splitting intentional for glob expansion
rm -f $temp_files
```

## Step 4: Verification
```bash
make lint
```

Report:
- Issues fixed automatically
- Issues requiring manual review
- Suppressions added with justification

## Summary

- Original issue count: N
- Auto-fixed: N
- Suppressed with justification: N
- Remaining issues: N
- Next steps if issues remain
```

**Checklist**:
- [ ] File created with frontmatter
- [ ] Auto-fix logic defined
- [ ] Verification steps included
- [ ] Suppression guidelines follow AGENTS.md

#### 3.4 Command: `/audit`

**File**: `.claude/commands/audit.md`

**Purpose**: Code quality audit following AGENTS.md standards

**Implementation**:
```markdown
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
```

**Checklist**:
- [ ] File created with frontmatter
- [ ] All 5 audit categories defined
- [ ] CWE checks align with AGENTS.md
- [ ] Output format specified

#### 3.5 Command: `/commit`

**File**: `.claude/commands/commit.md`

**Purpose**: Create well-formatted git commit

**Implementation**:
```markdown
---
description: "Create a well-formatted git commit following project standards"
hints: "Analyzes changes and drafts commit message following xray-fusion conventions"
---

Create a git commit following xray-fusion standards (see CLAUDE.md and git instructions):

## Step 1: Review Changes

Run in parallel:
```bash
git status           # Show staged and unstaged files
git diff             # Show unstaged changes
git diff --cached    # Show staged changes
git log -5 --oneline # Show recent commit style
```

## Step 2: Analyze Changes

Categorize the nature of changes:
- **add**: Wholly new feature or functionality
- **update**: Enhancement to existing feature
- **fix**: Bug fix or correction
- **refactor**: Code restructuring without behavior change
- **test**: Add or update tests
- **docs**: Documentation updates
- **chore**: Build, CI/CD, tooling changes

## Step 3: Draft Commit Message

**Format** (imperative mood):
```
<type>: <concise subject line (50 chars max)>

[Optional body: detailed explanation, wrap at 72 chars]
[Focus on WHY rather than WHAT (code shows WHAT)]

[Optional references:]
- Fixes #123
- Related to ADR-NNN
- Implements RFC XYZ
```

**Examples from project**:
- `fix: certificate sync lock file ownership handling`
- `add: PostToolUse hook for auto-format and lint`
- `update: SessionStart hook to use 'startup' matcher`
- `docs: add HOOK_INTEGRATION_RESEARCH.md with implementation plan`

**Rules**:
- Subject line: Imperative mood ("Fix", not "Fixed" or "Fixes")
- Subject line: No period at end
- Subject line: 50 characters max
- Body: Wrap at 72 characters
- Body: Focus on WHY (motivation, context)

## Step 4: Validate Before Committing

**Pre-commit checks** (mandatory):
```bash
make fmt           # Must pass
make lint          # Must pass
make test-unit     # Must pass
```

**Do NOT commit**:
- ❌ Secrets or credentials (.env, *.key, credentials.json)
- ❌ Temporary files (/tmp/*, *.tmp)
- ❌ Generated files (unless intended, like compiled binaries)
- ❌ Large binaries without LFS
- ❌ Files with merge conflict markers

## Step 5: Stage and Commit

```bash
# Stage relevant files
git add <files>

# Create commit with drafted message
git commit -m "$(cat <<'EOF'
<drafted message here>
EOF
)"

# Verify commit
git log -1 --stat
git show --name-status
```

## Step 6: Post-Commit Verification

```bash
# Verify commit authorship
git log -1 --format='%an %ae'

# Verify not pushed yet
git status  # Should show "Your branch is ahead"

# Verify commit message follows conventions
git log -1 --pretty=format:"%s" | head -c 50  # Should be ≤50 chars
```

## Summary

Report:
- Commit hash
- Files changed
- Commit message
- Next steps (push to remote, create PR, etc.)

If pre-commit checks fail, do NOT create commit. Fix issues first.
```

**Checklist**:
- [ ] File created with frontmatter
- [ ] Commit message format matches project conventions
- [ ] Pre-commit checks enforced
- [ ] Validation steps included

#### 3.6 Command: `/review-pr`

**File**: `.claude/commands/review-pr.md`

**Purpose**: Review pull request following project standards

**Implementation**:
```markdown
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
```

**Checklist**:
- [ ] File created with frontmatter
- [ ] All review categories defined (quality, security, testing, docs)
- [ ] CWE checks align with AGENTS.md
- [ ] Approval workflow specified
- [ ] Argument placeholder $1 used for PR number

#### 3.7 Phase 3 Completion Criteria

- [ ] Commands directory created
- [ ] All 5 commands implemented
- [ ] Each command tested manually in Claude Code session
- [ ] `/help` lists all custom commands
- [ ] Commands align with CLAUDE.md and AGENTS.md standards

---

## Phase 4: Documentation and Finalization

**Priority**: MEDIUM
**Estimated Time**: 1 hour
**Status**: Pending

### Objectives

1. ✅ Update .claude/README.md with comprehensive hook documentation
2. ✅ Ensure .gitignore includes settings.local.json
3. ✅ Commit all changes to feature branch
4. ✅ Create pull request

### Tasks

#### 4.1 Update .claude/README.md

**File**: `.claude/README.md`

**Requirements**:
- Document all 3 hooks (SessionStart, PostToolUse, Stop)
- Document all 5 slash commands
- Include testing instructions
- Include customization guide
- Add troubleshooting section

**Template**:
```markdown
# Claude Code Configuration

This directory contains Claude Code hooks and slash commands for the xray-fusion project.

## Table of Contents
1. [Hooks](#hooks)
   - [SessionStart Hook](#sessionstart-hook)
   - [PostToolUse Hook](#posttooluse-hook)
   - [Stop Hook](#stop-hook)
2. [Slash Commands](#slash-commands)
3. [Testing](#testing)
4. [Customization](#customization)
5. [Troubleshooting](#troubleshooting)

## Hooks

Hooks are automated scripts that run at specific lifecycle events. Configuration is in `.claude/settings.json`.

### SessionStart Hook

**Purpose**: Auto-install development tools on session start

**Trigger**: New session initialization (`matcher: "startup"`)

**Tools Installed**:
- shfmt v3.8.0 (shell formatter)
- shellcheck v0.10.0 (shell linter)
- bats-core v1.11.0 (test framework)

**Environment Detection**:
- **Web/iOS** (`CLAUDE_CODE_REMOTE=true`): Auto-install to `~/.local/bin/`
- **Desktop** (`CLAUDE_CODE_REMOTE=false`): Show manual installation instructions

**Script**: `.claude/scripts/session-start.sh`

### PostToolUse Hook

**Purpose**: Auto-format and lint shell scripts after editing

**Trigger**: After Edit/Write operations on `.sh` files (`matcher: "Edit|Write"`)

**Actions**:
1. Format with shfmt (`-i 2 -bn -ci -sr -kp`)
2. Lint with shellcheck (`-S warning -e SC2250`)

**Behavior**:
- **Non-blocking**: Never prevents continued work
- **Sequential**: Format first, then lint (avoids race conditions)
- **Graceful**: Handles missing tools gracefully

**Script**: `.claude/scripts/format-and-lint-shell.sh`

**Example Output**:
```
[PostToolUse] Processing shell script: bin/xrf
[PostToolUse] ✓ Already formatted
[PostToolUse] Linting bin/xrf...
[PostToolUse] ✓ No linting issues
```

### Stop Hook

**Purpose**: Verify git status before ending session

**Trigger**: Before session ends (`matcher: ""`)

**Checks**:
1. **Uncommitted changes** (BLOCKS if found)
2. **Unpushed commits** (WARNS if found)
3. **Recent activity** (REMINDS about documentation updates)

**Behavior**:
- **Blocking**: Prevents ending if uncommitted changes exist
- **Warning**: Allows ending but warns about unpushed commits
- **Helpful**: Provides clear remediation steps

**Script**: `.claude/scripts/stop-hook-git-check.sh`

**Example Output** (blocking scenario):
```
[Stop] Checking git status...
[Stop] ✗ Uncommitted changes detected:
M  lib/core.sh

[Stop] Please commit or stash changes before ending session:
  git add -A
  git commit -m 'Your descriptive message'
  ...
```

## Slash Commands

Slash commands provide quick access to common workflows. Type `/help` to list all available commands.

### `/test`

Run complete test suite (fmt + lint + unit tests).

**Usage**: `/test`

**Steps**:
1. Run `make fmt`
2. Run `make lint`
3. Run `make test-unit`
4. Report summary

### `/lint-fix`

Auto-fix shellcheck linting issues.

**Usage**: `/lint-fix`

**Steps**:
1. Identify auto-fixable issues
2. Apply fixes (quote variables, use [[ ]], etc.)
3. Document justified suppressions
4. Re-run `make lint`

### `/audit`

Perform code quality audit following AGENTS.md standards.

**Usage**: `/audit`

**Checks**:
- Code reuse (duplicated functions)
- Documentation (ShellDoc compliance)
- Security (CWE issues)
- Testing (coverage gaps)
- Standards compliance (AGENTS.md adherence)

### `/commit`

Create well-formatted git commit following project conventions.

**Usage**: `/commit`

**Steps**:
1. Review changes (git status, diff)
2. Analyze change type (add/update/fix/docs)
3. Draft commit message (imperative mood, 50 char subject)
4. Run pre-commit checks (fmt, lint, test)
5. Stage and commit
6. Verify commit

### `/review-pr`

Review pull request following project standards.

**Usage**: `/review-pr <number>`

**Example**: `/review-pr 42`

**Checks**:
- Code quality (AGENTS.md standards)
- Security (CWE issues)
- Testing (coverage, test results)
- Documentation (CLAUDE.md, AGENTS.md updates)

## File Structure

```
.claude/
├── settings.json                            # Hook configuration (committed)
├── settings.local.json                      # User overrides (gitignored)
├── scripts/
│   ├── session-start.sh                    # SessionStart hook
│   ├── format-and-lint-shell.sh            # PostToolUse hook
│   └── stop-hook-git-check.sh              # Stop hook
├── commands/
│   ├── test.md                             # /test command
│   ├── lint-fix.md                         # /lint-fix command
│   ├── audit.md                            # /audit command
│   ├── commit.md                           # /commit command
│   └── review-pr.md                        # /review-pr command
├── README.md                                # This file
├── HOOK_INTEGRATION_RESEARCH.md            # Research findings
└── IMPLEMENTATION_PLAN.md                  # Implementation plan
```

## Testing

### Test Hooks Manually

**SessionStart Hook**:
```bash
./.claude/scripts/session-start.sh
# Expected: Tools installed (or skip message if desktop)
```

**PostToolUse Hook**:
```bash
# Create test file
echo '#!/usr/bin/env bash
if [ -f file ];then
echo "test"
fi' > /tmp/test.sh

# Test hook
echo '{"params":{"file_path":"/tmp/test.sh"}}' | \
  .claude/scripts/format-and-lint-shell.sh

# Expected: File formatted and linted
```

**Stop Hook**:
```bash
# Clean state
git status  # Verify clean
echo '{}' | .claude/scripts/stop-hook-git-check.sh
# Expected: "Git status clean, safe to end session"

# Dirty state
echo "test" >> README.md
echo '{}' | .claude/scripts/stop-hook-git-check.sh
# Expected: "Uncommitted changes detected" (exit 2)
git checkout README.md
```

### Test Slash Commands

Test each command in a Claude Code session:
```
/test
/lint-fix
/audit
/commit
/review-pr 123
```

## Customization

### Personal Overrides

Create `.claude/settings.local.json` (gitignored) for personal hook customization:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/my-custom-hook.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

### Team-Wide Changes

Edit `.claude/settings.json` and commit to share with team.

### Adding New Commands

Create new command file in `.claude/commands/`:

```markdown
---
description: "Brief description"
hints: "Usage hints"
---

Your command prompt here.

Use $ARGUMENTS for all args, $1 $2 for specific args.
```

## Troubleshooting

### Hook Not Running

**Problem**: Hook doesn't execute when expected

**Solutions**:
1. Check hook script is executable: `chmod +x .claude/scripts/<script>`
2. Verify `settings.json` syntax: `jq . .claude/settings.json`
3. Check matcher pattern (e.g., "startup" for SessionStart)
4. Review hook output in Claude Code session logs

### Hook Timeout

**Problem**: Hook times out during execution

**Solutions**:
1. Increase timeout in `settings.json` (default: 15s for PostToolUse, 10s for Stop)
2. Optimize hook script (reduce network calls, use caching)
3. Check for hanging commands (add timeouts to external commands)

### Tools Not Found

**Problem**: shfmt/shellcheck not available

**Solutions**:
1. Run SessionStart hook manually: `./.claude/scripts/session-start.sh`
2. Verify `~/.local/bin` in PATH: `echo $PATH`
3. Install manually (desktop environment):
   - shfmt: https://github.com/mvdan/sh
   - shellcheck: https://github.com/koalaman/shellcheck

### Stop Hook Blocking Unexpectedly

**Problem**: Can't end session despite clean git state

**Solutions**:
1. Check actual git status: `git status`
2. Look for untracked files: `git ls-files --others --exclude-standard`
3. Check for unstaged changes: `git diff`
4. Temporarily disable hook (edit `settings.local.json`)

### Slash Command Not Found

**Problem**: `/mycommand` not recognized

**Solutions**:
1. Verify file exists: `ls .claude/commands/mycommand.md`
2. Check frontmatter syntax (YAML must be valid)
3. Run `/help` to list all available commands
4. Restart Claude Code session to reload commands

## References

- [Official Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Slash Commands Documentation](https://code.claude.com/docs/en/slash-commands)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Project Standards: CLAUDE.md](../CLAUDE.md)
- [Coding Guidelines: AGENTS.md](../AGENTS.md)

## Contributing

When adding new hooks or commands:
1. Follow AGENTS.md coding standards
2. Test thoroughly (see Testing section)
3. Update this README
4. Create PR with clear description
```

**Checklist**:
- [ ] README.md updated with all hooks and commands
- [ ] Testing section complete
- [ ] Troubleshooting section added
- [ ] References to official docs included

#### 4.2 Update .gitignore

**File**: `.gitignore`

**Add**:
```
# Claude Code user-specific settings
.claude/settings.local.json
```

**Verify**:
```bash
# Check if already present
grep -q "settings.local.json" .gitignore

# If not, add it
echo "" >> .gitignore
echo "# Claude Code user-specific settings" >> .gitignore
echo ".claude/settings.local.json" >> .gitignore
```

**Checklist**:
- [ ] .gitignore updated
- [ ] settings.local.json not tracked by git
- [ ] Verified with `git status`

#### 4.3 Final Verification

**Pre-Commit Checks**:
```bash
# Run all quality checks
make fmt
make lint
make test-unit

# All should pass
```

**Git Status**:
```bash
git status
# Expected files:
#   modified:   .claude/README.md
#   modified:   .claude/settings.json
#   modified:   .gitignore
#   new file:   .claude/scripts/format-and-lint-shell.sh
#   new file:   .claude/scripts/stop-hook-git-check.sh
#   new file:   .claude/commands/test.md
#   new file:   .claude/commands/lint-fix.md
#   new file:   .claude/commands/audit.md
#   new file:   .claude/commands/commit.md
#   new file:   .claude/commands/review-pr.md
#   new file:   .claude/HOOK_INTEGRATION_RESEARCH.md
#   new file:   .claude/IMPLEMENTATION_PLAN.md
```

**Checklist**:
- [ ] All quality checks pass
- [ ] All new files staged
- [ ] No unintended files included
- [ ] Ready for commit

#### 4.4 Commit and Push

**Commit Message**:
```bash
git add .claude/ .gitignore

git commit -m "$(cat <<'EOF'
add: Claude Code hooks and slash commands integration

Implement comprehensive Claude Code automation following official
documentation and best practices.

Hooks Added:
- PostToolUse: Auto-format and lint shell scripts after editing
- Stop: Verify git status before ending session (blocks if uncommitted)

Slash Commands Added:
- /test: Run complete test suite (fmt, lint, unit tests)
- /lint-fix: Auto-fix shellcheck issues
- /audit: Code quality audit (reuse, docs, security, testing)
- /commit: Create well-formatted git commit
- /review-pr: Review pull request following standards

All implementations:
- Follow official Claude Code hooks documentation
- Align with CLAUDE.md and AGENTS.md standards
- Include comprehensive testing procedures
- Non-blocking user experience (hooks inform, not obstruct)
- Graceful degradation (missing tools handled)

References:
- Research: .claude/HOOK_INTEGRATION_RESEARCH.md
- Implementation: .claude/IMPLEMENTATION_PLAN.md
- Source: https://github.com/xrf9268-hue/sbx/.claude

Related to: SessionStart hook optimization (matcher: "startup")
EOF
)"
```

**Push**:
```bash
# Push to feature branch
git push -u origin claude/research-claude-hooks-011YvSkWHWyS17mbdfeTivKr

# Retry up to 4 times if network failure (per git best practices)
# Exponential backoff: 2s, 4s, 8s, 16s
```

**Checklist**:
- [ ] Commit message follows project conventions
- [ ] Commit created successfully
- [ ] Pushed to correct branch
- [ ] No push errors

#### 4.5 Phase 4 Completion Criteria

- [ ] README.md updated and comprehensive
- [ ] .gitignore updated
- [ ] All quality checks pass
- [ ] Changes committed with proper message
- [ ] Changes pushed to feature branch

---

## Overall Completion Criteria

### Definition of Done

- [ ] **Phase 1 Complete**: PostToolUse hook implemented and tested
- [ ] **Phase 2 Complete**: Stop hook implemented and tested
- [ ] **Phase 3 Complete**: 5 slash commands implemented and tested
- [ ] **Phase 4 Complete**: Documentation updated and changes committed

### Success Metrics

**PostToolUse Hook**:
- [ ] Auto-formats 100% of edited shell scripts
- [ ] Reports lint issues within 5 seconds
- [ ] Zero false positives (only .sh files processed)
- [ ] Gracefully handles missing tools

**Stop Hook**:
- [ ] Blocks 100% of attempts to end session with uncommitted changes
- [ ] Warns about unpushed commits
- [ ] Provides clear remediation steps
- [ ] Exit codes correct (0 for allow, 2 for block)

**Slash Commands**:
- [ ] All 5 commands listed in `/help`
- [ ] Each command tested manually with success
- [ ] Commands align with CLAUDE.md/AGENTS.md standards
- [ ] Workflows complete end-to-end

**Documentation**:
- [ ] README.md comprehensive and accurate
- [ ] All hooks documented with examples
- [ ] All commands documented with usage
- [ ] Troubleshooting section helpful

### Validation Checklist

Before marking complete:
- [ ] Run `make fmt && make lint && make test-unit` (all pass)
- [ ] Test all 3 hooks manually
- [ ] Test all 5 slash commands in session
- [ ] Review README.md for accuracy
- [ ] Verify .gitignore excludes settings.local.json
- [ ] Commit message follows conventions
- [ ] Changes pushed to correct branch

---

## Timeline

**Total Estimated Time**: 6-8 hours

- **Phase 1**: 2-3 hours (PostToolUse hook)
- **Phase 2**: 1-2 hours (Stop hook)
- **Phase 3**: 2-3 hours (Slash commands)
- **Phase 4**: 1 hour (Documentation)

**Recommended Schedule**:
- **Day 1**: Phase 1 (PostToolUse hook) - Highest ROI
- **Day 2**: Phase 2 (Stop hook) - Git safety
- **Day 3**: Phase 3 (Slash commands) - Workflow enhancement
- **Day 4**: Phase 4 (Documentation and finalization)

---

## Notes

### Design Principles

1. **Non-Blocking**: Hooks inform, they don't obstruct work
2. **Sequential Processing**: Format before lint (avoid race conditions)
3. **Graceful Degradation**: Missing tools don't break workflows
4. **Clear Feedback**: All output actionable and helpful
5. **Official Alignment**: Follow Claude Code docs exactly

### Best Practices Applied

- ✅ Single hook per matcher (avoid parallel race conditions)
- ✅ Timeout set for all hooks (prevent hanging)
- ✅ JSON output for blocking scenarios (official format)
- ✅ Tool availability checks (graceful degradation)
- ✅ One-time warnings (reduce noise)
- ✅ Portable paths (`$CLAUDE_PROJECT_DIR`)
- ✅ Exit code semantics (0=allow, 2=block)

### References

- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Slash Commands](https://code.claude.com/docs/en/slash-commands)
- [Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Source Repository](https://github.com/xrf9268-hue/sbx/tree/main/.claude)

---

**End of Implementation Plan**
