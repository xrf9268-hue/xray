#!/usr/bin/env bash
# Xray installation utilities
# NOTE: This file is sourced. Strict mode is set by core::init() from the calling script

# Source guard: prevent double-sourcing
[[ -n "${_XRF_INSTALL_UTILS_LOADED:-}" ]] && return 0
readonly _XRF_INSTALL_UTILS_LOADED=1

##
# Extract SHA256 hash from .dgst file content
#
# Handles multiple .dgst file formats commonly used by Xray-core releases:
# - Format 1 (labeled): SHA256 (Xray-linux-64.zip) = abc123...
# - Format 2 (labeled, compact): SHA256(file)=hash
# - Format 3 (plain): abc123... Xray-linux-64.zip
# - Format 4 (plain, line-start): abc123...
#
# Priority: Labeled SHA256 formats first to avoid extracting SHA512's first 64 chars.
#
# Arguments:
#   $1 - Content of .dgst file (string, required)
#
# Output:
#   SHA256 hash (64 hex chars) to stdout, or empty string if not found
#
# Returns:
#   0 - Always succeeds (returns empty string if hash not found)
#
# Security:
#   Prevents CWE-345 (Insufficient Verification of Data Authenticity) by:
#   - Prioritizing labeled SHA256 format over plain hash format
#   - Avoiding extraction of SHA512 hash when both present
#
# Example:
#   dgst_content="$(curl -fsSL "${url}.dgst")"
#   sha="$(xray::extract_sha256_from_dgst "${dgst_content}")"
##
xray::extract_sha256_from_dgst() {
  local dgst_content="${1}"
  local sha=""

  [[ -z "${dgst_content}" ]] && return 0

  # Priority 1: Try labeled SHA256 format first (most reliable)
  # Matches: "SHA256 (file) = hash", "SHA256(file)=hash", or "SHA2-256= hash"
  sha="$(echo "${dgst_content}" | grep -iE 'SHA2?-?256' | grep -oE '[0-9A-Fa-f]{64}' | head -1)" || true

  # Priority 2: Fallback to plain hash at line start
  # Matches: "hash  filename" (two spaces separator)
  if [[ -z "${sha}" ]]; then
    sha="$(echo "${dgst_content}" | grep -oE '^[0-9A-Fa-f]{64}' | head -1)" || true
  fi

  echo "${sha}"
  return 0
}

##
# Validate SHA256 hash format
#
# Checks if a string is a valid 64-character hexadecimal SHA256 hash.
#
# Arguments:
#   $1 - SHA256 hash to validate (string, required)
#
# Returns:
#   0 - Valid SHA256 format
#   1 - Invalid format (not 64 hex chars)
#
# Example:
#   if xray::validate_sha256_format "${sha}"; then
#     echo "Valid SHA256"
#   fi
##
xray::validate_sha256_format() {
  local sha="${1}"
  [[ "${sha}" =~ ^[0-9A-Fa-f]{64}$ ]]
}

##
# Verify file checksum against expected SHA256
#
# Computes the SHA256 checksum of a file and compares it to the expected value.
# Uses sha256sum (coreutils) for computation.
#
# Arguments:
#   $1 - File path (string, required)
#   $2 - Expected SHA256 hash (string, required, 64 hex chars)
#
# Globals:
#   Uses core::log if available for structured logging
#
# Returns:
#   0 - Checksum matches
#   1 - Checksum mismatch or file not readable
#
# Example:
#   if xray::verify_file_checksum "${file}" "${expected_sha}"; then
#     echo "Checksum verified"
#   fi
##
xray::verify_file_checksum() {
  local file="${1}"
  local expected_sha="${2}"

  [[ -r "${file}" ]] || return 1

  local got
  got="$(sha256sum "${file}" | awk '{print $1}')" || return 1

  if [[ "${got}" != "${expected_sha}" ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "SHA256 mismatch" "$(printf '{"expected":"%s","got":"%s","file":"%s"}' "${expected_sha}" "${got}" "${file}")"
    fi
    return 1
  fi

  return 0
}
