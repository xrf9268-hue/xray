#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/errors.sh"
. "${HERE}/lib/validators.sh"
. "${HERE}/lib/plugins.sh"
. "${HERE}/modules/io.sh"
. "${HERE}/modules/state.sh"
. "${HERE}/services/xray/common.sh"

# Xray configuration file naming constants
# Files are numbered to control load order (Xray loads them alphabetically)
readonly XRAY_CONFIG_00_LOG="00_log.json"             # Logging configuration (loaded first)
readonly XRAY_CONFIG_05_INBOUNDS="05_inbounds.json"   # Inbound connections (VLESS/REALITY/Vision)
readonly XRAY_CONFIG_06_OUTBOUNDS="06_outbounds.json" # Outbound connections (direct/block)
readonly XRAY_CONFIG_09_ROUTING="09_routing.json"     # Routing rules (loaded last)

core::log debug "configure.sh started" "$(printf '{"args":"%s"}' "$*")"

# Helper: Sanitize user-derived strings for JSON safety
xray::sanitize_json_string() {
  local value="${1:-}" field="${2:-value}" sanitized

  sanitized="${value//$'\r'/}"
  sanitized="${sanitized//$'\n'/}"

  if [[ "${sanitized}" =~ [\"{}] ]]; then
    core::log error "unsafe characters in input" "$(printf '{"field":"%s"}' "${field}")"
    return "${ERR_INVALID_ARG}"
  fi

  printf '%s' "${sanitized}"
}

# Helper: Convert CSV to sanitized JSON array
json_array_from_csv() {
  local csv="${1}" field="${2:-value}" first_ref_name="${3:-}"
  local IFS=',' raw_items=() sanitized_items=()
  read -ra raw_items <<< "${csv}"

  local item trimmed sanitized first_assigned="false"
  for item in "${raw_items[@]}"; do
    IFS=$' \t\n' read -r trimmed <<< "${item}"
    [[ -z "${trimmed}" ]] && continue
    if ! validators::hostname "${trimmed}"; then
      core::log error "invalid host entry" "$(printf '{"field":"%s","value":"%s"}' "${field}" "${trimmed//\"/\\\\\"}")"
      return "${ERR_INVALID_ARG}"
    fi
    if ! sanitized="$(xray::sanitize_json_string "${trimmed}" "${field}")"; then
      return "${ERR_INVALID_ARG}"
    fi
    if [[ -n "${first_ref_name}" && "${first_assigned}" == "false" ]]; then
      printf -v "${first_ref_name}" '%s' "${sanitized}"
      first_assigned="true"
    fi
    sanitized_items+=("${sanitized}")
  done

  if [[ "${#sanitized_items[@]}" -eq 0 ]]; then
    printf '[]'
    return 0
  fi

  printf '%s\n' "${sanitized_items[@]}" | jq -R . | jq -s .
}

# Helper: Ensure reality destination format (hostname:port)
ensure_reality_dest() {
  local dest="${1}" default_host="${2}"
  IFS=$' \t\n' read -r dest <<< "${dest}"
  [[ -z "${dest}" ]] && dest="${default_host}"

  if [[ -z "${dest}" ]]; then
    core::log error "reality destination required" "{}"
    return "${ERR_INVALID_ARG}"
  fi

  local sanitized
  if ! sanitized="$(xray::sanitize_json_string "${dest}" "XRAY_REALITY_DEST")"; then
    return "${ERR_INVALID_ARG}"
  fi

  local host port
  if [[ "${sanitized}" == *:* ]]; then
    host="${sanitized%%:*}"
    port="${sanitized##*:}"
  else
    host="${sanitized}"
    port="443"
  fi

  if ! validators::hostname "${host}"; then
    core::log error "invalid destination host" "$(printf '{"host":"%s"}' "${host//\"/\\\"}")"
    return "${ERR_INVALID_ARG}"
  fi

  if ! validators::port "${port}"; then
    core::log error "invalid destination port" "$(printf '{"port":"%s"}' "${port}")"
    return "${ERR_INVALID_ARG}"
  fi

  printf '%s:%s' "${host}" "${port}"
}

# Helper: Build shortIds pool array
build_shortids_pool() {
  local primary="${1}" secondary="${2:-}" tertiary="${3:-}"

  if ! validators::shortid "${primary}" || ! validators::shortid "${secondary}" || ! validators::shortid "${tertiary}"; then
    core::log error "invalid shortId provided" "{}"
    return "${ERR_INVALID_ARG}"
  fi

  jq -n --arg primary "${primary}" --arg secondary "${secondary}" --arg tertiary "${tertiary}" '
    ["", $primary]
    + (if $secondary != "" then [$secondary] else [] end)
    + (if $tertiary != "" then [$tertiary] else [] end)
  '
}

##
# Verify TLS certificates exist for vision-reality
#
# Checks for required certificate files (fullchain.pem and privkey.pem)
# in the specified directory.
#
# Arguments:
#   $1 - Certificate directory path (string, required)
#
# Returns:
#   0 - Both certificate files exist
#   1 - One or both certificate files missing
#
# Example:
#   verify_tls_certificates "/usr/local/etc/xray/certs"
##
verify_tls_certificates() {
  local cert_dir="${1}"
  local fullchain="${cert_dir}/fullchain.pem"
  local privkey="${cert_dir}/privkey.pem"

  if [[ ! -f "${fullchain}" ]]; then
    core::log error "TLS certificate not found" "$(printf '{"file":"%s"}' "${fullchain}")"
    return 1
  fi

  if [[ ! -f "${privkey}" ]]; then
    core::log error "TLS private key not found" "$(printf '{"file":"%s"}' "${privkey}")"
    return 1
  fi

  core::log debug "TLS certificates verified" "$(printf '{"cert_dir":"%s"}' "${cert_dir}")"
  return 0
}

# Helper: Calculate config directory digest
digest_confdir() {
  local confdir="${1}"
  if command -v jq > /dev/null 2>&1; then
    (for f in "${confdir}"/*.json; do jq -S -c . "${f}"; done) | sha256sum | awk '{print $1}'
  else
    cat "${confdir}"/*.json | sha256sum | awk '{print $1}'
  fi
}

# Prepare release directory with timestamp
xray::prepare_release_dir() {
  local releases_dir timestamp release_dir
  releases_dir="$(xray::releases)"
  io::ensure_dir "${releases_dir}" 0755
  timestamp="$(date -u +%Y%m%d%H%M%S)"
  release_dir="${releases_dir}/${timestamp}"
  io::ensure_dir "${release_dir}" 0750
  printf '%s' "${release_dir}"
}

# Write base configuration files (log, outbounds, routing)
xray::write_base_configs() {
  local release_dir="${1}"
  local log_level="${XRAY_LOG_LEVEL:-warning}"

  # Logging configuration
  printf '{"log":{"access":"none","error":"none","loglevel":"%s"}}' "${log_level}" \
    | io::atomic_write "${release_dir}/${XRAY_CONFIG_00_LOG}" 0640

  # Outbounds configuration
  printf '{"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}]}' \
    | io::atomic_write "${release_dir}/${XRAY_CONFIG_06_OUTBOUNDS}" 0640

  # Routing configuration
  printf '{"routing":{"domainStrategy":"IPIfNonMatch","rules":[]}}' \
    | io::atomic_write "${release_dir}/${XRAY_CONFIG_09_ROUTING}" 0640

  core::log debug "base configs written" "$(printf '{"dir":"%s"}' "${release_dir}")"
}

# Render Reality-only inbound configuration
xray::render_reality_inbound() {
  local release_dir="${1}"
  local sniff_bool="${2}"

  # Validate required variables
  : "${XRAY_PORT:=443}" : "${XRAY_UUID:?}" : "${XRAY_SNI:=www.microsoft.com}"
  : "${XRAY_SHORT_ID:?}" : "${XRAY_PRIVATE_KEY:?}"

  validators::port "${XRAY_PORT}" || core::log fatal "invalid XRAY_PORT" "$(printf '{"port":"%s"}' "${XRAY_PORT}")"
  validators::uuid "${XRAY_UUID}" || core::log fatal "invalid XRAY_UUID format" "$(printf '{"uuid":"%s"}' "${XRAY_UUID}")"
  validators::shortid "${XRAY_SHORT_ID}" || core::log fatal "invalid XRAY_SHORT_ID" "{}"
  [[ -n "${XRAY_PRIVATE_KEY}" ]] || core::log fatal "XRAY_PRIVATE_KEY required" "{}"

  # Prepare configuration values
  local first_sni reality_dest server_names shortids_pool sanitized_uuid sanitized_key
  server_names="$(json_array_from_csv "${XRAY_SNI}" "XRAY_SNI" first_sni)"
  reality_dest="$(ensure_reality_dest "${XRAY_REALITY_DEST:-}" "${first_sni}")"
  shortids_pool="$(build_shortids_pool "${XRAY_SHORT_ID}" "${XRAY_SHORT_ID_2:-}" "${XRAY_SHORT_ID_3:-}")"
  if ! sanitized_uuid="$(xray::sanitize_json_string "${XRAY_UUID}" "XRAY_UUID")"; then
    core::log fatal "invalid XRAY_UUID characters" "{}"
  fi
  if ! sanitized_key="$(xray::sanitize_json_string "${XRAY_PRIVATE_KEY}" "XRAY_PRIVATE_KEY")"; then
    core::log fatal "invalid XRAY_PRIVATE_KEY characters" "{}"
  fi

  # Write inbound configuration
  jq -n \
    --argjson port "${XRAY_PORT}" \
    --arg uuid "${sanitized_uuid}" \
    --arg dest "${reality_dest}" \
    --argjson serverNames "${server_names}" \
    --arg privateKey "${sanitized_key}" \
    --argjson shortIds "${shortids_pool}" \
    --argjson sniff "${sniff_bool}" \
    '{
      inbounds: [
        {
          tag: "reality",
          listen: "0.0.0.0",
          port: $port,
          protocol: "vless",
          settings: {clients: [{id: $uuid, flow: "xtls-rprx-vision"}], decryption: "none"},
          streamSettings: {
            network: "tcp",
            security: "reality",
            realitySettings: {
              show: false,
              dest: $dest,
              xver: 0,
              serverNames: $serverNames,
              privateKey: $privateKey,
              shortIds: $shortIds,
              spiderX: "/"
            }
          },
          sniffing: {enabled: $sniff, destOverride: ["http","tls","quic"]}
        }
      ]
    }' | io::atomic_write "${release_dir}/${XRAY_CONFIG_05_INBOUNDS}" 0640

  core::log debug "reality-only inbound config written" "$(printf '{"port":%d}' "${XRAY_PORT}")"
}

# Render Vision + Reality dual inbound configuration
xray::render_vision_reality_inbounds() {
  local release_dir="${1}"
  local sniff_bool="${2}"

  # Validate required variables
  : "${XRAY_VISION_PORT:=8443}" : "${XRAY_REALITY_PORT:=443}"
  : "${XRAY_UUID_VISION:?}" : "${XRAY_UUID_REALITY:?}" : "${XRAY_DOMAIN:?}"
  : "${XRAY_CERT_DIR:=/usr/local/etc/xray/certs}" : "${XRAY_FALLBACK_PORT:=8080}"
  : "${XRAY_SNI:=www.microsoft.com}" : "${XRAY_SHORT_ID:?}" : "${XRAY_PRIVATE_KEY:?}"

  core::log debug "vision-reality variables set" "$(printf '{"vision_port":"%s","reality_port":"%s","domain":"%s"}' \
    "${XRAY_VISION_PORT}" "${XRAY_REALITY_PORT}" "${XRAY_DOMAIN}")"

  # Check for required TLS certificates (using extracted helper function)
  if ! verify_tls_certificates "${XRAY_CERT_DIR}"; then
    core::log fatal "vision-reality requires TLS certificates" "$(printf '{"cert_dir":"%s","suggestion":"Use: --plugins cert-auto"}' \
      "${XRAY_CERT_DIR}")"
  fi

  [[ -n "${XRAY_PRIVATE_KEY}" ]] || {
    core::log fatal "XRAY_PRIVATE_KEY required"
  }

  # Prepare configuration values
  validators::port "${XRAY_VISION_PORT}" || core::log fatal "invalid XRAY_VISION_PORT" "$(printf '{"port":"%s"}' "${XRAY_VISION_PORT}")"
  validators::port "${XRAY_REALITY_PORT}" || core::log fatal "invalid XRAY_REALITY_PORT" "$(printf '{"port":"%s"}' "${XRAY_REALITY_PORT}")"
  validators::port "${XRAY_FALLBACK_PORT}" || core::log fatal "invalid XRAY_FALLBACK_PORT" "$(printf '{"port":"%s"}' "${XRAY_FALLBACK_PORT}")"
  validators::uuid "${XRAY_UUID_VISION}" || core::log fatal "invalid XRAY_UUID_VISION format" "$(printf '{"uuid":"%s"}' "${XRAY_UUID_VISION}")"
  validators::uuid "${XRAY_UUID_REALITY}" || core::log fatal "invalid XRAY_UUID_REALITY format" "$(printf '{"uuid":"%s"}' "${XRAY_UUID_REALITY}")"
  validators::domain "${XRAY_DOMAIN}" || core::log fatal "invalid XRAY_DOMAIN" "$(printf '{"domain":"%s"}' "${XRAY_DOMAIN}")"
  validators::shortid "${XRAY_SHORT_ID}" || core::log fatal "invalid XRAY_SHORT_ID" "{}"
  validators::shortid "${XRAY_SHORT_ID_2:-}" || core::log fatal "invalid XRAY_SHORT_ID_2" "{}"
  validators::shortid "${XRAY_SHORT_ID_3:-}" || core::log fatal "invalid XRAY_SHORT_ID_3" "{}"

  local first_sni reality_dest server_names shortids_pool sanitized_vision_uuid sanitized_reality_uuid sanitized_key
  server_names="$(json_array_from_csv "${XRAY_SNI}" "XRAY_SNI" first_sni)"
  reality_dest="$(ensure_reality_dest "${XRAY_REALITY_DEST:-}" "${first_sni}")"
  shortids_pool="$(build_shortids_pool "${XRAY_SHORT_ID}" "${XRAY_SHORT_ID_2:-}" "${XRAY_SHORT_ID_3:-}")"
  if ! sanitized_vision_uuid="$(xray::sanitize_json_string "${XRAY_UUID_VISION}" "XRAY_UUID_VISION")"; then
    core::log fatal "invalid XRAY_UUID_VISION characters" "{}"
  fi
  if ! sanitized_reality_uuid="$(xray::sanitize_json_string "${XRAY_UUID_REALITY}" "XRAY_UUID_REALITY")"; then
    core::log fatal "invalid XRAY_UUID_REALITY characters" "{}"
  fi
  if ! sanitized_key="$(xray::sanitize_json_string "${XRAY_PRIVATE_KEY}" "XRAY_PRIVATE_KEY")"; then
    core::log fatal "invalid XRAY_PRIVATE_KEY characters" "{}"
  fi

  # Write dual inbound configuration
  jq -n \
    --argjson vision_port "${XRAY_VISION_PORT}" \
    --argjson reality_port "${XRAY_REALITY_PORT}" \
    --argjson fallback_port "${XRAY_FALLBACK_PORT}" \
    --arg vision_uuid "${sanitized_vision_uuid}" \
    --arg reality_uuid "${sanitized_reality_uuid}" \
    --argjson serverNames "${server_names}" \
    --arg privateKey "${sanitized_key}" \
    --argjson shortIds "${shortids_pool}" \
    --arg dest "${reality_dest}" \
    --arg cert_dir "${XRAY_CERT_DIR}" \
    --argjson sniff "${sniff_bool}" \
    '{
      inbounds: [
        {
          tag: "vision",
          listen: "0.0.0.0",
          port: $vision_port,
          protocol: "vless",
          settings: {
            clients: [{id: $vision_uuid, flow: "xtls-rprx-vision"}],
            decryption: "none",
            fallbacks: [
              {alpn: "h2", dest: $fallback_port},
              {dest: $fallback_port}
            ]
          },
          streamSettings: {
            network: "tcp",
            security: "tls",
            tlsSettings: {
              minVersion: "1.3",
              rejectUnknownSni: true,
              alpn: ["h2","http/1.1"],
              certificates: [
                {certificateFile: ($cert_dir + "/fullchain.pem"), keyFile: ($cert_dir + "/privkey.pem")}
              ]
            }
          },
          sniffing: {enabled: $sniff, destOverride: ["http","tls"]}
        },
        {
          tag: "reality",
          listen: "0.0.0.0",
          port: $reality_port,
          protocol: "vless",
          settings: {clients: [{id: $reality_uuid, flow: "xtls-rprx-vision"}], decryption: "none"},
          streamSettings: {
            network: "tcp",
            security: "reality",
            realitySettings: {
              show: false,
              dest: $dest,
              xver: 0,
              serverNames: $serverNames,
              privateKey: $privateKey,
              shortIds: $shortIds,
              spiderX: "/"
            }
          },
          sniffing: {enabled: $sniff, destOverride: ["http","tls","quic"]}
        }
      ]
    }' | io::atomic_write "${release_dir}/${XRAY_CONFIG_05_INBOUNDS}" 0640

  core::log debug "vision-reality inbounds config written" "$(printf '{"vision_port":%d,"reality_port":%d}' \
    "${XRAY_VISION_PORT}" "${XRAY_REALITY_PORT}")"
}

# Set permissions for configuration directory and files
xray::set_config_permissions() {
  local release_dir="${1}"

  core::log debug "setting permissions" "$(printf '{"dir":"%s"}' "${release_dir}")"

  chmod 0750 "${release_dir}" || true
  chown root:xray "${release_dir}" 2> /dev/null || true

  # Batch set permissions for all config files (performance: log once instead of per-file)
  local file_count=0
  for f in "${release_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    chown root:xray "${f}" 2> /dev/null || true
    chmod 0640 "${f}" || true
    ((file_count += 1))
  done

  core::log debug "config file permissions set" "$(printf '{"dir":"%s","count":%d}' "${release_dir}" "${file_count}")"
}

# Main function: Orchestrate Xray configuration rendering
render_release() {
  local topology="${1}"

  # Step 1: Prepare release directory
  local release_dir
  release_dir="$(xray::prepare_release_dir)"
  core::log debug "release directory created" "$(printf '{"dir":"%s"}' "${release_dir}")"

  # Step 2: Initialize plugin system and emit pre-configure hooks
  : "${XRAY_LOG_LEVEL:=warning}"
  : "${XRAY_SNIFFING:=false}"
  plugins::ensure_dirs
  plugins::load_enabled
  plugins::emit configure_pre "topology=${topology}" "release_dir=${release_dir}"

  # Step 3: Write base configuration files
  xray::write_base_configs "${release_dir}"

  # Step 4: Determine sniffing mode
  local sniff_bool
  sniff_bool=$([[ "${XRAY_SNIFFING}" == "true" ]] && echo true || echo false)

  # Step 5: Render topology-specific inbound configuration
  case "${topology}" in
    reality-only)
      xray::render_reality_inbound "${release_dir}" "${sniff_bool}"
      ;;
    vision-reality)
      xray::render_vision_reality_inbounds "${release_dir}" "${sniff_bool}"
      ;;
    *)
      core::log fatal "unknown topology" "$(printf '{"topology":"%s"}' "${topology}")"
      ;;
  esac

  # Step 6: Set permissions on config directory and files
  xray::set_config_permissions "${release_dir}"

  # Step 7: Emit post-configure hooks
  core::log debug "emitting configure_post" "$(printf '{"topology":"%s","release_dir":"%s"}' "${topology}" "${release_dir}")"
  plugins::emit configure_post "topology=${topology}" "release_dir=${release_dir}"

  # Step 8: Return release directory path to stdout
  core::log debug "render_release complete" "$(printf '{"release_dir":"%s"}' "${release_dir}")"
  printf '%s\n' "${release_dir}"
}

deploy_release() {
  local release_dir="${1}"
  core::log debug "deploy_release started" "$(printf '{"release_dir":"%s"}' "${release_dir}")"

  # Security: Validate directory path to prevent injection attacks
  # Reject: parent references (..), consecutive slashes (//), invalid characters
  # Note: Dots are allowed for hidden dirs (.config) and temp dirs (xrf.release.xxx)
  if [[ ! "${release_dir}" =~ ^/([a-zA-Z0-9._-]+/)*[a-zA-Z0-9._-]+$ ]] \
    || [[ "${release_dir}" == *".."* ]] \
    || [[ "${release_dir}" == *"//"* ]]; then
    core::log error "invalid directory path" "$(printf '{"path":"%s","reason":"path validation failed"}' "${release_dir//\"/\\\"}")"
    return "${ERR_INVALID_ARG}"
  fi

  if [[ ! -d "${release_dir}" ]]; then
    core::log error "directory does not exist" "$(printf '{"path":"%s"}' "${release_dir}")"
    return 1
  fi

  if [[ -x "$(xray::bin)" ]]; then
    local xray_bin test_output
    xray_bin="$(xray::bin)"

    if ! test_output="$("${xray_bin}" -test -confdir "${release_dir}" -format json 2>&1)"; then
      core::log error "xray config test failed" "$(printf '{"confdir":"%s","test_output":"%s"}' "${release_dir//\"/\\\"}" "${test_output}")"
      printf '%s\n' "${test_output}" >&2
      return 1
    fi
    core::log debug "xray config test passed" "$(printf '{"confdir":"%s"}' "${release_dir}")"
  fi
  local new_digest
  new_digest="$(digest_confdir "${release_dir}")"
  local old_digest=""
  [[ -f "$(state::digest)" ]] && old_digest="$(cat "$(state::digest)")"
  if [[ -n "${old_digest}" && "${old_digest}" == "${new_digest}" ]]; then
    core::log info "no changes; skip reload" "$(printf '{"digest":"%s"}' "${new_digest}")"
    return 0
  fi
  io::ensure_dir "$(xray::confbase)" 0755
  io::ensure_dir "$(xray::releases)" 0755
  ln -sfn "${release_dir}" "$(xray::active).new"
  mv -Tf "$(xray::active).new" "$(xray::active)"
  echo "${new_digest}" | io::atomic_write "$(state::digest)" 0644
  if command -v systemctl > /dev/null 2>&1 && systemctl is-active --quiet xray 2> /dev/null; then systemctl reload-or-restart xray || systemctl restart xray || true; fi
  plugins::emit deploy_post "active_dir=$(xray::active)"
  core::log info "deployed" "$(printf '{"active":"%s"}' "$(xray::active)")"
}

deploy_with_lock() {
  local topology="${1}"
  local release_dir
  release_dir="$(render_release "${topology}")"
  deploy_release "${release_dir}"
}

main() {
  core::init "${@}"
  local topology="reality-only"
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --topology)
        topology="${2}"
        shift 2
        ;;
      *) shift ;;
    esac
  done

  # Security: Validate topology parameter
  case "${topology}" in
    "reality-only" | "vision-reality") ;;
    *)
      core::log fatal "invalid topology" "$(printf '{"topology":"%s","valid_options":"reality-only,vision-reality"}' "${topology}")"
      ;;
  esac
  plugins::ensure_dirs
  plugins::load_enabled
  core::with_flock "$(state::lock)" deploy_with_lock "${topology}"
}
main "${@}"
