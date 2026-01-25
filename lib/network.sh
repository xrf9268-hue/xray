#!/usr/bin/env bash
# Network utilities for xray-fusion
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_NETWORK_LOADED:-}" ]] && return 0
readonly _XRF_NETWORK_LOADED=1

##
# Retry command with exponential backoff
#
# This function executes a command and retries it if it fails, using
# exponential backoff strategy. This is useful for network operations
# that may experience temporary failures.
#
# Arguments:
#   $1 - Max retries (number, required) - Maximum number of attempts
#   $2 - Initial delay in seconds (number, required) - Starting delay
#   $@ - Command to execute (string, required) - Command and its arguments
#
# Output:
#   Command stdout/stderr (preserved)
#   Debug logs to stderr via core::log
#
# Globals:
#   XRF_DEBUG - If "true", show retry attempt logs
#
# Returns:
#   0 - Command succeeded
#   1 - Command failed after max retries or invalid arguments
#
# Example:
#   network::retry 3 2 curl -fsSL https://example.com
#   network::retry 5 1 download_function arg1 arg2
#
# Backoff Strategy:
#   Attempt 1: Execute immediately
#   Attempt 2: Wait initial_delay (e.g., 2s)
#   Attempt 3: Wait initial_delay * 2 (e.g., 4s)
#   Attempt 4: Wait initial_delay * 4 (e.g., 8s)
#   Attempt N: Wait initial_delay * 2^(N-2)
##
network::retry() {
  local max_retries="${1:-}"
  local initial_delay="${2:-}"
  shift 2 || {
    core::log error "missing required arguments" '{"function":"retry","usage":"network::retry <max_retries> <delay> <command>"}'
    return 1
  }

  # Validate arguments
  if [[ -z "${max_retries}" || -z "${initial_delay}" ]]; then
    core::log error "invalid arguments" '{"function":"retry"}'
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    core::log error "no command specified" '{"function":"retry"}'
    return 1
  fi

  local attempt=0
  local delay="${initial_delay}"

  while [[ ${attempt} -lt ${max_retries} ]]; do
    attempt=$((attempt + 1))

    core::log debug "executing command" "$(printf '{"attempt":%d,"max_retries":%d,"command":"%s"}' ${attempt} ${max_retries} "${1}")"

    # Execute command and capture result
    if "$@"; then
      core::log debug "command succeeded" "$(printf '{"attempt":%d}' ${attempt})"
      return 0
    fi

    # Check if we should retry
    if [[ ${attempt} -lt ${max_retries} ]]; then
      core::log warn "command failed, retrying in ${delay}s" "$(printf '{"attempt":%d,"max_retries":%d,"delay":%d}' ${attempt} ${max_retries} ${delay})"
      sleep "${delay}"
      # Exponential backoff: double the delay for next attempt
      delay=$((delay * 2))
    fi
  done

  core::log error "command failed after ${max_retries} attempts" '{"function":"retry"}'
  return 1
}

##
# Download file with retry logic
#
# This is a convenience wrapper around network::retry for file downloads.
# It tries curl first, then wget, with automatic retries.
#
# Arguments:
#   $1 - URL (string, required)
#   $2 - Output file (string, required)
#   $3 - Max retries (number, optional, default: 3)
#   $4 - Initial delay (number, optional, default: 2)
#
# Returns:
#   0 - Download successful
#   1 - Download failed after retries
#
# Example:
#   network::download_with_retry "https://example.com/file" "/tmp/file"
#   network::download_with_retry "https://example.com/file" "/tmp/file" 5 1
##
network::download_with_retry() {
  local url="${1:-}"
  local output="${2:-}"
  local max_retries="${3:-3}"
  local initial_delay="${4:-2}"

  # Validate arguments
  if [[ -z "${url}" || -z "${output}" ]]; then
    core::log error "missing required arguments" '{"function":"download_with_retry"}'
    return 1
  fi

  # Define download function
  _do_download() {
    local url="${1}"
    local output="${2}"

    # Try curl first
    if command -v curl > /dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 300 "${url}" -o "${output}" 2> /dev/null
      return $?
    fi

    # Fallback to wget
    if command -v wget > /dev/null 2>&1; then
      wget -q --timeout=10 "${url}" -O "${output}" 2> /dev/null
      return $?
    fi

    core::log error "no download tool available (curl/wget)" '{}'
    return 1
  }

  # Use retry mechanism
  network::retry "${max_retries}" "${initial_delay}" _do_download "${url}" "${output}"
}
