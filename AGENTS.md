# Repository Guidelines

## Project Structure & Module Organization
- `bin/xrf`: CLI entrypoint (install/status/uninstall/plugin).
- `commands/`: High‑level workflows (e.g., `install.sh`, `status.sh`).
- `lib/`: Core utilities (`core.sh`, `args.sh`, `plugins.sh`).
- `modules/`: Reusable helpers (`io.sh`, `state.sh`, `fw/*`, `user/*`, `web/*`).
- `services/xray/`: Xray install/configure/systemd logic.
- `plugins/available/<id>/plugin.sh`: Built‑in plugins; `plugins/enabled/` is auto‑managed.
- `packaging/systemd/`: Unit templates.

## Build, Test, and Development Commands
- `make fmt` — Format all Bash with shfmt (2‑space, Bash mode).
- `make lint` — ShellCheck across scripts (errors/warnings, `-x`).
- `make test` — Run all tests (unit + integration).
- `make test-unit` — Run unit tests only.
- Run locally:
  - `bin/xrf install --topology reality-only`
  - `bin/xrf status`, `bin/xrf links`, `bin/xrf uninstall`
  - Example safe sandbox: `XRF_PREFIX=$PWD/tmp/prefix XRF_ETC=$PWD/tmp/etc bin/xrf install --topology reality-only`

## Coding Style & Naming Conventions
- Language: Bash; start files with `#!/usr/bin/env bash` and `set -euo pipefail` where applicable.
- Indentation: 2 spaces; UTF‑8; LF (see `.editorconfig`).
- Namespacing: `namespace::function` (e.g., `core::log`, `io::atomic_write`).
- Variables: lowercase `local` vars; exported/env vars UPPER_SNAKE (e.g., `XRAY_*`, `XRF_*`).
- File names: kebab‑case; plugins use ID `[a-zA-Z0-9_-]+` and functions via `plugins::fn_prefix`.
- Use helpers: `io::ensure_dir`, `io::atomic_write`, `core::log`, `core::with_flock`, `core::ensure_lock_writable`, `xray::generate_shortid`.

## Development Principles
- **System debugging, no guessing**: Use logs to analyze and locate issues based on actual phenomena.
- **Use project logging framework**: Consistently use `core::log`, never use `echo` for logs.
- **Consult official docs first**: Avoid deprecated or outdated implementations.
- **Keep code clean**: No unnecessary backward compatibility; delete incomplete/deprecated code.
- **Scriptable everything**: Ensure all operations are parameterized via scripts, avoid manual intervention.
- **Code reuse over duplication**: Extract common logic into reusable functions when used 2+ times.

## Code Reuse Principles

To maintain code quality and prevent duplication, follow these guidelines:

### When to Extract a Function
- **Duplication threshold**: Extract when same logic appears 2+ times
- **Location priority**: Place in `lib/` for core utilities, `modules/` for helpers, `services/` for domain-specific
- **Standalone scripts**: Create lightweight compatible versions when script cannot source shared libs

### Key Reusable Functions

**Core Utilities** (`lib/core.sh`):
- `core::log(level, message, context)` - Structured logging (text/JSON)
- `core::with_flock(lock, command...)` - Execute with exclusive file lock
- `core::ensure_lock_writable(lock_file)` - Fix lock file ownership/permissions (CWE-283)
- `core::retry(attempts, command...)` - Retry with exponential backoff

**Xray Utilities** (`services/xray/common.sh`):
- `xray::generate_shortid()` - Generate 16-char hex shortId (xxd → od → openssl)
- `xray::prefix()`, `xray::etc()`, `xray::confbase()` - Path helpers

**I/O Utilities** (`modules/io.sh`):
- `io::ensure_dir(dir, mode)` - Create directory with sudo fallback
- `io::atomic_write(file, mode)` - Atomic file write from stdin
- `io::writable(path)` - Check if path is writable

**Validators** (`lib/validators.sh`):
- `validators::domain(domain)` - RFC-compliant domain validation (1918/3927/6761/4193/4291)
- `validators::shortid(id)` - Validate shortId format
- `validators::port(port)` - Validate TCP/UDP port

### Standalone Script Pattern

For scripts that cannot source shared libraries (e.g., `/usr/local/bin/caddy-cert-sync`), define lightweight compatible versions:

```bash
##
# Standalone version of core::ensure_lock_writable
#
# Lightweight version for standalone scripts.
# Maintains API compatibility with lib/core.sh.
##
ensure_lock_writable() {
  local lock="${1}"
  [[ ! -f "${lock}" ]] && return 0

  # Fix ownership
  if ! chown "$(id -u):$(id -g)" "${lock}" 2>/dev/null; then
    command -v sudo >/dev/null && sudo chown "$(id -u):$(id -g)" "${lock}" 2>/dev/null || return 1
  fi

  # Fix permissions
  chmod 0644 "${lock}" 2>/dev/null || return 1
}
```

**Key Points**:
- Keep API identical to original function
- Document as "standalone version of X"
- Note compatibility in comments
- Keep implementation minimal

### Anti-Patterns to Avoid
- ❌ Copy-pasting function implementations
- ❌ Inline directory creation (`mkdir -p`) when `io::ensure_dir()` exists
- ❌ Inline lock management when `core::with_flock()` exists
- ❌ Custom hex generation when `xray::generate_shortid()` exists
- ❌ Simplified validation when RFC-compliant version exists

