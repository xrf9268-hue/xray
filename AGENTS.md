# Technical Reference

Detailed patterns and conventions for xray-fusion development.

## Scope

- Applies to the entire repository rooted at this `AGENTS.md`.
- If a deeper directory contains another `AGENTS.md`, the deeper file takes precedence for that subtree.
- This file is operational guidance for coding agents and should stay aligned with `CONTRIBUTING.md`.

## Execution Rules

### Always

- Prefer targeted changes and keep diffs minimal.
- Use structured logging via `core::log`; do not add new plain `echo` logging in library/runtime paths.
- Update tests and docs when behavior changes (especially `tests/README.md`, `CONTRIBUTING.md`, and relevant service docs).
- Run verification commands relevant to the changed area before claiming completion.

### Never

- Do not add `trap ... EXIT` patterns in utility/library functions.
- Do not bypass shellcheck/shfmt conventions for shell files.
- Do not enable Docker proxy fallback in GitHub CI; local-only fallback is allowed (see Testing section).

## Change-Triggered Verification

Run these checks based on what you changed:

- `lib/**`, `modules/**`, `commands/**`, `services/**`, `plugins/**`, `bin/**`:
  `make fmt && make lint && make test-unit`
- `.github/workflows/**`, `.github/dependabot.yml`:
  `bats -t tests/unit/test_github_metadata.bats`
- `scripts/e2e/install-lifecycle-smoke.sh`:
  `bash -n scripts/e2e/install-lifecycle-smoke.sh`
- `tests/**`:
  run the specific changed bats file(s), then `make test-unit`

Before opening a PR, prefer running full test suite when feasible:

```bash
make test
```

## Key APIs

### Core Utilities (`lib/core.sh`)

```bash
# Structured logging - ALWAYS use, never echo
core::log info "message" '{"key":"value"}'
core::log error "failed" "$(printf '{"file":"%s"}' "${path}")"

# File locking
core::with_flock /var/lock/mylock.lock my_command arg1 arg2

# Retry with exponential backoff
core::retry 3 curl -fsSL "${url}"
```

### I/O Utilities (`modules/io.sh`)

```bash
# Atomic file write (same-partition, prevents race conditions)
echo "content" | io::atomic_write /path/to/file 0644

# Directory creation with sudo fallback
io::ensure_dir /path/to/dir 0755
```

### Validators (`lib/validators.sh`)

```bash
# RFC-compliant domain validation (rejects private/reserved)
validators::domain "example.com" || exit 1
```

### Xray Utilities (`services/xray/common.sh`)

```bash
# Generate 16-char hex shortId (uses xxd → od → openssl fallback)
shortid=$(xray::generate_shortid)
```

## Shell Patterns

### Source Guards (Required for Libraries)

```bash
# Prevent "readonly variable" errors on multiple source
[[ -n "${_XRF_MYLIB_LOADED:-}" ]] && return 0
readonly _XRF_MYLIB_LOADED=1

readonly MY_CONSTANT="value"
```

### Module Dependencies

```bash
# ALWAYS source dependencies explicitly
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/defaults.sh
. "${HERE}/lib/defaults.sh"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"
```

### No Traps in Utility Functions

```bash
# EXIT traps in functions break pipelines and test frameworks
# Use explicit cleanup instead:
my_function() {
  local tmp="$(mktemp)"
  if ! some_operation > "${tmp}"; then
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  fi
  mv "${tmp}" "${dest}" || { rm -f "${tmp}"; return 1; }
}
```

### Atomic File Operations

```bash
# Create temp in same dir for atomic mv
tmp="$(mktemp -p "${dstdir}" .atomic.XXXXXX.tmp)"
cat > "${tmp}" && mv -f "${tmp}" "${dst}"
```

### External Tool Parsing

```bash
# Normalize before matching - upstream formats change silently
label="${line%%:*}"
normalized="${label,,}"                # lowercase
normalized="${normalized//[[:space:]]/}"  # remove whitespace
if [[ "${normalized}" == *keyword* ]]; then
  # matched
fi
```

