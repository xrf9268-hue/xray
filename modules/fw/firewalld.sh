#!/usr/bin/env bash
# firewalld backend
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_FW_FIREWALLD_LOADED:-}" ]] && return 0
readonly _XRF_FW_FIREWALLD_LOADED=1

fw_firewalld::is_available() { command -v firewall-cmd > /dev/null 2>&1; }
fw_firewalld::open() {
  local rule="${1}"
  sudo firewall-cmd --permanent --add-port="${rule}" || true
  sudo firewall-cmd --reload || true
}
fw_firewalld::close() {
  local rule="${1}"
  sudo firewall-cmd --permanent --remove-port="${rule}" || true
  sudo firewall-cmd --reload || true
}
