#!/usr/bin/env bash
# UFW firewall backend
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_FW_UFW_LOADED:-}" ]] && return 0
readonly _XRF_FW_UFW_LOADED=1

fw_ufw::is_available() { command -v ufw > /dev/null 2>&1; }
fw_ufw::open() {
  local rule="${1}"
  sudo ufw allow "${rule}" || true
}
fw_ufw::close() {
  local rule="${1}"
  sudo ufw delete allow "${rule}" || true
}