## Security Best Practices

### Download Integrity Verification
**Critical**: When downloading and executing code (e.g., install scripts), ALWAYS verify integrity BEFORE executing any downloaded code.

```bash
# ❌ Wrong: Verify AFTER sourcing (CWE-494)
source "${downloaded_dir}/lib/core.sh"  # Malicious code executes here!
git rev-parse HEAD  # Verification is now meaningless

# ✅ Correct: Verify BEFORE sourcing
actual_commit=$(git -C "${downloaded_dir}" rev-parse HEAD)
[[ "${actual_commit}" == "${expected_commit}" ]] || exit 1
source "${downloaded_dir}/lib/core.sh"  # Safe to execute
```

**Key Principles**:
- Verification logic must be self-contained (use only trusted system tools)
- Never `source` or execute downloaded code before integrity checks pass
- Fail fast on verification errors (call `error_exit` or equivalent)
- Support optional cryptographic verification (commit hash, GPG signatures)

**Attack Scenarios Prevented**:
- Man-in-the-middle (MITM) attacks
- Malicious mirror repositories
- DNS hijacking

**Reference**:
- CWE-494: Download of Code Without Integrity Check
- See `install.sh:595-634` for reference implementation
- Security test: `tests/security/test-download-verification.sh`

## Function Documentation Standard

All public functions must include ShellDoc-style comments for maintainability and developer onboarding:

```bash
##
# Brief one-line description of the function
#
# Detailed description (optional, multiple lines)
# Explain what the function does, why it exists, and any important notes.
#
# Arguments:
#   $1 - Parameter name (type, required/optional, description)
#   $2 - Parameter name (type, required/optional, default: value)
#
# Input:
#   Description of stdin input (if applicable)
#
# Output:
#   Description of stdout output
#
# Globals:
#   VARIABLE_NAME - Description of global variable used/modified
#
# Returns:
#   0 - Success description
#   1 - Error description
#   N - Another error code description (reference lib/errors.sh)
#
# Security:
#   Security considerations (CWE references, TOCTOU, etc.)
#
# Example:
#   function_name arg1 arg2
#   echo "data" | function_name arg1
##
function_name() {
  # implementation
}
```

**Documentation Requirements**:
- All public functions in `lib/`, `modules/`, and `services/` must have documentation
- Helper functions and internal functions should have brief inline comments
- Security-sensitive functions must include Security section with CWE references
- Functions with non-trivial return codes must document all possible return values
- Complex algorithms should include examples

**Example - Core logging function**:
```bash
##
# Structured logging to stderr
#
# Logs messages in text or JSON format depending on XRF_JSON.
# All output goes to stderr to avoid contaminating function
# return values. Debug messages are filtered unless XRF_DEBUG=true.
#
# Arguments:
#   $1 - Log level (string, required) - debug|info|warn|error
#   $2 - Message (string, required)
#   $3 - Context JSON (string, optional, default: "{}")
#
# Globals:
#   XRF_JSON - If "true", output JSON format
#   XRF_DEBUG - If "true", show debug messages
#
# Output:
#   Log line to stderr (text or JSON format)
#
# Returns:
#   0 - Always succeeds (or returns early for filtered debug)
#
# Example:
#   core::log info "Operation completed" '{"duration_ms":123}'
#   core::log error "Failed" "$(printf '{"file":"%s"}' "${path}")"
##
core::log() {
  local lvl="${1}"; shift
  local msg="${1}"; shift || true
  local ctx="${1-{} }"
  # ... implementation ...
}
```

## Shell Programming Best Practices

### Logging Standards
```bash
# All logs go to stderr to avoid polluting function return values
core::log() {
  local lvl="${1}"; shift
  local msg="${1}"; shift || true
  local ctx="${1-{} }"

  # Filter debug messages unless XRF_DEBUG=true
  [[ "${lvl}" == "debug" && "${XRF_DEBUG}" != "true" ]] && return 0

  # All logs to stderr
  if [[ "${XRF_JSON}" == "true" ]]; then
    printf '{"ts":"%s","level":"%s","msg":"%s","ctx":%s}\n' \
      "$(core::ts)" "${lvl}" "${msg}" "${ctx}" >&2
  else
    printf '[%s] %-5s %s %s\n' "$(core::ts)" "${lvl}" "${msg}" "${ctx}" >&2
  fi
}

# Standalone scripts embed compatible log function
# For scripts like /usr/local/bin/caddy-cert-sync
log() {
  local lvl="${1}"; shift
  local msg="${1}"
  [[ "${lvl}" == "debug" && "${XRF_DEBUG}" != "true" ]] && return 0
  if [[ "${XRF_JSON}" == "true" ]]; then
    printf '{"ts":"%s","level":"%s","msg":"[script-name] %s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${lvl}" "${msg}" >&2
  else
    printf '[%s] %-5s [script-name] %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${lvl}" "${msg}" >&2
  fi
}

# External command output must also be redirected
external-command >/dev/null 2>&1 || true
```

### Trap and Variable Scope
```bash
# ❌ Wrong: local variable in EXIT trap
function_name() {
  local tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT  # Local variable may fail in trap
}

# ✅ Correct: Use global variable + parameter expansion
function_name() {
  local tmpdir="$(mktemp -d)"
  _GLOBAL_TMPDIR="${tmpdir}"
  trap 'rm -rf "${_GLOBAL_TMPDIR:-}" 2>/dev/null || true; unset _GLOBAL_TMPDIR' EXIT
}

# ✅ Better: Trap multiple signals
cleanup() {
  [[ -n "${tmpdir:-}" && -d "${tmpdir}" ]] && rm -rf "${tmpdir}"
}
trap cleanup EXIT INT TERM HUP
```

