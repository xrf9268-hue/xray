#!/usr/bin/env bash
# Unified argument parsing module for xray-fusion
# Provides consistent parameter interface for both install.sh and xrf commands
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_ARGS_LOADED:-}" ]] && return 0
readonly _XRF_ARGS_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/defaults.sh
. "${HERE}/lib/defaults.sh"
# shellcheck source=lib/validators.sh
. "${HERE}/lib/validators.sh"
# shellcheck source=lib/error_codes.sh
. "${HERE}/lib/error_codes.sh"

# Initialize default values
args::init() {
  TOPOLOGY="${DEFAULT_TOPOLOGY}"
  DOMAIN=""
  VERSION="${DEFAULT_VERSION}"
  PLUGINS=""
  DEBUG="${DEFAULT_XRF_DEBUG}"
  UUID=""
  UUID_FROM_STRING=""
  XRF_YES="false"
  XRF_DRY_RUN="false"
  TEMPLATE=""
  FINGERPRINT="${DEFAULT_XRAY_FINGERPRINT}"

  # Tracking flags for explicit CLI arguments (used by template override logic)
  _TOPOLOGY_EXPLICIT=""
  _VERSION_EXPLICIT=""
  _PLUGINS_EXPLICIT=""
}

# Parse command line arguments
args::parse() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --topology | -t)
        args::validate_topology "${2:-}" || return 1
        TOPOLOGY="${2}"
        _TOPOLOGY_EXPLICIT="true"
        shift 2
        ;;
      --domain | -d)
        args::validate_domain "${2:-}" || return 1
        DOMAIN="${2}"
        shift 2
        ;;
      --fingerprint | -f)
        args::validate_fingerprint "${2:-}" || return 1
        FINGERPRINT="${2}"
        shift 2
        ;;
      --version | -v)
        args::validate_version "${2:-}" || return 1
        VERSION="${2}"
        _VERSION_EXPLICIT="true"
        shift 2
        ;;
      --plugins | -p)
        PLUGINS="${2:-}"
        _PLUGINS_EXPLICIT="true"
        shift 2
        ;;
      --uuid)
        UUID="${2:-}"
        shift 2
        ;;
      --uuid-from-string)
        UUID_FROM_STRING="${2:-}"
        shift 2
        ;;
      --template)
        TEMPLATE="${2:-}"
        shift 2
        ;;
      --debug)
        DEBUG="true"
        shift
        ;;
      --yes | -y)
        XRF_YES="true"
        shift
        ;;
      --dry-run)
        XRF_DRY_RUN="true"
        shift
        ;;
      --help | -h)
        return 10 # Special return code for help
        ;;
      --)
        shift
        break
        ;;
      *)
        core::log error "unknown argument" "$(printf '{"arg":"%s"}' "${1}")"
        return 1
        ;;
    esac
  done

  # Validate configuration
  args::validate_config || return 1

  # Validate UUID parameters if provided
  if [[ -n "${UUID}" && -n "${UUID_FROM_STRING}" ]]; then
    core::log error "cannot use both --uuid and --uuid-from-string" "{}"
    return 1
  fi

  # Export variables for use by other modules
  export TOPOLOGY DOMAIN VERSION PLUGINS DEBUG UUID UUID_FROM_STRING XRF_YES XRF_DRY_RUN TEMPLATE FINGERPRINT
  export _TOPOLOGY_EXPLICIT _VERSION_EXPLICIT _PLUGINS_EXPLICIT

  return 0
}

# Topology validation
args::validate_topology() {
  local topology="${1:-}"
  if [[ -z "${topology}" ]]; then
    error_codes::missing_parameter "topology" ""
    return 1
  fi

  case "${topology}" in
    reality-only | vision-reality)
      return 0
      ;;
    *)
      error_codes::invalid_topology "${topology}"
      return 1
      ;;
  esac
}

