#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/export.sh"

usage() {
  cat << 'EOF'
Usage: xrf export <format> [options]

Export client configurations in multiple formats.

Formats:
  uri        Print client URI links
  v2rayn     Print v2rayN-compatible JSON
  clash      Print Clash Meta YAML
  sub        Print Base64 subscription content
  qr         Render QR code(s) in terminal
  all        Export all formats to files

Options:
  --out-dir <path>   Output directory for `all` (default: /tmp/xrf-export)
  --help, -h         Show this help
EOF
}

main() {
  core::init "${@}"
  plugins::ensure_dirs
  plugins::load_enabled

  local format="${1:-}"
  shift || true

  local out_dir="${XRF_EXPORT_DIR:-/tmp/xrf-export}"
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --out-dir)
        out_dir="${2:-}"
        if [[ -z "${out_dir}" ]]; then
          core::log error "missing value for --out-dir" "{}"
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

  export::load_context

  case "${format}" in
    uri) export::uri ;;
    v2rayn) export::v2rayn ;;
    clash) export::clash ;;
    sub) export::subscription ;;
    qr) export::qr ;;
    all) export::all "${out_dir}" ;;
    --help | -h | "")
      usage
      exit 0
      ;;
    *)
      core::log error "unknown export format" "$(printf '{"format":"%s"}' "${format}")"
      usage
      exit 1
      ;;
  esac
}

main "${@}"