### Avoiding Traps in Utility Functions

**Critical**: Do NOT use EXIT/INT/TERM traps in utility functions. Traps are process-level and cause unpredictable behavior in pipelines, subshells, and test frameworks.

```bash
# ❌ Wrong: Using traps in utility function
function_with_trap() {
  local tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' EXIT INT TERM  # Bug: triggers unexpectedly!
  cat > "${tmp}"
  mv "${tmp}" "/destination"
  trap - EXIT INT TERM
}

# Caller uses pipeline:
echo "data" | function_with_trap  # Fails! EXIT trap triggers in pipeline

# ✅ Correct: Explicit cleanup on error paths
function_without_trap() {
  local tmp="$(mktemp)"

  # Write content
  if ! cat > "${tmp}"; then
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  fi

  # Move to destination
  if ! mv "${tmp}" "/destination"; then
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  fi

  # Success - temp file moved
  return 0
}
```

**Why traps fail in utility functions**:
- EXIT trap is process-level, not function-level
- In pipelines, each command runs in a subshell with separate trap context
- Restoring traps with `eval "trap..."` can trigger them immediately
- Test frameworks (like bats) rely on traps and will break

**Better approach**:
- Use explicit error checking (`if ! command; then cleanup; return 1; fi`)
- Accept that temp files may leak on SIGKILL (use hidden prefix to avoid conflicts)
- Keep utility functions stateless and side-effect free

**Reference**: See `modules/io.sh::atomic_write()` for production implementation

### Source Guard for Libraries with Readonly Variables

**Critical**: Libraries that define readonly variables MUST use source guards to prevent "readonly variable" errors when sourced multiple times.

```bash
# ❌ Wrong: No source guard - fails on second source
# lib/defaults.sh
readonly DEFAULT_TOPOLOGY="reality-only"
readonly DEFAULT_VERSION="latest"

# commands/install.sh sources twice via chain:
. lib/defaults.sh        # First source - OK
. lib/args.sh           # Second source via lib/args.sh - ERROR!
  └─ . lib/defaults.sh  # "DEFAULT_TOPOLOGY: readonly variable"

# ✅ Correct: Add idempotent source guard
# lib/defaults.sh
[[ -n "${_XRF_DEFAULTS_LOADED:-}" ]] && return 0
readonly _XRF_DEFAULTS_LOADED=1

readonly DEFAULT_TOPOLOGY="reality-only"
readonly DEFAULT_VERSION="latest"
```

**Why this pattern is needed**:
- Bash doesn't prevent multiple sourcing of the same file
- `readonly` variables cannot be reassigned (even to same value)
- Complex projects often have transitive sourcing chains
- Source guard makes libraries idempotent and safe to source multiple times

**Best practices**:
- Use library-specific guard variable (e.g., `_XRF_DEFAULTS_LOADED`)
- Check guard at top of file before any readonly declarations
- Make guard itself readonly to prevent accidental modification
- Use early return (`return 0`) to skip re-sourcing

**Common scenarios requiring source guards**:
1. Libraries with readonly constants (defaults, config values)
2. Shared utilities sourced by multiple scripts
3. Hierarchical sourcing (A sources B, C sources both A and B)

**Reference**: Fixed in commit 3904ccb (2025-11-11)

### Module Dependency Management

**Critical**: When a module uses constants or functions from another module, it MUST explicitly source that dependency. Shellcheck disable comments (SC2154) are NOT a substitute for proper dependency management.

```bash
# ❌ Wrong: Using constants without sourcing their definition
# lib/health_check.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/modules/state.sh"
. "${HERE}/services/xray/common.sh"

health::check_certificates() {
  # shellcheck disable=SC2154  # DEFAULT_XRAY_CERT_DIR from lib/defaults.sh
  cert_dir="${DEFAULT_XRAY_CERT_DIR}"  # Bug: lib/defaults.sh never sourced!

  # cert_dir is empty string, checks /fullchain.pem instead of
  # /usr/local/etc/xray/certs/fullchain.pem
  [[ -f "${cert_dir}/fullchain.pem" ]] || return 1
}

# ✅ Correct: Explicitly source all dependencies
# lib/health_check.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/defaults.sh
. "${HERE}/lib/defaults.sh"  # Source before using DEFAULT_XRAY_CERT_DIR
# shellcheck source=modules/state.sh
. "${HERE}/modules/state.sh"
# shellcheck source=services/xray/common.sh
. "${HERE}/services/xray/common.sh"

health::check_certificates() {
  # shellcheck disable=SC2154  # DEFAULT_XRAY_CERT_DIR from lib/defaults.sh
  cert_dir="${DEFAULT_XRAY_CERT_DIR}"  # Now correctly defined

  # Checks correct path: /usr/local/etc/xray/certs/fullchain.pem
  [[ -f "${cert_dir}/fullchain.pem" ]] || return 1
}
```

**Why this matters**:
- Undefined variables default to empty string in bash (with `set -u` they cause errors)
- Empty strings in path constructions lead to checking wrong locations (e.g., `/file` instead of `/dir/file`)
- Shellcheck SC2154 warnings indicate missing dependencies, not permission to ignore them
- Tests may pass if test environment accidentally provides the missing variables

