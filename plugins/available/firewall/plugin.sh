#!/usr/bin/env bash
# shellcheck disable=SC2034  # Plugin metadata variables are used by the plugin system
XRF_PLUGIN_ID="firewall"
XRF_PLUGIN_VERSION="1.0.0"
XRF_PLUGIN_DESC="Open/close ports with ufw/firewalld during service lifecycle"
XRF_PLUGIN_HOOKS=("configure_post" "uninstall_pre")
HERE="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
. "${HERE}/lib/core.sh"
. "${HERE}/modules/fw/fw.sh"
firewall::configure_post() {
  local topology=""
  for kv in "${@}"; do case "${kv}" in topology=*) topology="${kv#*=}" ;; esac done
  if [[ "${topology}" == "vision-reality" ]]; then
    local vp="${XRAY_VISION_PORT:-8443}" rp="${XRAY_REALITY_PORT:-443}"
    core::log info "firewall opening ports" "$(printf '{"ports":["%s/tcp","%s/tcp"]}' "${vp}" "${rp}")"
    fw::open "${vp}"
    fw::open "${rp}"
  else
    local p="${XRAY_PORT:-443}"
    core::log info "firewall opening port" "$(printf '{"port":"%s/tcp"}' "${p}")"
    fw::open "${p}"
  fi
}
firewall::uninstall_pre() {
  if [[ "${XRF_KEEP_RULES:-false}" == "true" ]]; then
    core::log info "firewall keeping existing rules" "{}"
    return 0
  fi
  if [[ -n "${XRAY_VISION_PORT:-}" || -n "${XRAY_REALITY_PORT:-}" ]]; then
    [[ -n "${XRAY_VISION_PORT:-}" ]] && fw::close "${XRAY_VISION_PORT}"
    [[ -n "${XRAY_REALITY_PORT:-}" ]] && fw::close "${XRAY_REALITY_PORT}"
  elif [[ -n "${XRAY_PORT:-}" ]]; then fw::close "${XRAY_PORT}"; fi
}
