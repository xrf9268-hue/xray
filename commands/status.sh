#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/services/xray/common.sh"
main() {
  core::init "${@}"
  local ver="unknown"
  local xray_bin
  xray_bin="$(xray::bin)"
  if [[ -x "${xray_bin}" ]]; then
    ver="$("${xray_bin}" -version 2> /dev/null | awk 'NR==1{print $2}')"
  fi

  local active_confdir
  active_confdir="$(xray::active)"
  core::log info "Xray" "$(printf '{"version":"%s","active_confdir":"%s"}' "${ver}" "${active_confdir}")"
}
main "${@}"