**Dependency Management Checklist**:
1. **Identify all external constants/functions** used in your module
2. **Source their defining modules** at the top of your file
3. **Add shellcheck source comments** for static analysis to follow
4. **Document dependencies** in function documentation (Globals section)
5. **Use source guards** in all library files to prevent double-sourcing issues

**Common dependency sources**:
- `lib/defaults.sh` - Project-wide default values (DEFAULT_*)
- `lib/core.sh` - Core utilities (core::log, core::with_flock)
- `modules/io.sh` - I/O utilities (io::ensure_dir, io::atomic_write)
- `modules/state.sh` - State management (state::path, state::load)
- `services/xray/common.sh` - Xray utilities (xray::prefix, xray::generate_shortid)

**Reference**: Fixed in commit b5cc468 (2025-11-12) - lib/health_check.sh missing lib/defaults.sh source

### Network Operations and Error Recovery

**Critical**: Network operations (downloads, API calls) must implement retry logic and provide actionable error messages.

```bash
# ❌ Wrong: Single attempt, generic error message
if [[ -z "${sha}" ]]; then
  local dgst_content
  dgst_content="$(curl -fsSL "${url}.dgst" 2>/dev/null)" || true
  if [[ -n "${dgst_content}" ]]; then
    sha="$(xray::extract_sha256_from_dgst "${dgst_content}")"
  fi
fi

if [[ -z "${sha}" ]]; then
  core::log error "missing SHA256 checksum" "{}"
  exit 5
fi

# ✅ Correct: Retry with exponential backoff + actionable error message
if [[ -z "${sha}" ]]; then
  local dgst_content
  core::log debug "downloading checksum file with retry" "$(printf '{"url":"%s.dgst"}' "${url}")"
  # Retry checksum download up to 3 times with exponential backoff
  if dgst_content="$(core::retry 3 curl -fsSL "${url}.dgst" 2>&1)"; then
    core::log debug "checksum file downloaded successfully" "{}"
    sha="$(xray::extract_sha256_from_dgst "${dgst_content}")"
  else
    core::log warn "checksum download failed after retries" "$(printf '{"dgst_url":"%s.dgst"}' "${url}")"
  fi
fi

if [[ -z "${sha}" ]]; then
  core::log error "missing SHA256 checksum" "$(printf '{"dgst_url":"%s.dgst","hint":"Network issue or file unavailable"}' "${url}")"
  core::log info "workaround: manually verify and set checksum" "$(printf '{"example":"XRAY_SHA256=<64-char-hex> xrf install ...","get_checksum":"curl -fsSL %s.dgst"}' "${url}")"
  exit 5
fi
```

**Why this matters**:
- Network operations are inherently unreliable (timeouts, DNS issues, firewalls)
- Transient failures can often be resolved with retries
- Users need clear guidance when automation fails
- Workarounds prevent complete installation failure

**Error Message Best Practices**:
1. **Explain what failed**: Include URL, file name, or specific operation
2. **Suggest workarounds**: Provide environment variables or manual steps
3. **Show examples**: Give copy-paste ready commands
4. **Log level hierarchy**: Use `warn` for retryable failures, `error` for terminal failures

**Reference**: Fixed in commit 171c272 (2025-11-12) - services/xray/install.sh checksum download retry logic

### Real-World Trap Failure Case Study

**Problem**: The `lib/backup.sh` functions `backup::create` and `backup::restore` used EXIT traps, causing "tmpdir: unbound variable" errors when called from error paths.

```bash
# ❌ Wrong: EXIT trap in backup::create (original code)
backup::create() {
  local tmpdir
  tmpdir=$(mktemp -d -t xray-backup.XXXXXX)
  trap 'rm -rf "${tmpdir}" 2>/dev/null || true' EXIT INT TERM

  # ... backup operations ...

  if ! tar -czf "${backup_file}" -C "${tmpdir}" . 2>/dev/null; then
    core::log error "failed to create backup archive" "$(printf '{"file":"%s"}' "${backup_file}")"
    return 1  # Bug: EXIT trap tries to access ${tmpdir}, but variable scope issues
  fi
  # ... rest of function ...
}

# When called from commands/install.sh error path:
# 1. install.sh calls backup::create (creates trap)
# 2. tar fails, function returns 1
# 3. install.sh ERR trap fires
# 4. backup::create EXIT trap also fires
# 5. Error: "tmpdir: unbound variable" because trap context is different
```

**Fix**: Remove traps, add explicit cleanup on all error paths

```bash
# ✅ Correct: Explicit cleanup without traps
backup::create() {
  # Use hidden prefix to avoid conflicts if cleanup fails (CWE-362)
  local tmpdir
  tmpdir=$(mktemp -d -t .xray-backup.XXXXXX)

  # ... copy operations with error handling ...

  if ! cp -a "${xray_etc}" "${tmpdir}/xray" 2>/dev/null; then
    core::log error "failed to copy xray configuration" "{}"
    rm -rf "${tmpdir}" 2>/dev/null || true  # Explicit cleanup
    return 1
  fi

  # Create tar.gz archive
  if ! tar -czf "${backup_file}" -C "${tmpdir}" . 2>/dev/null; then
    core::log error "failed to create backup archive" "$(printf '{"file":"%s"}' "${backup_file}")"
    rm -rf "${tmpdir}" 2>/dev/null || true  # Explicit cleanup
    return 1
  fi

  # Cleanup temporary directory (archive created successfully)
  rm -rf "${tmpdir}" 2>/dev/null || true

  # ... rest of function ...
}
```

