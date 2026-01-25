#!/usr/bin/env bash
# Core utils: strict-mode (only via init), logging, retry
# NOTE: This file is sourced. Strict mode (set -euo pipefail) is set by core::init()
#       which must be called by the main script.

# Source guard: prevent double-sourcing
[[ -n "${_XRF_CORE_LOADED:-}" ]] && return 0
readonly _XRF_CORE_LOADED=1

##
# Initialize strict mode and parse global flags
#
# Sets up bash strict mode (set -euo pipefail -E) and parses
# global flags like --json and --debug. Must be called at the
# start of every main script.
#
# Arguments:
#   $@ - Command-line arguments (optional)
#
# Globals:
#   XRF_JSON - Set to "true" if --json flag present
#   XRF_DEBUG - Set to "true" if --debug flag present
#
# Returns:
#   0 - Always succeeds
#
# Side Effects:
#   - Enables bash strict mode (set -euo pipefail -E)
#   - Sets up ERR trap for error handling
#
# Example:
#   core::init "${@}"
##
core::init() {
  set -euo pipefail -E
  export XRF_JSON="${XRF_JSON:-false}"
  export XRF_DEBUG="${XRF_DEBUG:-false}"
  for arg in "${@}"; do
    case "${arg}" in
      --json) XRF_JSON=true ;;
      --debug) XRF_DEBUG=true ;;
      *) ;;
    esac
  done
  trap 'core::error_handler "${?}" "${LINENO}" "${BASH_COMMAND}"' ERR
}

