#!/usr/bin/env bash
[[ -n "${_XRF_USER_LOADED:-}" ]] && return 0
readonly _XRF_USER_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"

##
# Run privileged command using direct execution as root, sudo otherwise.
##
user::_run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    core::sudo_cmd "$@"
  fi
}

##
# Ensure a system user and group exist with expected ownership
#
# Creates a system group/user pair when missing and validates existing
# ownership matches the expected primary group.
#
# Arguments:
#   $1 - Username (string, optional, default: xray)
#   $2 - Group name (string, optional, default: xray)
#
# Returns:
#   0 - User/group exist and are correctly associated
#   1 - Failed to create or ownership mismatch detected
##
user::ensure_system_user() {
  local u="${1:-xray}" g="${2:-xray}"
  local group_entry expected_gid user_entry user_gid

  if ! group_entry="$(getent group "${g}")"; then
    core::log info "creating system group" "$(printf '{"group":"%s"}' "${g}")"
    if ! user::_run_privileged groupadd --system "${g}"; then
      core::log error "failed to create system group" "$(printf '{"group":"%s","hint":"ensure permission to create groups or create manually"}' "${g}")"
      return 1
    fi
    if ! group_entry="$(getent group "${g}")"; then
      core::log error "system group missing after creation" "$(printf '{"group":"%s","hint":"verify group database state"}' "${g}")"
      return 1
    fi
  else
    core::log debug "system group already exists" "$(printf '{"group":"%s"}' "${g}")"
  fi

  IFS=':' read -r _ _ expected_gid _ <<< "${group_entry}"
  if [[ -z "${expected_gid}" ]]; then
    core::log error "could not determine system group gid" "$(printf '{"group":"%s"}' "${g}")"
    return 1
  fi

  if user_entry="$(getent passwd "${u}")"; then
    IFS=':' read -r _ _ _ user_gid _ <<< "${user_entry}"
    if [[ "${user_gid}" != "${expected_gid}" ]]; then
      core::log error "system user has unexpected primary group" "$(printf '{"user":"%s","expected_group":"%s","expected_gid":"%s","actual_gid":"%s","hint":"recreate user with --gid %s or update existing assignment"}' "${u}" "${g}" "${expected_gid}" "${user_gid:-}" "${g}")"
      return 1
    fi
    core::log debug "system user already exists" "$(printf '{"user":"%s","group":"%s"}' "${u}" "${g}")"
    return 0
  fi

  core::log info "creating system user" "$(printf '{"user":"%s","group":"%s"}' "${u}" "${g}")"
  if ! user::_run_privileged useradd --system --gid "${g}" --home-dir "/var/lib/${u}" --no-create-home --shell /usr/sbin/nologin "${u}"; then
    core::log error "failed to create system user" "$(printf '{"user":"%s","group":"%s","hint":"create user manually with system flags and expected group"}' "${u}" "${g}")"
    return 1
  fi

  if ! getent passwd "${u}" > /dev/null 2>&1; then
    core::log error "system user missing after creation" "$(printf '{"user":"%s","hint":"verify passwd database state"}' "${u}")"
    return 1
  fi

  core::log info "system user ensured" "$(printf '{"user":"%s","group":"%s"}' "${u}" "${g}")"
  return 0
}