**Key Insights**:
- **Trap scope confusion**: EXIT traps fire when *process* exits, not when *function* returns
- **Complex call chains**: When utility functions are called from error handlers, traps can nest unpredictably
- **Variable visibility**: Local variables may not be accessible in trap context depending on execution flow
- **Hidden prefix pattern**: Use `.` prefix for temp files (`.xray-backup.XXXXXX`) to minimize conflicts if cleanup fails

**When to use traps**:
- ✅ Main scripts (commands/*.sh) with clear lifecycle
- ✅ Standalone scripts that run in their own process
- ❌ Utility functions in lib/ or modules/
- ❌ Functions called from complex contexts (error handlers, pipelines)

**Reference**: Fixed in commit 171c272 (2025-11-12) - lib/backup.sh EXIT trap removal

### Variable Pollution Defense
```bash
# ❌ Wrong: Directly sourcing external files may pollute variables
. /etc/os-release  # VERSION gets overwritten by system version

# ✅ Correct: Subshell isolation
os_info=$(source /etc/os-release 2>/dev/null && echo "${ID:-unknown} ${VERSION_ID:-unknown}")
```

### Atomic File Operations and Security
```bash
# ❌ Wrong: Predictable temp file names, cross-partition mv
io::atomic_write_old() {
  local dst="${1}"
  tmp="$(mktemp "${dst}.XXXX.tmp")"  # Predictable pattern, wrong location
  cat > "${tmp}"
  mv -f "${tmp}" "${dst}"  # May fail if cross-partition
}

# ✅ Correct: Secure temp file creation with explicit error handling
io::atomic_write() {
  local dst="${1}" mode="${2:-0644}"
  local dstdir tmp
  dstdir="$(dirname "${dst}")"

  # Create in destination dir (same partition = atomic mv)
  # Use hidden prefix + XXXXXX for unpredictability
  tmp="$(mktemp -p "${dstdir}" .atomic-write.XXXXXX.tmp)" || return 1

  # Write content to temp file
  if ! cat > "${tmp}"; then
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  fi

  # Move to final location (atomic on same filesystem)
  if ! mv -f "${tmp}" "${dst}"; then
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  fi

  chmod "${mode}" "${dst}" || true
  return 0
}
```

**Security Benefits**:
- ✅ **Same-partition operation**: Temp file in destination directory ensures atomic `mv`
- ✅ **Unpredictable names**: `mktemp XXXXXX` prevents symlink attacks (CWE-59)
- ✅ **Hidden prefix**: `.atomic-write.` avoids naming conflicts
- ✅ **Explicit error handling**: Cleanup on each failure path
- ✅ **No trap interference**: Works correctly in pipelines and test frameworks
- ✅ **Race condition防护**: Prevents TOCTOU attacks (CWE-362)

**References**:
- [CWE-362: Concurrent Execution using Shared Resource](https://cwe.mitre.org/data/definitions/362.html)
- [CWE-59: Improper Link Resolution](https://cwe.mitre.org/data/definitions/59.html)

### Permission and Ownership Edge Cases

When dealing with files that may be created by different users (root vs non-root), always ensure **both permissions AND ownership** are correct. This is especially critical for lock files and shared resources.

**⚠️ Common Scenario:**
```bash
# Run 1: sudo xrf install → creates lock file owned by root:root 0644
# Run 2: xrf status (non-root user) → lock file still root-owned
# Result: exec 200>> "${lock}" fails (cannot append to root-owned file)
```

**❌ Wrong: Only fixing permissions**
```bash
if test -f "${lock}"; then
  # File exists from previous run
  chmod 0644 "${lock}" 2>/dev/null || true
  # Bug: still owned by root, non-root user cannot write
fi

exec 200>> "${lock}"  # Fails if file is root-owned
```

**✅ Correct: Fix both ownership and permissions**
```bash
if test -f "${lock}"; then
  # File exists, may be root-owned from previous sudo run
  # Fix ownership first
  if ! chown "$(id -u):$(id -g)" "${lock}" 2>/dev/null; then
    sudo chown "$(id -u):$(id -g)" "${lock}" 2>/dev/null || true
  fi
  # Then fix permissions
  if ! chmod 0644 "${lock}" 2>/dev/null; then
    sudo chmod 0644 "${lock}" 2>/dev/null || true
  fi
fi

exec 200>> "${lock}"  # Now succeeds for all users
```

**Why this matters**:
- Mixed sudo/non-sudo usage is common in deployment tools
- Lock files must be writable by all legitimate users
- Permissions alone don't guarantee write access (ownership matters)
- Fixes CWE-283 (Unverified Ownership)

**Reference**: See `lib/core.sh::with_flock()` for production implementation

### Upstream Tool Compatibility

When integrating with external tools (e.g., Xray, Docker, systemd), their output format may change between versions. Always design parsers to be robust and backward-compatible.

**⚠️ Real-World Case: Xray x25519 Format Change**

Xray-core changed x25519 output format in v25.8.31+ (2024):
```bash
# Old format (pre-v25.8.31)
Private key: <base64-value>
Public key: <base64-value>

# New format (v25.8.31+)
PrivateKey: <base64url-value>
Password: <base64url-value>      ← Public key renamed to discourage sharing
Hash32: <base64url-value>         ← VLESS Encryption only
```

**❌ Fragile: Hard-coded pattern matching**
```bash
# Breaks when format changes
private_key=$(echo "${output}" | grep "Private key:" | awk '{print $3}')
public_key=$(echo "${output}" | grep "Public key:" | awk '{print $3}')
```

**✅ Robust: Normalized label matching with multiple patterns**
```bash
x25519::parse_keys() {
  local output="${1}" line label value normalized
  local private="" public=""

  while IFS= read -r line; do
    [[ "${line}" != *:* ]] && continue

    label="${line%%:*}"
    value="${line#*:}"

    # Normalize: lowercase, remove spaces, keep only letters
    normalized="${label,,}"
    normalized="${normalized//[[:space:]]/}"
    normalized="${normalized//[^a-z]/}"
    value="$(trim "${value}")"

    # Match both old and new formats
    # "Private key" → "privatekey", "PrivateKey" → "privatekey"
    if [[ "${normalized}" == *private*key* || "${normalized}" == "privatekey" ]]; then
      [[ -z "${private}" ]] && private="${value}"
    fi

    # "Public key" → "publickey", "PublicKey" → "publickey"
    # "Password" → "password" (new format)
    if [[ "${normalized}" == *public*key* || "${normalized}" == "publickey" || "${normalized}" == "password" ]]; then
      [[ -z "${public}" ]] && public="${value}"
    fi
  done <<< "${output}"

  printf '%s\n%s\n' "${private}" "${public}"
}
```

**Best Practices for External Tool Integration**:

1. **Test with actual tool output**, not mocked data
   ```bash
   # Download and test with real binary
   xray x25519 > test_output.txt
   ./parse_function.sh < test_output.txt
   ```

2. **Normalize before matching**
   - Convert to lowercase
   - Remove whitespace
   - Strip special characters
   - Use pattern matching (`*substring*`) over exact matches

3. **Add version-specific test cases**
   ```bash
   @test "x25519::parse_keys handles old format (pre-v25.8.31)" {
     output=$(x25519::parse_keys 'Private key: ABC=\nPublic key: XYZ=')
     [ "${output}" = $'ABC=\nXYZ=' ]
   }

   @test "x25519::parse_keys handles new format (v25.8.31+)" {
     output=$(x25519::parse_keys 'PrivateKey: ABC\nPassword: XYZ\nHash32: 123')
     [ "${output}" = $'ABC\nXYZ' ]
   }
   ```

4. **Document format changes in comments**
   ```bash
   # In Xray v25.8.31+, the public key field was renamed from
   # "Public key" to "Password" to discourage users from sharing it
   # publicly (GitHub discussion #5084).
   if [[ "${normalized}" == "password" ]]; then
     public="${value}"
   fi
   ```

5. **Check upstream changelogs and discussions**
   - Review GitHub releases, discussions, issues
   - Search for format change announcements
   - Understand *why* the change was made (affects parser design)

6. **Fail gracefully with actionable errors**
   ```bash
   if [[ -z "${private}" || -z "${public}" ]]; then
     core::log error "failed to parse x25519 keypair" \
       '{"suggestion":"verify xray x25519 output format","output_sample":"'"${output:0:100}"'"}'
     return 1
   fi
   ```

**Anti-Patterns to Avoid**:
- ❌ Relying on exact whitespace or capitalization
- ❌ Using hardcoded array indices (e.g., `awk '{print $3}'`)
- ❌ Skipping validation when parsing succeeds
- ❌ Not testing with multiple tool versions
- ❌ Ignoring upstream release notes

**Reference**: Fixed in commit dfbce58 (2025-11-16) - lib/x25519.sh parser upgrade for Xray v25.8.31+ compatibility

## Testing Guidelines
- Test framework: bats-core with 119 unit tests across 5 test files.
- Fast feedback: `make lint && make fmt && make test-unit`.
- Run tests:
  - `make test` — Run all tests (unit + integration)
  - `make test-unit` — Run unit tests only
  - `bats -t tests/unit/*.bats` — Run with verbose output
- Functional checks:
  - Dry config test is automatic and cannot be skipped (see ADR-007 in CLAUDE.md).
  - Avoid touching system paths by overriding `XRF_PREFIX` and `XRF_ETC` to a temp dir.
- Prefer validating inputs and error codes; don't print secrets.
- Test coverage: ~85% (119 tests across lib/args.sh, lib/core.sh, lib/plugins.sh, lib/validators.sh, modules/io.sh, services/xray/common.sh)
  - Code reuse tests: 6 tests for xray::generate_shortid()
  - Log format tests: 5 tests for unified logging
  - Security tests: 12 tests for RFC-compliant domain validation
  - Recent additions (2025-11): +23 tests as part of code duplication elimination

## Xray Configuration Best Practices

### Vision-Reality Topology
- **Reality Port**: 443 (standard HTTPS, officially recommended)
- **Vision Port**: 8443 (real TLS, avoids conflict with Reality)
- **Caddy HTTPS Port**: 8444 (avoids occupying 443)

### Certificate Permissions
```bash
# Xray service runs as xray user, needs to read private key
chmod 644 fullchain.pem
chmod 640 privkey.pem
chown root:xray *.pem
```

### VLESS+REALITY Core Concepts
- REALITY protocol **does not require domain ownership**
- SNI is used for camouflage (e.g., `www.microsoft.com` is a valid config)
- Reality cannot be forwarded through regular reverse proxies (like Caddy)

### TLS Configuration
```json
{
  "minVersion": "1.3",  // 2025 security standard, enforce TLS 1.3
  "serverName": "example.com"
  // Note: No longer use ocspStapling (Let's Encrypt stopped OCSP service on 2025-01-30)
}
```

### shortIds Configuration
- shortIds is a server-side **pool** that clients choose from
- Not "must be unique per client", but "provides differentiation capability"
- Single shortId is sufficient for personal use; multi-user scenarios can expand the pool

### spiderX Parameter
- spiderX is a **client parameter**, not a server-enforced value
- Server-side `"spiderX": "/"` is an example path
- Client link `spx=%2F` is the actual value used

## Certificate Management

### Automation Solution Choice
- ✅ **Caddy**: Mature automatic certificate management (reference: 233boy/Xray)
- ❌ **acme.sh**: Lacks complete integration logic, high maintenance complexity

### Certificate Sync Atomicity
```bash
# ✅ Use same-partition temp dir + mv (POSIX guarantees atomicity)
tmpdir=$(mktemp -d -p "${TARGET_DIR}" .sync.XXXXXX)
cp source "${tmpdir}/file"
chmod 644 "${tmpdir}/file"
mv -f "${tmpdir}/file" "${TARGET_DIR}/file"  # Atomic operation

# ⚠️ Avoid cross-partition mv (non-atomic, actually copy + delete)
mktemp -d -p /tmp  # /tmp usually on different partition or ramfs
```

### Certificate Validation (Supports RSA and ECDSA)
```bash
# ✅ Universal method: Compare public key hashes
cert_pub=$(openssl x509 -in cert.pem -pubkey -noout | sha256sum | awk '{print $1}')
key_pub=$(openssl pkey -in key.pem -pubout | sha256sum | awk '{print $1}')
[[ "${cert_pub}" == "${key_pub}" ]] || exit 1

# ❌ Old method: RSA only
cert_modulus=$(openssl x509 -noout -modulus -in cert.pem | openssl md5)
key_modulus=$(openssl rsa -noout -modulus -in key.pem | openssl md5)
```

### Sync Failure Rollback
```bash
# Backup existing certificates
backup_dir="${TARGET_DIR}/.backup.$$"
cp -a existing_cert "${backup_dir}/"

# Atomic move of both files
mv -f new_fullchain.pem target/
if ! mv -f new_privkey.pem target/; then
  # Rollback
  mv -f "${backup_dir}/fullchain.pem" target/
  exit 1
fi
rm -rf "${backup_dir}"
```

### systemd Integration Strategy
```ini
# ✅ Use Timer (reliable, predictable)
[Timer]
OnBootSec=2min
OnUnitActiveSec=10min  # Certificate changes infrequently, 10 min is sufficient
Persistent=true

# ❌ Avoid Path unit (inotify unreliable on nested dirs/NFS)
[Path]
PathChanged=/path/to/certs  # Has built-in delay, unreliable on some filesystems
```

### Certificate Validity Check
```bash
# Check if expired (reject sync)
openssl x509 -in cert.pem -noout -checkend 0 || exit 1

# 7-day warning window (24 hours too short)
openssl x509 -in cert.pem -noout -checkend 604800 || log warn "expires soon"
```

### Concurrency Protection
```bash
# ✅ Certificate sync script must add global lock (prevent systemd timer concurrent triggers)
exec 200>/var/lock/caddy-cert-sync.lock
if ! flock -n 200; then
  log info "another sync process is running, skipping"
  exit 0
fi

# Existing sync logic...
```

### Xray Restart Strategy
**Important**: Xray-core **does not support** SIGHUP graceful reload
- Reference: https://github.com/XTLS/Xray-core/discussions/1060
- Official install scripts never include `ExecReload` directive

```bash
# ❌ Wrong: Xray doesn't support reload
systemctl reload xray

# ✅ Correct: Must restart after certificate update
systemctl restart xray
```

### systemd Service Hardening
```ini
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cert-sync

# Security restrictions
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/usr/local/etc/xray/certs
NoNewPrivileges=true

# Resource limits
MemoryMax=50M
TasksMax=10
```

## Parameter System Design

### Unified Parameter Format
```bash
# install.sh and xrf use exactly the same parameters
--topology reality-only|vision-reality
--domain <domain>           # Required for vision-reality
--version <version>         # default: latest
--plugins <plugin1,plugin2>
--debug

# Pipe-friendly (env vars don't work in pipes)
curl -sL install.sh | bash -s -- --domain example.com
```

### Parameter Validation Principles
```bash
# Input validation
args::validate_topology()  # Only allow reality-only|vision-reality
args::validate_domain()    # RFC compliant + forbid internal domains
args::validate_version()   # latest or vX.Y.Z

# Cross validation
args::validate_config()    # vision-reality requires domain

# ✅ Correct: Exit immediately on validation failure
args::validate_topology "${2}" || return 1
TOPOLOGY="${2}"

# ❌ Wrong: Continue execution after validation failure
args::validate_topology "${2}"  # Not checking return value
TOPOLOGY="${2}"
```

### Domain Validation (RFC Compliant + Extended)

**Updated**: 2025-11-10 - Phase 1 Security Enhancements

The `validators::domain()` function now implements comprehensive validation:

```bash
# ✅ RFC 1035 format validation
[[ "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]

# ✅ IPv4 Private addresses (RFC 1918 + RFC 3927)
case "${domain}" in
  # Loopback and special
  localhost|*.local|127.*|0.0.0.0) return 1 ;;

  # RFC 1918 private networks
  10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*) return 1 ;;

  # RFC 3927 link-local addresses (NEW)
  169.254.*) return 1 ;;

  # RFC 6761 special-use domain names (NEW)
  *.test|*.invalid) return 1 ;;
esac

# ✅ IPv6 Private addresses (NEW - RFC 4193, RFC 4291)
# - ::1 (loopback)
# - fc00::/7 and fd00::/8 (unique local addresses - RFC 4193)
# - fe80::/10 (link-local - RFC 4291)
if [[ "${domain}" =~ ^::1$ ]] || \
   [[ "${domain}" =~ ^[fF][cCdD][0-9a-fA-F]{2}: ]] || \
   [[ "${domain}" =~ ^[fF][eE]80: ]]; then
  return 1
fi
```

**Rejected Domains**:
- RFC 1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- RFC 3927: `169.254.0.0/16` (link-local)
- RFC 6761: `.test`, `.invalid` (special-use TLDs)
- IPv6 loopback: `::1`
- IPv6 ULA: `fc00::/7`, `fd00::/8` (RFC 4193)
- IPv6 link-local: `fe80::/10` (RFC 4291)

## Common Commands

### Build and Install
```bash
# Local install
bin/xrf install --topology reality-only

# Vision-Reality topology with plugins
bin/xrf install --topology vision-reality --domain your.domain.com --plugins cert-auto

# One-liner install (pipe-friendly)
curl -sL install.sh | bash -s -- --topology reality-only

# Uninstall
bin/xrf uninstall
```

### Debugging
```bash
# Enable debug logs
XRF_DEBUG=true bin/xrf install --topology reality-only

# JSON format logs
XRF_JSON=true bin/xrf install --topology reality-only

# View service status
systemctl status xray
journalctl -u xray -f

# Test certificate sync
/usr/local/bin/caddy-cert-sync example.com

# Verify systemd timer
systemctl list-timers cert-reload.timer
systemctl status cert-reload.timer
```

### Endpoint Verification
```bash
# Vision endpoint test
timeout 3 bash -c "</dev/tcp/domain.com/8443" && echo "Vision accessible"

# Reality endpoint test
timeout 3 bash -c "</dev/tcp/1.2.3.4/443" && echo "Reality accessible"
```

## Commit & Pull Request Guidelines
- Commits: imperative, concise, scoped (e.g., "Fix …", "Add …", "Implement …").
- Group related changes; keep diffs minimal; reference areas (commands/lib/services/plugins) in the body when useful.
- PRs must include:
  - Summary of changes and rationale
  - How to validate (exact commands/env vars)
  - Screenshots or logs if behavior changes
  - Linked issues (if any)

## Plugin System

### Plugin Metadata
Add new plugin at `plugins/available/<id>/plugin.sh` with metadata:
- `XRF_PLUGIN_ID` - Unique plugin identifier (required)
- `XRF_PLUGIN_VERSION` - Semantic version (required)
- `XRF_PLUGIN_DESC` - Human-readable description (required)
- `XRF_PLUGIN_HOOKS` - Array of hook names (required)
- `XRF_PLUGIN_DEPS` - Array of command dependencies (optional)

Supported hooks: `configure_pre|configure_post|deploy_post|service_setup|service_remove|links_render|uninstall_pre`

### Plugin Dependencies
**Feature**: Automatic dependency installation (v1.2.0+)

Plugins can declare dependencies using `XRF_PLUGIN_DEPS` array. When a plugin is enabled, the system will:
1. Check if all dependencies are installed
2. Prompt user to install missing dependencies (interactive mode)
3. Auto-install in non-interactive mode or when `XRF_AUTO_INSTALL_DEPS=true`

```bash
# Plugin metadata example
XRF_PLUGIN_ID="links-qr"
XRF_PLUGIN_VERSION="1.2.0"
XRF_PLUGIN_DESC="Render QR codes for client links"
XRF_PLUGIN_HOOKS=("links_render")
XRF_PLUGIN_DEPS=("qrencode")  # Auto-install qrencode when enabling plugin
```

**Behavior**:
```bash
# Interactive mode - prompts user
xrf plugin enable links-qr
# Output:
# [INFO] Plugin links-qr requires: qrencode
# Install missing dependencies? [Y/n] y
# [INFO] Installing packages: qrencode (using yum)
# [INFO] Packages installed successfully: qrencode
# enabled: links-qr

# Non-interactive mode - auto-installs
XRF_AUTO_INSTALL_DEPS=true xrf plugin enable links-qr

# CI/CD environments - auto-detects non-interactive
echo | xrf plugin enable links-qr  # Auto-installs without prompt
```

**Supported package managers**: apt-get, yum, dnf, apk, zypper, pacman

### Plugin Security
- Validate IDs with `plugins::validate_id`; never traverse paths
- Use repo helpers for path resolution
- Plugin dependencies are installed via system package manager with sudo fallback

---

**Architecture Decisions & Lessons Learned**: See [@CLAUDE.md](./CLAUDE.md) for ADRs and core lessons.
