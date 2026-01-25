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
#   - Only processes .sh and .bats files (prevent unintended execution)
##

set -euo pipefail

# Check jq availability (required for JSON parsing)
if ! command -v jq > /dev/null 2>&1; then
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

# Only process shell scripts (.sh, .bats extension)
if [[ ! "${file}" =~ \.(sh|bats)$ ]]; then
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
if command -v shfmt > /dev/null 2>&1; then
  # Check if formatting needed (dry-run with -d flag)
  if ! shfmt -i 2 -bn -ci -sr -kp -d "${file}" > /dev/null 2>&1; then
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
if command -v shellcheck > /dev/null 2>&1; then
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
