#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/config_validation.sh"

usage() {
  cat << 'EOF'
Usage: xrf check [options]

Validate Xray configuration.

Options:
  --deep                 Run three-layer deep validation before xray -test
  --confdir <path>       Configuration directory (default: active confdir)
  --help, -h             Show this help
EOF
}

main() {
  core::init "${@}"

  local deep="false"
  local confdir
  confdir="$(xray::active)"

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --deep)
        deep="true"
        shift
        ;;
      --confdir)
        confdir="${2:-}"
        if [[ -z "${confdir}" ]]; then
          core::log error "missing value for --confdir" "{}"
          usage
          exit 1
        fi
        shift 2
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        core::log error "unknown option" "$(printf '{"option":"%s"}' "${1}")"
        usage
        exit 1
        ;;
    esac
  done

  if [[ "${deep}" == "true" ]]; then
    config::validate_deep "${confdir}" || exit 1
  fi
  config::validate_binary "${confdir}" || exit 1

  core::log info "configuration validation passed" "$(printf '{"confdir":"%s","deep":%s}' "${confdir}" "${deep}")"
}

main "${@}"