# Domain validation
args::validate_domain() {
  local domain="${1:-}"
  [[ -z "${domain}" ]] && return 0 # Domain is optional for reality-only

  # Use shared validator (RFC compliant, length limits, internal domain check)
  # Validator logs specific rejection reason via debug output
  if ! validators::domain "${domain}"; then
    error_codes::invalid_domain "${domain}" "see debug log for details"
    return 1
  fi

  return 0
}

# Version validation
args::validate_version() {
  local version="${1:-}"
  if [[ -z "${version}" ]]; then
    core::log error "version cannot be empty" "{}"
    return 1
  fi

  # Use shared validator (accepts 'latest' or vX.Y.Z)
  if ! validators::version "${version}"; then
    core::log error "invalid version format" "$(printf '{"version":"%s","format":"vX.Y.Z or latest"}' "${version}")"
    return 1
  fi

  return 0
}

# Fingerprint validation
args::validate_fingerprint() {
  local fingerprint="${1:-}"
  if [[ -z "${fingerprint}" ]]; then
    core::log error "fingerprint cannot be empty" "{}"
    return 1
  fi

  # Use shared validator (accepts chrome/firefox/safari/ios/android/edge/360/qq/random/randomized)
  if ! validators::fingerprint "${fingerprint}"; then
    core::log error "invalid fingerprint" "$(printf '{"fingerprint":"%s","valid":"chrome|firefox|safari|ios|android|edge|360|qq|random|randomized"}' "${fingerprint}")"
    return 1
  fi

  return 0
}

# Configuration validation
args::validate_config() {
  # vision-reality topology requires domain
  if [[ "${TOPOLOGY}" == "vision-reality" && -z "${DOMAIN}" ]]; then
    error_codes::missing_parameter "domain" "vision-reality topology"
    return 1
  fi

  return 0
}

# Show help for common arguments
args::show_help() {
  cat << EOF
Options:
  --topology, -t <type>         Installation topology (reality-only|vision-reality)
  --domain, -d <domain>         Domain for vision-reality topology (required)
  --fingerprint, -f <type>      TLS fingerprint (default: chrome)
                                Valid: chrome, firefox, safari, ios, android, edge, 360, qq, random, randomized
  --version, -v <version>       Xray version to install (default: latest)
  --template <id>               Use pre-built template (home|office|server)
  --plugins, -p <list>          Comma-separated list of plugins to enable
  --uuid <uuid>                 Custom UUID (default: auto-generated)
  --uuid-from-string <string>   Generate UUID from custom string
  --yes, -y                     Auto-confirm installation (skip prompt)
  --dry-run                     Show preview without installing
  --debug                       Enable debug output
  --help, -h                    Show this help

Examples:
  # Reality-only topology
  --topology reality-only

  # Install with home template (quick start)
  --template home

  # Install with office template and custom domain
  --template office --domain vpn.company.com

  # Vision-Reality with domain and plugins
  --topology vision-reality --domain your.domain.com --plugins cert-auto

  # Preview without installing
  --topology reality-only --dry-run

  # Auto-confirm installation
  --topology reality-only --yes

  # Specific version
  --version v1.8.1

  # List available templates
  xrf templates list

EOF
}

# Show current configuration (debug helper)
args::show_config() {
  if [[ "${DEBUG}" == "true" ]]; then
    core::log debug "parsed arguments" "$(printf '{"topology":"%s","domain":"%s","version":"%s","plugins":"%s","fingerprint":"%s","debug":"%s"}' \
      "${TOPOLOGY}" "${DOMAIN}" "${VERSION}" "${PLUGINS}" "${FINGERPRINT}" "${DEBUG}")"
  fi
}

# Export parsed arguments as environment variables
args::export_vars() {
  # Set XRAY_DOMAIN for Xray configuration
  if [[ -n "${DOMAIN}" ]]; then
    export XRAY_DOMAIN="${DOMAIN}"
  fi

  # Set XRAY_FINGERPRINT for client link generation
  if [[ -n "${FINGERPRINT}" ]]; then
    export XRAY_FINGERPRINT="${FINGERPRINT}"
  fi

  # Set XRF_DEBUG for core module
  export XRF_DEBUG="${DEBUG}"
}
