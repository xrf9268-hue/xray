#!/usr/bin/env bash
# Download and verification utilities for xray-fusion
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_DOWNLOAD_LOADED:-}" ]] && return 0
readonly _XRF_DOWNLOAD_LOADED=1

##
# Verify git commit hash matches expected value
#
# This function checks if the current HEAD commit of a git repository
# matches the expected commit hash. This is used to ensure download
# integrity and prevent tampering.
#
# Arguments:
#   $1 - Repository path (string, required)
#   $2 - Expected commit hash (string, required)
#
# Output:
#   Debug logs to stderr via core::log
#
# Returns:
#   0 - Commit hash matches
#   1 - Hash mismatch or verification error
#
# Security:
#   Protects against:
#   - CWE-494: Download of Code Without Integrity Check
#   - CWE-353: Missing Support for Integrity Check
#   - Man-in-the-middle attacks
#
# Example:
#   download::verify_commit "/tmp/repo" "abc123..."
##
download::verify_commit() {
  local repo_path="${1:-}"
  local expected_hash="${2:-}"

  # Validate inputs using standardized parameter validation
  core::require_params \
    "repo_path=${repo_path}" \
    "expected_hash=${expected_hash}" || return 1

  # Check if git repo exists
  if [[ ! -d "${repo_path}/.git" ]]; then
    core::log error "not a git repository" "$(printf '{"path":"%s"}' "${repo_path}")"
    return 1
  fi

  # Get actual commit hash
  local actual_hash
  if ! actual_hash="$(git -C "${repo_path}" rev-parse HEAD 2> /dev/null)"; then
    core::log error "failed to get commit hash" "$(printf '{"path":"%s"}' "${repo_path}")"
    return 1
  fi

  # Compare hashes (case-insensitive)
  if [[ "${actual_hash,,}" != "${expected_hash,,}" ]]; then
    core::log error "commit hash mismatch" "$(printf '{"expected":"%s","actual":"%s"}' "${expected_hash}" "${actual_hash}")"
    return 1
  fi

  core::log debug "commit hash verified" "$(printf '{"hash":"%s"}' "${actual_hash}")"
  return 0
}

##
# Verify GPG signature of latest commit (optional)
#
# This function attempts to verify the GPG signature of the HEAD commit.
# If GPG is not available or the commit is unsigned, it gracefully degrades
# without failing. This is an optional security enhancement.
#
# Arguments:
#   $1 - Repository path (string, required)
#
# Output:
#   Info/warn logs to stderr via core::log
#
# Returns:
#   0 - Signature valid, GPG not available, or unsigned commit (graceful)
#   1 - Repository validation error
#
# Security:
#   Enhances security by verifying cryptographic signatures, but does not
#   fail the installation if GPG is unavailable (optional verification).
#
# Example:
#   download::verify_gpg_signature "/tmp/repo"
##
download::verify_gpg_signature() {
  local repo_path="${1:-}"

  # Validate input using standardized parameter validation
  core::require_param "${repo_path}" "repo_path" "verify_gpg_signature" || return 1

  # Check if git repo exists
  if [[ ! -d "${repo_path}/.git" ]]; then
    core::log error "not a git repository" "$(printf '{"path":"%s"}' "${repo_path}")"
    return 1
  fi

  # Check if GPG is available
  if ! command -v gpg > /dev/null 2>&1; then
    core::log warn "gpg not available, skipping signature verification" '{}'
    return 0 # Graceful degradation
  fi

  # Verify commit signature
  if git -C "${repo_path}" verify-commit HEAD 2> /dev/null; then
    core::log info "GPG signature verified" '{}'
    return 0
  else
    # Don't fail on unsigned commits - this is optional verification
    core::log warn "GPG signature verification failed or commit not signed" '{}'
    return 0
  fi
}

