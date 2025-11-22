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
