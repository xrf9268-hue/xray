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
if ! git diff-index --quiet HEAD -- 2> /dev/null; then
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
  exit 2 # Block stopping
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
  ahead_count=$(git rev-list --count origin/"${current_branch}"..HEAD 2> /dev/null || echo "?")

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
