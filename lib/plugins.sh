#!/usr/bin/env bash
# Lightweight plugin loader + event bus
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_PLUGINS_LOADED:-}" ]] && return 0
readonly _XRF_PLUGINS_LOADED=1

plugins::base() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  [[ -n "${XRF_PLUGINS:-}" ]] && {
    echo "${XRF_PLUGINS}"
    return
  }
  echo "${here}/plugins"
}
plugins::dir_available() { echo "$(plugins::base)/available"; }
plugins::dir_enabled() { echo "$(plugins::base)/enabled"; }
plugins::ensure_dirs() { mkdir -p "$(plugins::dir_available)" "$(plugins::dir_enabled)"; }

# Security: Validate plugin ID to prevent path traversal attacks
plugins::validate_id() {
  local id="${1:?id}"

  # Check for valid characters only
  if [[ ! "${id}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "invalid plugin id: ${id}" >&2
    return 1
  fi

  # Check for path traversal patterns
  if [[ "${id}" =~ \.\.|\/ ]]; then
    echo "invalid plugin id contains path traversal: ${id}" >&2
    return 1
  fi

  return 0
}

# Load
declare -ag __PLUG_IDS=()
declare -Ag __PLUG_META=()

plugins::load_enabled() {
  __PLUG_IDS=()
  local d
  d="$(plugins::dir_enabled)"
  [[ -d "${d}" ]] || return 0
  local f project_root
  project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  for f in "${d}"/*.sh; do
    [[ -f "${f}" ]] || continue
    # shellcheck disable=SC1090
    if HERE="${project_root}" . "${f}" 2> /dev/null; then
      # Validate required plugin variables
      if [[ -n "${XRF_PLUGIN_ID:-}" ]]; then
        local id="${XRF_PLUGIN_ID}" ver="${XRF_PLUGIN_VERSION:-0.0.0}" desc="${XRF_PLUGIN_DESC:-}" hooks="${XRF_PLUGIN_HOOKS[*]:-}"
        __PLUG_IDS+=("${id}")
        __PLUG_META["${id}"]="${ver}|${desc}|${hooks}"
      else
        printf 'Warning: Plugin %s missing XRF_PLUGIN_ID\n' "$(basename "${f}")" >&2
      fi
    else
      printf 'Warning: Failed to load plugin %s\n' "$(basename "${f}")" >&2
    fi
    # Clear plugin variables for next iteration
    unset XRF_PLUGIN_ID XRF_PLUGIN_VERSION XRF_PLUGIN_DESC XRF_PLUGIN_HOOKS
  done
}

plugins::fn_prefix() { echo "${1//-/_}"; }

plugins::emit() {
  local event="${1}"
  shift || true
  local args=("${@}")
  local id meta hooks fn
  core::log debug "emitting plugin event" "$(printf '{"event":"%s","args":"%s"}' "${event}" "${args[*]}")"
  for id in "${__PLUG_IDS[@]}"; do
    meta="${__PLUG_META[${id}]}"
    hooks="${meta#*|}"
    hooks="${hooks#*|}"
    case " ${hooks} " in *" ${event} "*) ;; *) continue ;; esac
    fn="$(plugins::fn_prefix "${id}")::${event}"
    if declare -F "${fn}" > /dev/null 2>&1; then
      core::log debug "executing plugin hook" "$(printf '{"plugin":"%s","event":"%s","function":"%s"}' "${id}" "${event}" "${fn}")"
      "${fn}" "${args[@]}" || {
        core::log error "plugin hook failed" "$(printf '{"plugin":"%s","event":"%s","rc":"%s"}' "${id}" "${event}" "$?")"
        return 1
      }
    fi
  done
}

##
# List plugins from a directory (internal helper)
#
# Internal function used by plugins::list to iterate and display plugins.
# Extracts common logic to reduce code duplication.
#
# Arguments:
#   $1 - Directory pattern (string, required) - e.g., "${av}"/*/plugin.sh
#   $2 - Format type (string, required) - "detailed" or "simple"
#
# Output:
#   Plugin list to stdout (one per line)
#
# Returns:
#   0 - Always succeeds
##
plugins::list_from_dir() {
  local pattern="${1}"
  local format="${2:-simple}"
  local f

  for f in ${pattern}; do
    [[ -f "${f}" ]] || continue
    # shellcheck source=/dev/null
    . "${f}"

    if [[ "${format}" == "detailed" ]]; then
      printf "  - %-14s %s (v%s)\n" "${XRF_PLUGIN_ID}" "${XRF_PLUGIN_DESC:-}" "${XRF_PLUGIN_VERSION:-0.0.0}"
    else
      echo "  - ${XRF_PLUGIN_ID}"
    fi
  done
}

plugins::list() {
  local av en
  av="$(plugins::dir_available)"
  en="$(plugins::dir_enabled)"

  echo "Available:"
  plugins::list_from_dir "${av}/*/plugin.sh" "detailed"

  echo ""
  echo "Enabled:"
  plugins::list_from_dir "${en}/*.sh" "simple"
}

plugins::enable() {
  local id="${1:?id}"

  # Validate plugin ID for security
  plugins::validate_id "${id}" || return 2

  local src dst
  src="$(plugins::dir_available)/${id}/plugin.sh"
  dst="$(plugins::dir_enabled)/${id}.sh"

  # Check if plugin exists
  if [[ ! -f "${src}" ]]; then
    echo "plugin not found: ${id}" >&2
    return 2
  fi

  # Security: Verify plugin is within expected directory
  local av_dir real_src real_av_dir
  av_dir="$(plugins::dir_available)"
  real_src="$(realpath "${src}" 2> /dev/null || echo "")"
  real_av_dir="$(realpath "${av_dir}" 2> /dev/null || echo "")"

  if [[ -z "${real_src}" || -z "${real_av_dir}" ]] || [[ ! "${real_src}" =~ ^"${real_av_dir}"/ ]]; then
    echo "plugin source validation failed: ${id}" >&2
    return 2
  fi

  # Load plugin metadata to check dependencies
  local project_root
  project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck disable=SC1090
  if HERE="${project_root}" . "${src}" 2> /dev/null; then
    # Check if plugin declares dependencies
    if [[ -n "${XRF_PLUGIN_DEPS:-}" ]]; then
      # Load dependencies library if available
      if [[ -f "${project_root}/lib/dependencies.sh" ]]; then
        # shellcheck disable=SC1091
        . "${project_root}/lib/dependencies.sh"

        # Check and install dependencies
        if declare -f deps::check_and_install_plugin_deps > /dev/null 2>&1; then
          if ! deps::check_and_install_plugin_deps "${id}" "${XRF_PLUGIN_DEPS[@]}"; then
            echo "warning: plugin dependencies not satisfied, but plugin will be enabled" >&2
          fi
        fi
      fi
    fi
    # Clear plugin variables
    unset XRF_PLUGIN_ID XRF_PLUGIN_VERSION XRF_PLUGIN_DESC XRF_PLUGIN_HOOKS XRF_PLUGIN_DEPS
  fi

  ln -sfn "../available/${id}/plugin.sh" "${dst}"
  echo "enabled: ${id}"
}
plugins::disable() {
  local id="${1:?id}"

  # Validate plugin ID for security
  plugins::validate_id "${id}" || return 2

  local dst
  dst="$(plugins::dir_enabled)/${id}.sh"
  [[ -e "${dst}" ]] || {
    echo "plugin not enabled: ${id}" >&2
    return 2
  }
  rm -f "${dst}"
  echo "disabled: ${id}"
}
plugins::info() {
  local id="${1:?id}"

  # Validate plugin ID for security
  plugins::validate_id "${id}" || return 2

  local f
  f="$(plugins::dir_available)/${id}/plugin.sh"
  [[ -f "${f}" ]] || {
    echo "plugin not found: ${id}" >&2
    return 2
  }

  # Security: Verify plugin is within expected directory
  local real_f real_av_dir
  real_f="$(realpath "${f}" 2> /dev/null || echo "")"
  real_av_dir="$(realpath "$(plugins::dir_available)" 2> /dev/null || echo "")"

  if [[ -z "${real_f}" || -z "${real_av_dir}" ]] || [[ ! "${real_f}" =~ ^"${real_av_dir}"/ ]]; then
    echo "plugin source validation failed: ${id}" >&2
    return 2
  fi

  # shellcheck source=/dev/null
  . "${f}"
  echo "id: ${XRF_PLUGIN_ID}"
  echo "version: ${XRF_PLUGIN_VERSION:-0.0.0}"
  echo "desc: ${XRF_PLUGIN_DESC:-}"
  echo "hooks: ${XRF_PLUGIN_HOOKS[*]:-}"
}