##
# ERR trap handler for error logging
#
# Internal function called by ERR trap to log error details before exit.
# Uses critical level to indicate severe error condition.
#
# Arguments:
#   $1 - Return code (number, required)
#   $2 - Line number (number, required)
#   $3 - Failed command (string, required)
#
# Returns:
#   Never returns (exits with return code from $1)
#
# Example:
#   trap 'core::error_handler "${?}" "${LINENO}" "${BASH_COMMAND}"' ERR
##
core::error_handler() {
  local return_code="${1}" line_number="${2}" command="${3}"
  # Use critical level for ERR trap (doesn't exit, trap will handle that)
  core::log critical "ERR trap" "$(printf '{"rc":%d,"line":%d,"cmd":"%s"}' "${return_code}" "${line_number}" "${command//\"/\\\"}")"
  exit "${return_code}"
}

##
# Generate ISO 8601 UTC timestamp
#
# Returns:
#   ISO 8601 timestamp string (YYYY-MM-DDTHH:MM:SSZ)
#
# Example:
#   ts="$(core::ts)"  # "2025-11-10T12:34:56Z"
##
core::ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

##
# Format log message for output (internal helper)
#
# Internal function used by core::log to format messages.
# Separated to reduce cyclomatic complexity and improve testability.
#
# Arguments:
#   $1 - Log level (string, required)
#   $2 - Message (string, required)
#   $3 - Context JSON (string, required)
#
# Globals:
#   XRF_JSON - If "true", output JSON format
#
# Output:
#   Formatted log line to stdout (caller redirects to stderr)
#
# Returns:
#   0 - Always succeeds
##
core::log_format() {
  local lvl="${1}"
  local msg="${2}"
  local ctx="${3}"

  # Normalize fatal/critical to uppercase for visibility in text output
  local display_lvl="${lvl}"
  if [[ "${lvl}" == "fatal" || "${lvl}" == "critical" ]]; then
    display_lvl="${lvl^^}"
  fi

  # Check if context is empty (whitespace-only or empty object)
  local ctx_is_empty="false"
  local ctx_trimmed="${ctx//[[:space:]]/}"
  [[ -z "${ctx_trimmed}" || "${ctx_trimmed}" == "{}" ]] && ctx_is_empty="true"

  if [[ "${XRF_JSON}" == "true" ]]; then
    local json_ctx="${ctx}"
    [[ "${ctx_is_empty}" == "true" ]] && json_ctx="{}"
    printf '{"ts":"%s","level":"%s","msg":"%s","ctx":%s}\n' "$(core::ts)" "${lvl}" "${msg}" "${json_ctx}"
  else
    if [[ "${ctx_is_empty}" == "true" ]]; then
      printf '[%s] %-8s %s\n' "$(core::ts)" "${display_lvl}" "${msg}"
    else
      printf '[%s] %-8s %s %s\n' "$(core::ts)" "${display_lvl}" "${msg}" "${ctx}"
    fi
  fi
}

##
# Structured logging to stderr
#
# Logs messages in text or JSON format depending on XRF_JSON.
# All output goes to stderr to avoid contaminating function
# return values. Debug messages are filtered unless XRF_DEBUG=true.
#
# Supports log levels: debug, info, warn, error, critical, fatal
# - fatal: Immediately exits with code 1 after logging
# - critical: Logs severe error but does not exit
# - error/warn/info/debug: Standard log levels
#
# Arguments:
#   $1 - Log level (string, required) - debug|info|warn|error|critical|fatal
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
#   0 - Success (debug/info/warn/error/critical)
#   Exits 1 - If level is fatal
#
# Example:
#   core::log info "Operation completed" '{"duration_ms":123}'
#   core::log error "Failed to read file" "$(printf '{"file":"%s"}' "${path}")"
#   core::log critical "Database corrupted" '{"db":"/var/lib/app/data.db"}'
#   core::log fatal "Missing required configuration"  # Exits immediately
##
core::log() {
  local lvl="${1}"
  shift
  local msg="${1}"
  shift || true
  local ctx="${1-}"
  [[ -z "${ctx}" ]] && ctx="{}"

  # Early return: filter debug messages unless XRF_DEBUG is true
  [[ "${lvl}" == "debug" && "${XRF_DEBUG}" != "true" ]] && return 0

  # Format and output to stderr (avoid contaminating function outputs)
  core::log_format "${lvl}" "${msg}" "${ctx}" >&2

  # Fatal errors exit immediately
  [[ "${lvl}" == "fatal" ]] && exit 1

  return 0
}

##
# Retry command with exponential backoff
#
# Executes a command up to max_attempts times, with exponentially
# increasing delays between attempts (1s, 4s, 9s, 16s, 25s, ...).
# Formula: sleep(attempt^2)
#
# Arguments:
#   $1 - Maximum attempts (number, optional, default: 3)
#   $@ - Command and arguments to execute (required)
#
# Returns:
#   0 - Command succeeded within max_attempts
#   1 - All attempts failed
#
# Example:
#   core::retry 5 curl -fsSL https://example.com/file
#   core::retry wget -O /tmp/file https://example.com/file  # Uses default 3 attempts
##
core::retry() {
  local max_attempts="${1:-3}"
  shift
  local attempt=0
  until "${@}"; do
    attempt=$((attempt + 1))
    [[ ${attempt} -ge ${max_attempts} ]] && return 1
    sleep $((attempt * attempt))
  done
}

##
# Ensure lock file is writable by current user
#
# Handles mixed sudo/non-sudo scenarios where lock file may be
# owned by root from a previous run. Attempts to fix ownership
# and permissions to allow the current user to write to the lock file.
#
# Arguments:
#   $1 - Lock file path (string, required)
#
# Returns:
#   0 - Lock file is writable or doesn't exist
#   1 - Failed to make lock file writable
#
# Security:
#   - Fixes CWE-283 (Unverified Ownership) by ensuring correct ownership
#   - Uses sudo only when necessary (principle of least privilege)
#   - Safe to call multiple times (idempotent)
#
# Example:
#   core::ensure_lock_writable "/var/lib/xray-fusion/locks/install.lock"
##
core::ensure_lock_writable() {
  local lock="${1}"

  # If file doesn't exist, nothing to fix
  [[ ! -f "${lock}" ]] && return 0

  local has_sudo=false
  command -v sudo > /dev/null 2>&1 && has_sudo=true

  # Fix ownership (may be root-owned from previous sudo run)
  if ! chown "$(id -u):$(id -g)" "${lock}" 2> /dev/null; then
    if ! ${has_sudo} || ! sudo chown "$(id -u):$(id -g)" "${lock}" 2> /dev/null; then
      core::log warn "cannot fix lock file ownership" "$(printf '{"lock":"%s"}' "${lock//\"/\\\"}")"
      return 1
    fi
  fi

  # Fix permissions (make writable)
  if ! chmod 0644 "${lock}" 2> /dev/null; then
    if ! ${has_sudo} || ! sudo chmod 0644 "${lock}" 2> /dev/null; then
      core::log warn "cannot fix lock file permissions" "$(printf '{"lock":"%s"}' "${lock//\"/\\\"}")"
      return 1
    fi
  fi

  return 0
}

##
# Execute command with exclusive file lock
#
# Acquires a file-based lock before executing the command,
# ensuring mutual exclusion. Handles sudo/non-sudo mixed
# scenarios by fixing ownership and permissions atomically.
#
# Arguments:
#   $1 - Lock file path (string, required)
#   $@ - Command and arguments to execute (required)
#
# Returns:
#   0 - Command succeeded
#   1 - Command failed
#   2 - Missing command argument
#
# Security:
#   - Uses install(1) for atomic file creation (prevents TOCTOU - CWE-362)
#   - Fixes ownership to current user (handles sudo remnants - CWE-283)
#   - Executes in subshell with fd 200 to release lock automatically
#   - Ensures writable lock file for all legitimate users
#
# Example:
#   core::with_flock "/var/lib/app/locks/deploy.lock" deploy_function arg1 arg2
#   core::with_flock "$(state::lock)" configure_and_deploy
##
core::with_flock() {
  local lock="${1}"
  shift || true
  [[ $# -gt 0 ]] || {
    core::log error "with_flock missing command" "$(printf '{"lock":"%s"}' "${lock//\"/\\\"}")"
    return 2
  }
  local dir
  dir="$(dirname "${lock}")"
  if ! mkdir -p "${dir}" 2> /dev/null; then
    core::log warn "mkdir fallback sudo" "$(printf '{"dir":"%s"}' "${dir//\"/\\\"}")"
    sudo mkdir -p "${dir}"
  fi

  # Security: Atomic lock file creation with correct ownership and permissions
  # Use install(1) instead of touch + chown to prevent TOCTOU window
  if ! test -f "${lock}" 2> /dev/null; then
    if ! install -m 0644 -o "$(id -u)" -g "$(id -g)" /dev/null "${lock}" 2> /dev/null; then
      core::log warn "lock file creation needs sudo" "$(printf '{"file":"%s"}' "${lock//\"/\\\"}")"
      # Use install with sudo for atomic creation (single syscall, no TOCTOU)
      sudo install -m 0644 -o "$(id -u)" -g "$(id -g)" /dev/null "${lock}" 2> /dev/null || true
    fi
  fi

  # Ensure lock file is writable (handles previous root runs - CWE-283)
  core::ensure_lock_writable "${lock}" || {
    core::log error "lock file not writable" "$(printf '{"lock":"%s"}' "${lock//\"/\\\"}")"
    return 1
  }

  (
    exec 200>> "${lock}"
    flock 200
    "${@}"
  )
}
