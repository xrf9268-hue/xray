#!/usr/bin/env bash
# Common Xray paths and utilities
# NOTE: This file is sourced. Strict mode is set by core::init() from the calling script

# Source guard: prevent double-sourcing
[[ -n "${_XRF_XRAY_COMMON_LOADED:-}" ]] && return 0
readonly _XRF_XRAY_COMMON_LOADED=1

xray::prefix() { echo "${XRF_PREFIX:-/usr/local}"; }
xray::etc() { echo "${XRF_ETC:-/usr/local/etc}"; }
xray::confbase() { echo "$(xray::etc)/xray"; }
xray::releases() { echo "$(xray::confbase)/releases"; }
xray::active() { echo "$(xray::confbase)/active"; }
xray::bin() { echo "$(xray::prefix)/bin/xray"; }

##
# Generate a random shortId for Xray Reality
#
# Creates a 16-character hexadecimal string using reliable tools.
# Tries xxd → od → openssl (in order of preference).
#
# Output:
#   16-character hexadecimal string to stdout
#
# Returns:
#   0 - Success
#   1 - All tools failed (should never happen, openssl is always available)
#
# Example:
#   shortid=$(xray::generate_shortid)
#   # Output: a1b2c3d4e5f67890
##
xray::generate_shortid() {
  local result=""

  if command -v xxd > /dev/null 2>&1; then
    result="$(head -c 8 /dev/urandom | xxd -p -c 16)"
  elif command -v od > /dev/null 2>&1; then
    result="$(head -c 8 /dev/urandom | od -An -tx1 -v | tr -d ' \n')"
  elif command -v openssl > /dev/null 2>&1; then
    result="$(openssl rand -hex 8)"
  else
    # This should never happen as openssl is a project dependency
    echo "ERROR: no suitable tool found for shortId generation" >&2
    return 1
  fi

  # Output the result
  echo "${result}"
  return 0
}

##
# Generate multiple random shortIds for Xray Reality (batch operation)
#
# Creates N shortIds in a single operation, reducing subprocess overhead.
# More efficient than calling xray::generate_shortid() multiple times.
#
# Arguments:
#   $1 - Count of shortIds to generate (integer, required, default: 3)
#
# Output:
#   N lines, each containing a 16-character hexadecimal string to stdout
#
# Returns:
#   0 - Success
#   1 - All tools failed or invalid count
#
# Example:
#   mapfile -t sids < <(xray::generate_shortids 3)
#   # sids[0]=a1b2c3d4e5f67890
#   # sids[1]=1234567890abcdef
#   # sids[2]=fedcba9876543210
##
xray::generate_shortids() {
  local count="${1:-3}"

  # Validate count
  if ! [[ "${count}" =~ ^[0-9]+$ ]] || [[ "${count}" -lt 1 ]]; then
    echo "ERROR: invalid count for shortId generation: ${count}" >&2
    return 1
  fi

  local bytes=$((count * 8)) # 8 bytes per shortId

  if command -v xxd > /dev/null 2>&1; then
    # xxd: read all bytes at once, output 16 hex chars per line (8 bytes * 2)
    # Note: -c 8 means 8 bytes per line, which produces 16 hex characters
    head -c "${bytes}" /dev/urandom | xxd -p -c 8 | head -n "${count}"
  elif command -v od > /dev/null 2>&1; then
    # od: read all bytes, split into 16-char chunks
    local raw
    raw="$(head -c "${bytes}" /dev/urandom | od -An -tx1 -v | tr -d ' \n')"
    for ((i = 0; i < count; i++)); do
      echo "${raw:$((i * 16)):16}"
    done
  elif command -v openssl > /dev/null 2>&1; then
    # openssl: generate count times (no batch mode for rand)
    for ((i = 0; i < count; i++)); do
      openssl rand -hex 8
    done
  else
    echo "ERROR: no suitable tool found for shortId generation" >&2
    return 1
  fi

  return 0
}
