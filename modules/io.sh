#!/usr/bin/env bash
# Atomic write + safe install helpers
# NOTE: This module is sourced; strict mode (set -euo pipefail) must be enabled by the caller (e.g., via core::init()).

[[ -n "${_XRF_IO_LOADED:-}" ]] && return 0
readonly _XRF_IO_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"

##
# Ensure directory exists with correct permissions
#
# Creates directory if it doesn't exist, sets permissions if it does.
# Falls back to sudo if permission denied.
#
# Arguments:
#   $1 - Directory path (string, required)
#   $2 - Permissions mode (octal, optional, default: 0755)
#
# Returns:
#   0 - Directory exists with correct permissions
#   1 - Failed to create directory (sudo also failed)
#
# Example:
#   io::ensure_dir "/var/lib/app"           # Create with 0755
#   io::ensure_dir "/etc/app" "0750"        # Create with 0750
##
io::ensure_dir() {
  local dir="${1}"
  local mode="${2:-0755}"

  if [[ -d "${dir}" ]]; then
    chmod "${mode}" "${dir}" || true
    return 0
  fi

  if ! mkdir -p "${dir}" 2> /dev/null; then
    core::log warn "mkdir fallback sudo" "$(printf '{"dir":"%s"}' "$(core::json_escape "${dir}")")"
    if ! core::sudo_cmd mkdir -p "${dir}"; then
      core::log error "failed to create directory" "$(printf '{"dir":"%s"}' "$(core::json_escape "${dir}")")"
      return 1
    fi
  fi

  chmod "${mode}" "${dir}" || true
  return 0
}

##
# Check if path is writable
#
# Arguments:
#   $1 - Path to check (string, required)
#
# Returns:
#   0 - Path is writable
#   1 - Path is not writable or does not exist
#
# Example:
#   io::writable "/tmp" && echo "Can write"
##
io::writable() { test -w "${1}" 2> /dev/null; }

##
# Atomic file write from stdin
#
# Writes stdin to a file atomically using temp file + move strategy.
# Temp file is created in the same directory as destination to ensure
# atomic move operation (same filesystem). Falls back to sudo if needed.
#
# Arguments:
#   $1 - Destination file path (string, required)
#   $2 - Permissions mode (octal, optional, default: 0644)
#
# Input:
#   Content to write (stdin)
#
# Returns:
#   0 - File written successfully
#   1 - Failed to write (temp file creation, write, or move failed)
#
# Security:
#   - Temp file in destination dir prevents cross-partition move (ensures atomicity)
#   - Hidden prefix (.atomic-write.) prevents conflicts
#   - mktemp XXXXXX provides unpredictable names (prevents CWE-59)
#   - Explicit cleanup on all error paths (no trap interference)
#   - Works correctly in pipelines and test frameworks
#
# Example:
#   echo "content" | io::atomic_write "/etc/app/config" "0640"
#   cat file.txt | io::atomic_write "/var/lib/app/data"
##
io::atomic_write() {
  local dst="${1}"
  local mode="${2:-0644}"
  local dstdir tmp
  dstdir="$(dirname "${dst}")"

  # Security: Create temp file in destination directory (same partition for atomic mv)
  # Use hidden prefix to prevent conflicts and mktemp XXXXXX for unpredictability
  local attempt=0
  while true; do
    tmp="$(mktemp -p "${dstdir}" .atomic-write.XXXXXX.tmp 2> /dev/null)" && break
    attempt=$((attempt + 1))
    [[ "${attempt}" -lt 5 ]] || return 1
    sleep 0.02
  done

  cleanup_tmp() {
    rm -f "${tmp}" 2> /dev/null || true
  }

  # Write content to temp file
  if ! cat > "${tmp}"; then
    cleanup_tmp
    return 1
  fi

  # Move to final location
  if io::writable "${dstdir}"; then
    if ! mv -f "${tmp}" "${dst}"; then
      cleanup_tmp
      return 1
    fi
    chmod "${mode}" "${dst}" || true
    return 0
  fi

  core::log warn "write needs sudo" "$(printf '{"file":"%s"}' "$(core::json_escape "${dst}")")"
  if ! core::sudo_cmd mv -f "${tmp}" "${dst}"; then
    cleanup_tmp
    return 1
  fi
  core::sudo_cmd chmod "${mode}" "${dst}" || true

  # Success - temp file has been moved
  return 0
}

##
# Install file with permissions
#
# Copies a file to destination with specified permissions.
# Creates parent directory if needed. Falls back to sudo if permission denied.
#
# Arguments:
#   $1 - Source file path (string, required)
#   $2 - Destination file path (string, required)
#   $3 - Permissions mode (octal, optional, default: 0755)
#
# Returns:
#   0 - File installed successfully
#   1 - Failed to install (copy failed even with sudo)
#
# Example:
#   io::install_file "./xrf" "/usr/local/bin/xrf" "0755"
#   io::install_file "config.json" "/etc/app/config.json" "0640"
##
io::install_file() {
  local src="${1}" dst="${2}" mode="${3:-0755}"
  io::ensure_dir "$(dirname "${dst}")" || return 1
  if ! cp -f "${src}" "${dst}" 2> /dev/null; then
    core::log warn "copy needs sudo" "$(printf '{"file":"%s"}' "$(core::json_escape "${dst}")")"
    if ! core::sudo_cmd cp -f "${src}" "${dst}"; then
      core::log error "failed to copy file" "$(printf '{"src":"%s","dst":"%s"}' "$(core::json_escape "${src}")" "$(core::json_escape "${dst}")")"
      return 1
    fi
  fi
  chmod "${mode}" "${dst}" || true
  return 0
}
