#!/usr/bin/env bash
# Firewall dispatcher module
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_FW_LOADED:-}" ]] && return 0
readonly _XRF_FW_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${HERE}/modules/fw/ufw.sh"
. "${HERE}/modules/fw/firewalld.sh"
fw::detect() { if fw_ufw::is_available; then echo ufw; elif fw_firewalld::is_available; then echo firewalld; else echo none; fi; }
fw::open() {
  local p="${1}"/tcp
  case "$(fw::detect)" in ufw) fw_ufw::open "${p}" ;; firewalld) fw_firewalld::open "${p}" ;; *) true ;; esac
}
fw::close() {
  local p="${1}"/tcp
  case "$(fw::detect)" in ufw) fw_ufw::close "${p}" ;; firewalld) fw_firewalld::close "${p}" ;; *) true ;; esac
}