##
# Download repository as tarball and extract
#
# Downloads a GitHub repository tarball and extracts it to the destination
# directory. Supports both curl and wget with automatic fallback.
#
# Arguments:
#   $1 - Tarball URL (string, required)
#   $2 - Destination directory (string, required)
#   $3 - Branch name (string, required)
#
# Output:
#   Debug/error logs to stderr via core::log
#
# Returns:
#   0 - Download and extraction successful
#   1 - Download or extraction failed
#
# Example:
#   download::via_tarball "https://github.com/user/repo/archive/main.tar.gz" "/tmp" "main"
##
download::via_tarball() {
  local url="${1:-}"
  local dest_dir="${2:-}"
  local branch="${3:-}"

  # Validate inputs using standardized parameter validation
  core::require_params \
    "url=${url}" \
    "dest_dir=${dest_dir}" \
    "branch=${branch}" || return 1

  local tarball="${dest_dir}/archive.tar.gz"
  local download_success=false

  # Try curl first
  if command -v curl > /dev/null 2>&1; then
    core::log debug "attempting download via curl" "$(printf '{"url":"%s"}' "${url}")"
    if curl -fsSL --connect-timeout 10 --max-time 300 "${url}" -o "${tarball}" 2> /dev/null; then
      core::log debug "download successful via curl" '{}'
      download_success=true
    else
      core::log warn "curl download failed" '{}'
      rm -f "${tarball}"
    fi
  fi

  # Fallback to wget if curl failed or unavailable
  if [[ "${download_success}" == "false" ]] && command -v wget > /dev/null 2>&1; then
    core::log debug "attempting download via wget" "$(printf '{"url":"%s"}' "${url}")"
    if wget -q --timeout=10 "${url}" -O "${tarball}" 2> /dev/null; then
      core::log debug "download successful via wget" '{}'
      download_success=true
    else
      core::log warn "wget download failed" '{}'
      rm -f "${tarball}"
    fi
  fi

  # Check if download succeeded
  if [[ "${download_success}" == "false" ]]; then
    core::log error "all download attempts failed (curl/wget)" '{}'
    return 1
  fi

  # Extract tarball
  core::log debug "extracting tarball" '{}'
  if ! tar -xzf "${tarball}" -C "${dest_dir}" 2> /dev/null; then
    core::log error "failed to extract tarball" '{}'
    rm -f "${tarball}"
    return 1
  fi

  # Rename extracted directory
  local extracted_dir="${dest_dir}/xray-fusion-${branch}"
  if [[ -d "${extracted_dir}" ]]; then
    mv "${extracted_dir}" "${dest_dir}/xray-fusion"
  else
    core::log error "extracted directory not found" "$(printf '{"expected":"%s"}' "${extracted_dir}")"
    return 1
  fi

  # Cleanup tarball
  rm -f "${tarball}"

  core::log debug "tarball download complete" '{}'
  return 0
}

##
# Download repository with automatic fallback
#
# Tries multiple download methods in order:
#   1. git clone (preserves .git history)
#   2. tarball via curl
#   3. tarball via wget
#
# Arguments:
#   $1 - Repository URL (string, required)
#   $2 - Destination directory (string, required)
#   $3 - Branch name (string, required)
#
# Output:
#   Info/warn/error logs to stderr via core::log
#
# Returns:
#   0 - Download successful
#   1 - All download methods failed
#
# Example:
#   download::with_fallback "https://github.com/user/repo.git" "/tmp" "main"
##
download::with_fallback() {
  local repo_url="${1:-}"
  local dest_dir="${2:-}"
  local branch="${3:-}"

  # Validate inputs using standardized parameter validation
  core::require_params \
    "repo_url=${repo_url}" \
    "dest_dir=${dest_dir}" \
    "branch=${branch}" || return 1

  # Method 1: Git clone (preferred)
  if command -v git > /dev/null 2>&1; then
    core::log debug "attempting git clone" "$(printf '{"url":"%s","branch":"%s"}' "${repo_url}" "${branch}")"
    if git clone --depth 1 --branch "${branch}" "${repo_url}" "${dest_dir}/xray-fusion" 2> /dev/null; then
      core::log info "git clone successful" '{}'
      return 0
    else
      core::log warn "git clone failed, trying tarball fallback" '{}'
    fi
  else
    core::log debug "git not available, skipping git clone" '{}'
  fi

  # Method 2 & 3: Tarball download (curl/wget)
  local tarball_url="${repo_url%.git}/archive/refs/heads/${branch}.tar.gz"
  core::log debug "attempting tarball download" "$(printf '{"url":"%s"}' "${tarball_url}")"

  if download::via_tarball "${tarball_url}" "${dest_dir}" "${branch}"; then
    core::log info "tarball download successful" '{}'
    return 0
  else
    core::log error "all download methods failed" '{}'
    return 1
  fi
}
