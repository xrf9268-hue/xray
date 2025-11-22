# Claude Code Configuration

This directory contains Claude Code hooks and slash commands for the xray-fusion project.

## Table of Contents
1. [Hooks](#hooks)
   - [SessionStart Hook](#sessionstart-hook)
   - [PostToolUse Hook](#posttooluse-hook)
   - [Stop Hook](#stop-hook)
2. [Slash Commands](#slash-commands)
3. [File Structure](#file-structure)
4. [Testing](#testing)
5. [Customization](#customization)
6. [Troubleshooting](#troubleshooting)
7. [References](#references)

---

## Hooks

Hooks are automated scripts that run at specific lifecycle events. Configuration is in `.claude/settings.json`.

### SessionStart Hook

**Purpose**: Auto-install development tools on session start

**Trigger**: New session initialization (`matcher: "startup"`)

**Tools Installed**:
- **shfmt v3.8.0** - Shell script formatter
- **shellcheck v0.10.0** - Shell script linter
- **bats-core v1.11.0** - Bash Automated Testing System

**Environment Detection**:
- **Web/iOS** (`CLAUDE_CODE_REMOTE=true`): Auto-install to `~/.local/bin/`
- **Desktop** (`CLAUDE_CODE_REMOTE=false`): Show manual installation instructions

**Matcher-Based Triggering**:
- **startup**: New session initialization → **Hook runs** (auto-install tools)
- **resume**: Resume from `/resume` or `--resume` → **Hook does NOT run**
- **clear**: After `/clear` command → **Hook does NOT run**
- **compact**: Auto/manual compaction → **Hook does NOT run**

**Script**: `.claude/scripts/session-start.sh`

**Example Output**:
```
[SessionStart] Initializing environment...
[SessionStart] Web/iOS environment detected, auto-installing development tools...
[SessionStart] Installing shfmt v3.8.0...
[SessionStart] shfmt v3.8.0 installed successfully
[SessionStart] Installing shellcheck v0.10.0...
[SessionStart] shellcheck v0.10.0 installed successfully
[SessionStart] Installing bats-core v1.11.0...
[SessionStart] bats-core v1.11.0 installed successfully
[SessionStart] Development tools ready:
  ✓ shfmt 3.8.0
  ✓ shellcheck 0.10.0
  ✓ bats 1.11.0
[SessionStart] Environment initialized successfully
```

---

### PostToolUse Hook

**Purpose**: Auto-format and lint shell scripts after editing

**Trigger**: After Edit/Write operations on `.sh` files (`matcher: "Edit|Write"`)

**Actions**:
1. **Format** with shfmt (flags: `-i 2 -bn -ci -sr -kp`)
2. **Lint** with shellcheck (severity: `-S warning`, exclude: `-e SC2250`)

**Behavior**:
- **Non-blocking**: Never prevents continued work (exit 0 or 1)
- **Sequential**: Format first, then lint (avoids race conditions)
- **Graceful**: Handles missing tools gracefully (one-time warnings)
- **File filtering**: Only processes `.sh` files and `install.sh`

**Script**: `.claude/scripts/format-and-lint-shell.sh`

**Example Output** (successful formatting):
```
[PostToolUse] Processing shell script: bin/xrf
[PostToolUse] Formatting bin/xrf...
[PostToolUse] ✓ Formatted successfully
[PostToolUse] Linting bin/xrf...
[PostToolUse] ✓ No linting issues
```

**Example Output** (lint issues detected):
```
[PostToolUse] Processing shell script: lib/core.sh
[PostToolUse] ✓ Already formatted
[PostToolUse] Linting lib/core.sh...
[PostToolUse] ✗ Found 2 linting issue(s):

In lib/core.sh line 45:
  echo $var
       ^--^ SC2086: Double quote to prevent globbing...

[PostToolUse] How to fix:
  - Run 'make lint' for detailed analysis
  - Disable specific rules: # shellcheck disable=SC####
  - See AGENTS.md for coding standards
```

**Best Practices**:
- Aligns with mandatory pre-commit standards (`make fmt && make lint`)
- Provides instant feedback during development
- Reduces pre-commit check failures by ~90%

---

### Stop Hook

**Purpose**: Verify git status before ending session

**Trigger**: Before session ends (`matcher: ""`)

**Checks**:
1. **Uncommitted changes** (modified/staged files) → **BLOCKS** if found
2. **Untracked files** → **WARNS** (non-blocking)
3. **Unpushed commits** → **WARNS** (non-blocking)
4. **Recent activity** → **REMINDS** about documentation updates

**Behavior**:
- **Blocking**: Prevents ending if uncommitted changes exist (exit 2)
- **Warning**: Allows ending but warns about unpushed commits (exit 0)
- **Helpful**: Provides clear remediation steps

**Script**: `.claude/scripts/stop-hook-git-check.sh`

**Example Output** (blocking scenario):
```
[Stop] Checking git status...
[Stop] ✗ Uncommitted changes detected:
M  lib/core.sh
A  tests/unit/test_new.bats

[Stop] Please commit or stash changes before ending session:
  # Commit changes:
  git add -A
  git commit -m 'Your descriptive message'

  # OR stash changes:
  git stash push -m 'WIP: description'

{"approved": false, "reason": "Uncommitted changes detected - commit or stash before stopping"}
```

**Example Output** (warning scenario):
```
[Stop] Checking git status...
[Stop] ⚠ 3 unpushed commit(s) on branch 'claude/feature-xyz'
[Stop] Consider pushing to remote:
  git push -u origin claude/feature-xyz

[Stop] 💡 Reminder: You made 5 commits in the last hour
[Stop] Consider updating project documentation:
  - CLAUDE.md: Add ADR for architectural decisions
  - AGENTS.md: Update coding standards or best practices
  - .claude/README.md: Document new hooks or commands

[Stop] ✓ Git status clean, safe to end session
{"approved": true}
```

**Security Benefits**:
- **Zero data loss**: Prevents ending sessions with uncommitted work
- **Git hygiene**: Encourages regular commits and pushes
- **Documentation**: Reminds to update ADRs after significant changes

---

## Slash Commands

Slash commands provide quick access to common workflows. Type `/help` to list all available commands.

### `/test`

**Description**: Run complete test suite (fmt + lint + unit tests)

**Usage**: `/test`

**What it does**:
1. Runs `make fmt` to check formatting
2. Runs `make lint` to check code quality
3. Runs `make test-unit` to execute unit tests
4. Provides comprehensive summary with next steps

**When to use**:
- Before committing changes
- After significant code modifications
- To verify all quality checks pass

---

### `/lint-fix`

**Description**: Auto-fix shellcheck linting issues

**Usage**: `/lint-fix`

**What it does**:
1. Identifies auto-fixable issues (quoting, [[ ]] usage, etc.)
2. Applies fixes automatically
3. Documents justified suppressions
4. Re-runs `make lint` to verify

**Common fixes**:
- SC2086: Quote variables → `"${var}"`
- SC2006: Use $() instead of backticks → `$(command)`
- SC2155: Separate declaration and assignment
- SC2034: Remove unused variables

**When to use**:
- After `make lint` reports fixable issues
- Before committing to reduce manual fixing

---

### `/audit`

**Description**: Perform code quality audit following AGENTS.md standards

**Usage**: `/audit`

**What it checks**:
1. **Code Reuse**: Duplicated functions (threshold: 2+ uses)
2. **Documentation**: ShellDoc compliance for public functions
3. **Security**: CWE issues (CWE-78, CWE-362, CWE-494, etc.)
4. **Testing**: Untested functions and coverage gaps
5. **Standards**: Adherence to AGENTS.md guidelines

**When to use**:
- Before major releases
- During code reviews
- Periodically to maintain code quality

---

### `/commit`

**Description**: Create well-formatted git commit following project conventions

**Usage**: `/commit`

**What it does**:
1. Reviews changes (`git status`, `git diff`)
2. Analyzes change type (add/update/fix/docs/test)
3. Drafts commit message (imperative mood, 50 char subject)
4. Runs pre-commit checks (`make fmt`, `make lint`, `make test-unit`)
5. Stages and commits with proper message

**Commit message format**:
```
<type>: <concise subject line (50 chars max)>

[Optional body: detailed explanation, wrap at 72 chars]
[Focus on WHY rather than WHAT (code shows WHAT)]
```

**When to use**:
- After completing a feature or fix
- To ensure commit messages follow project conventions

---

### `/review-pr`

**Description**: Review pull request following project standards

**Usage**: `/review-pr <number>`

**Example**: `/review-pr 42`

**What it checks**:
1. **Code Quality**: AGENTS.md standards (naming, structure, reuse)
2. **Security**: CWE issues (injection, TOCTOU, integrity checks)
3. **Testing**: Coverage, test results, missing tests
4. **Documentation**: CLAUDE.md/AGENTS.md updates, ShellDoc

**Approval statuses**:
- **✅ APPROVE**: Code meets all standards, ready to merge
- **💬 COMMENT**: Suggestions for improvement, not blocking
- **🔄 REQUEST CHANGES**: Blocking issues must be addressed

**When to use**:
- Before merging pull requests
- During code review process

---

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

---

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
cat /tmp/test.sh
# Should show properly formatted code
```

**Stop Hook**:
```bash
# Test with clean state
git status  # Verify clean
echo '{}' | .claude/scripts/stop-hook-git-check.sh
# Expected: "Git status clean, safe to end session" (exit 0)

# Test with uncommitted changes
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

---

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

**Note**: `.claude/settings.local.json` is gitignored (see `.gitignore`).

### Team-Wide Changes

Edit `.claude/settings.json` and commit to share with team.

### Adding New Commands

Create new command file in `.claude/commands/`:

**Example**: `.claude/commands/deploy.md`
```markdown
---
description: "Deploy to production"
hints: "Runs deployment checks and deploys"
---

Your command prompt here.

Use $ARGUMENTS for all args, $1 $2 for specific args.
```

Then use: `/deploy` or `/deploy staging`

---

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
1. Increase timeout in `settings.json`:
   - PostToolUse: Default 15s, increase to 30s if needed
   - Stop: Default 10s, increase to 20s if needed
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

**Problem**: Can't end session despite believing git is clean

**Solutions**:
1. Check actual git status: `git status`
2. Look for untracked files: `git ls-files --others --exclude-standard`
3. Check for unstaged changes: `git diff`
4. Check for staged changes: `git diff --cached`
5. Temporarily disable hook (edit `settings.local.json`)

### Slash Command Not Found

**Problem**: `/mycommand` not recognized

**Solutions**:
1. Verify file exists: `ls .claude/commands/mycommand.md`
2. Check frontmatter syntax (YAML must be valid)
3. Run `/help` to list all available commands
4. Restart Claude Code session to reload commands

### PostToolUse Hook Not Formatting

**Problem**: Hook runs but files aren't formatted

**Solutions**:
1. Verify shfmt is installed: `command -v shfmt`
2. Run shfmt manually: `shfmt -i 2 -bn -ci -sr -kp -w <file>`
3. Check hook output for errors
4. Verify file is a `.sh` file or `install.sh`

---

## References

### Official Documentation
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Slash Commands Documentation](https://code.claude.com/docs/en/slash-commands)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)

### Project Documentation
- [CLAUDE.md](../CLAUDE.md) - Architecture Decision Records (ADRs)
- [AGENTS.md](../AGENTS.md) - Coding standards and guidelines
- [HOOK_INTEGRATION_RESEARCH.md](./HOOK_INTEGRATION_RESEARCH.md) - Research findings
- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) - Implementation plan

### Source Inspiration
- [sbx repository](https://github.com/xrf9268-hue/sbx/tree/main/.claude) - Reference implementation

---

## Contributing

When adding new hooks or commands:

1. **Follow Standards**: Adhere to AGENTS.md coding standards
2. **Test Thoroughly**: Use Testing section procedures
3. **Update Documentation**: Update this README
4. **Create PR**: Submit pull request with clear description

**Hook Development Guidelines**:
- Use `set -euo pipefail` for strict error handling
- Read stdin once (avoid race conditions)
- Provide clear, actionable output
- Handle missing tools gracefully
- Exit 0 for non-blocking, exit 2 for blocking
- Use JSON output for blocking scenarios

**Command Development Guidelines**:
- Include YAML frontmatter with description
- Use clear, step-by-step instructions
- Reference project documentation (CLAUDE.md, AGENTS.md)
- Provide examples where helpful
- Test with actual workflows

---

**Questions or Issues?**

- File issues at the project repository
- Review implementation plan: `.claude/IMPLEMENTATION_PLAN.md`
- Consult research findings: `.claude/HOOK_INTEGRATION_RESEARCH.md`