## Testing

```bash
# Run all checks
make fmt && make lint && make test-unit

# Run specific test file
bats -t tests/unit/test-core.bats

# Test with sandbox paths
XRF_PREFIX=$PWD/tmp/prefix XRF_ETC=$PWD/tmp/etc bin/xrf install --topology reality-only

# Local e2e smoke test (Docker)
scripts/e2e/install-lifecycle-smoke.sh
```

- Local e2e Docker test may fallback to `docker.950288.xyz/library/ubuntu:24.04` when `ubuntu:24.04` pull fails.
- GitHub CI must stay on official source only (`GITHUB_ACTIONS=true` path disables proxy fallback).
- Optional overrides:
  - `XRF_SMOKE_BASE_IMAGE` (default: `ubuntu:24.04`)
  - `XRF_SMOKE_FALLBACK_IMAGE` (default: `docker.950288.xyz/library/ubuntu:24.04`)

## Xray Configuration

### Ports
- **Reality**: 443 (standard HTTPS)
- **Vision**: 8443 (real TLS)
- **Caddy HTTPS**: 8444

### Certificate Permissions
```bash
chmod 644 fullchain.pem
chmod 640 privkey.pem
chown root:xray *.pem
```

### TLS Settings
```json
{
  "minVersion": "1.3",
  "alpn": ["h2", "http/1.1"]
}
```

### Key Concepts
- REALITY does not require domain ownership (SNI is for camouflage)
- Use `systemctl restart xray` after cert updates (no reload support)
- shortIds is a server pool, not per-client requirement

## Function Documentation

```bash
##
# Brief description
#
# Arguments:
#   $1 - name (type, required)
#   $2 - value (type, optional, default: X)
#
# Returns:
#   0 - success
#   1 - error
##
my_function() {
  # implementation
}
```

## Commit Guidelines

- Use Conventional Commits: `<type>(<scope>): <subject>`
- Keep subject imperative and concise (prefer <72 chars)
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- Before commit, run at minimum:

```bash
make fmt && make lint && make test-unit
```

## Push and CI

- After every push or PR update, monitor GitHub Actions for the pushed commit until all required checks complete.
- If any required check fails, investigate the failure, make the necessary fix, rerun relevant local validation, and push follow-up commits until the required checks pass.
- After every push or PR update, also review new PR reviews, review comments, and bot suggestions for the pushed commit.
- Treat actionable review findings as required follow-up work: validate whether they still apply on `HEAD`, fix or respond with evidence, rerun relevant local validation, and push follow-up commits until there is no unresolved blocking review feedback.
- Do not stop at reporting CI failures unless the user explicitly asks to pause.

## Plugin System

### Metadata (Required)

```bash
XRF_PLUGIN_ID="my-plugin"
XRF_PLUGIN_VERSION="1.0.0"
XRF_PLUGIN_DESC="Description"
XRF_PLUGIN_HOOKS=("configure_post" "deploy_post")
XRF_PLUGIN_DEPS=("curl" "jq")  # optional, auto-installed
```

### Hooks

`configure_pre` | `configure_post` | `deploy_post` | `service_setup` | `service_remove` | `links_render` | `uninstall_pre`

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| `readonly variable` error | Add source guard |
| Variable undefined in SC2154 | Source the defining module |
| `exec >> lock` fails | Fix ownership AND permissions |
| Network download fails | Use `core::retry` |
| Parse error after tool upgrade | Normalize labels before matching |
| Trap "unbound variable" | Don't use traps in utility functions |
| kcov exits non-zero with bats | DEBUG trap conflict; capture exit code, check `coverage.json` instead |
| Prebuilt binary crashes in CI | Build from source and cache; prebuilt binaries assume specific shared libs |
| Python f-string `SyntaxError` | No backslashes in f-string expressions before 3.12; use `%`-formatting |
