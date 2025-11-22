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
