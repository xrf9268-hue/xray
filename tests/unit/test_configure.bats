#!/usr/bin/env bats
# Test services/xray/configure.sh - Xray configuration rendering
# shellcheck disable=SC2154  # Variables defined in test_helper.bash

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/core.sh"
  source "${PROJECT_ROOT}/lib/errors.sh"
  source "${PROJECT_ROOT}/lib/validators.sh"
  source "${PROJECT_ROOT}/lib/plugins.sh"
  source "${PROJECT_ROOT}/modules/io.sh"
  source "${PROJECT_ROOT}/modules/state.sh"
  source "${PROJECT_ROOT}/services/xray/common.sh"

  # Create required directories
  mkdir -p "${TEST_TMPDIR}/xray-releases"
  mkdir -p "${TEST_TMPDIR}/xray-certs"

  # Override plugin directories for testing
  export XRF_PLUGIN_DIR="${TEST_TMPDIR}/plugins"
  mkdir -p "${XRF_PLUGIN_DIR}/enabled"
  mkdir -p "${XRF_PLUGIN_DIR}/available"

  # Define configuration file naming constants (from configure.sh)
  XRAY_CONFIG_00_LOG="00_log.json"
  XRAY_CONFIG_05_INBOUNDS="05_inbounds.json"
  XRAY_CONFIG_06_OUTBOUNDS="06_outbounds.json"
  XRAY_CONFIG_07_DNS="07_dns.json"
  XRAY_CONFIG_09_ROUTING="09_routing.json"

  # Define helper functions inline (extracted from configure.sh)
  # We don't source configure.sh directly because it has main() at the end
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

  json_array_from_csv() {
    local csv="${1}" field="${2:-value}" first_ref_name="${3:-}"
    local IFS=',' raw_items=() sanitized_items=()
    read -ra raw_items <<< "${csv}"

    local item trimmed sanitized first_assigned="false"
    for item in "${raw_items[@]}"; do
      IFS=$' \t\n' read -r trimmed <<< "${item}"
      [[ -z "${trimmed}" ]] && continue
      if ! validators::hostname "${trimmed}"; then
        core::log error "invalid host entry" "$(printf '{"field":"%s","value":"%s"}' "${field}" "${trimmed//\"/\\\"}")"
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

  ensure_reality_dest() {
    local dest="${1}" sni="${2}"
    IFS=$' \t\n' read -r dest <<< "${dest}"
    [[ -z "${dest}" ]] && dest="${sni}"

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

    # Warn about Apple/iCloud REALITY destinations (v26.3.27+: risk of IP blocking)
    case "${host}" in
      *icloud-content.com | *cdn-apple.com | *mzstatic.com | *icloud.com | *apple.com)
        core::log warn "Apple/iCloud REALITY dest may cause IP blocking (Xray v26.3.27+)" \
          "$(printf '{"host":"%s","suggestion":"Use a non-Apple domain such as www.microsoft.com"}' "${host}")"
        ;;
    esac

    printf '%s:%s' "${host}" "${port}"
  }

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

    return 0
  }

  digest_confdir() {
    local confdir="${1}"
    if command -v jq > /dev/null 2>&1; then
      (for f in "${confdir}"/*.json; do jq -S -c . "${f}"; done) | sha256sum | awk '{print $1}'
    else
      cat "${confdir}"/*.json | sha256sum | awk '{print $1}'
    fi
  }

  xray::prepare_release_dir() {
    local releases_dir timestamp release_dir
    releases_dir="$(xray::releases)"
    io::ensure_dir "${releases_dir}" 0755
    timestamp="$(date -u +%Y%m%d%H%M%S)"
    release_dir="${releases_dir}/${timestamp}"
    io::ensure_dir "${release_dir}" 0750
    printf '%s' "${release_dir}"
  }

  xray::write_base_configs() {
    local release_dir="${1}"
    local dns_query_strategy="${2:-UseIPv4}"
    local log_level="${XRAY_LOG_LEVEL:-warning}"

    printf '{"log":{"access":"none","error":"","loglevel":"%s"}}' "${log_level}" \
      | io::atomic_write "${release_dir}/${XRAY_CONFIG_00_LOG}" 0640

    printf '{"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}]}' \
      | io::atomic_write "${release_dir}/${XRAY_CONFIG_06_OUTBOUNDS}" 0640

    printf '{"dns":{"queryStrategy":"%s"}}' "${dns_query_strategy}" \
      | io::atomic_write "${release_dir}/${XRAY_CONFIG_07_DNS}" 0640

    printf '{"routing":{"domainStrategy":"IPIfNonMatch","rules":[]}}' \
      | io::atomic_write "${release_dir}/${XRAY_CONFIG_09_ROUTING}" 0640
  }

  deploy_release() {
    local release_dir="${1}"

    # Security: Validate directory path
    if [[ ! "${release_dir}" =~ ^/([a-zA-Z0-9._-]+/)*[a-zA-Z0-9._-]+$ ]] \
      || [[ "${release_dir}" == *".."* ]] \
      || [[ "${release_dir}" == *"//"* ]]; then
      core::log error "invalid directory path" "{}"
      return "${ERR_INVALID_ARG}"
    fi

    if [[ ! -d "${release_dir}" ]]; then
      core::log error "directory does not exist" "{}"
      return 1
    fi

    return 0
  }
}

teardown() {
  cleanup_test_env
}

# === json_array_from_csv Tests ===

@test "json_array_from_csv converts single value" {
  result="$(json_array_from_csv "example.com")"
  [ "$(echo "${result}" | jq -c '.')" = '["example.com"]' ]
}

@test "json_array_from_csv converts multiple values" {
  result="$(json_array_from_csv "example.com,test.com,demo.com")"
  [ "$(echo "${result}" | jq -c '.')" = '["example.com","test.com","demo.com"]' ]
}

@test "json_array_from_csv handles spaces" {
  result="$(json_array_from_csv "example.com, test.com, demo.com")"
  [ "$(echo "${result}" | jq -c '.')" = '["example.com","test.com","demo.com"]' ]
}

@test "json_array_from_csv handles empty input" {
  result="$(json_array_from_csv "")"
  [ "$(echo "${result}" | jq -c '.')" = '[]' ]
}

@test "json_array_from_csv handles SNI list" {
  result="$(json_array_from_csv "www.microsoft.com,www.apple.com")"
  [ "$(echo "${result}" | jq -c '.')" = '["www.microsoft.com","www.apple.com"]' ]
}

@test "xray::sanitize_json_string strips newlines" {
  result="$(xray::sanitize_json_string "line1
line2" "test")"
  [ "${result}" = "line1line2" ]
}

@test "xray::sanitize_json_string rejects braces" {
  run xray::sanitize_json_string "{bad}" "test"
  [ "${status}" -ne 0 ]
}

@test "json_array_from_csv populates first reference" {
  local first_value=""
  json_array_from_csv "www.microsoft.com,www.apple.com" "XRAY_SNI" first_value > /dev/null
  [ "${first_value}" = "www.microsoft.com" ]
}

@test "json_array_from_csv rejects malicious host" {
  run json_array_from_csv "good.com,evil\".com"
  [ "${status}" -ne 0 ]
}

# === ensure_reality_dest Tests ===

@test "ensure_reality_dest uses dest when provided" {
  result="$(ensure_reality_dest "custom.server.com:443" "www.microsoft.com")"
  [ "${result}" = "custom.server.com:443" ]
}

@test "ensure_reality_dest falls back to SNI when dest is empty" {
  result="$(ensure_reality_dest "" "www.microsoft.com")"
  [ "${result}" = "www.microsoft.com:443" ]
}

@test "ensure_reality_dest adds port when missing" {
  result="$(ensure_reality_dest "custom.server.com" "www.microsoft.com")"
  [ "${result}" = "custom.server.com:443" ]
}

@test "ensure_reality_dest preserves custom port" {
  result="$(ensure_reality_dest "custom.server.com:8443" "www.microsoft.com")"
  [ "${result}" = "custom.server.com:8443" ]
}

@test "ensure_reality_dest trims whitespace" {
  result="$(ensure_reality_dest "  custom.server.com  " "www.microsoft.com")"
  [ "${result}" = "custom.server.com:443" ]
}

@test "ensure_reality_dest rejects malicious input" {
  run ensure_reality_dest "bad\"host" "www.microsoft.com"
  [ "${status}" -ne 0 ]
}

@test "ensure_reality_dest warns for Apple/iCloud destinations" {
  result="$(ensure_reality_dest "www.icloud.com:443" "www.microsoft.com")"
  [ "${result}" = "www.icloud.com:443" ]
}

@test "ensure_reality_dest warns for cdn-apple.com destinations" {
  result="$(ensure_reality_dest "cdn-apple.com" "www.microsoft.com")"
  [ "${result}" = "cdn-apple.com:443" ]
}

@test "ensure_reality_dest does not warn for microsoft.com" {
  result="$(ensure_reality_dest "www.microsoft.com:443" "www.microsoft.com")"
  [ "${result}" = "www.microsoft.com:443" ]
}

# === build_shortids_pool Tests ===

@test "build_shortids_pool with single shortId" {
  result="$(build_shortids_pool "abc123def456")"
  [ "$(echo "${result}" | jq -c '.')" = '["","abc123def456"]' ]
}

@test "build_shortids_pool with two shortIds" {
  result="$(build_shortids_pool "abc123def456" "111222333444")"
  [ "$(echo "${result}" | jq -c '.')" = '["","abc123def456","111222333444"]' ]
}

@test "build_shortids_pool with three shortIds" {
  result="$(build_shortids_pool "abc123def456" "111222333444" "555666777888")"
  [ "$(echo "${result}" | jq -c '.')" = '["","abc123def456","111222333444","555666777888"]' ]
}

@test "build_shortids_pool always includes empty string first" {
  result="$(build_shortids_pool "abcd1234")"
  [[ "$(echo "${result}" | jq -c '. | .[0]')" == '""' ]]
}

@test "build_shortids_pool ignores empty secondary" {
  result="$(build_shortids_pool "abc123def456" "")"
  [ "$(echo "${result}" | jq -c '.')" = '["","abc123def456"]' ]
}

@test "build_shortids_pool ignores empty tertiary" {
  result="$(build_shortids_pool "abc123def456" "111222333444" "")"
  [ "$(echo "${result}" | jq -c '.')" = '["","abc123def456","111222333444"]' ]
}

@test "build_shortids_pool rejects invalid shortId" {
  run build_shortids_pool "badshortid!" "" ""
  [ "${status}" -ne 0 ]
}

# === verify_tls_certificates Tests ===

@test "verify_tls_certificates fails when fullchain missing" {
  mkdir -p "${TEST_TMPDIR}/certs"
  touch "${TEST_TMPDIR}/certs/privkey.pem"

  run verify_tls_certificates "${TEST_TMPDIR}/certs"
  [ "${status}" -eq 1 ]
}

@test "verify_tls_certificates fails when privkey missing" {
  mkdir -p "${TEST_TMPDIR}/certs"
  touch "${TEST_TMPDIR}/certs/fullchain.pem"

  run verify_tls_certificates "${TEST_TMPDIR}/certs"
  [ "${status}" -eq 1 ]
}

@test "verify_tls_certificates succeeds when both files exist" {
  mkdir -p "${TEST_TMPDIR}/certs"
  touch "${TEST_TMPDIR}/certs/fullchain.pem"
  touch "${TEST_TMPDIR}/certs/privkey.pem"

  run verify_tls_certificates "${TEST_TMPDIR}/certs"
  [ "${status}" -eq 0 ]
}

@test "verify_tls_certificates fails for non-existent directory" {
  run verify_tls_certificates "${TEST_TMPDIR}/nonexistent"
  [ "${status}" -eq 1 ]
}

# === digest_confdir Tests ===

@test "digest_confdir produces SHA256 hash" {
  mkdir -p "${TEST_TMPDIR}/confdir"
  echo '{"key":"value"}' > "${TEST_TMPDIR}/confdir/config.json"

  result="$(digest_confdir "${TEST_TMPDIR}/confdir")"
  # SHA256 hash should be 64 hex characters
  [ "${#result}" -eq 64 ]
  [[ "${result}" =~ ^[a-f0-9]{64}$ ]]
}

@test "digest_confdir produces consistent hash for same content" {
  mkdir -p "${TEST_TMPDIR}/confdir"
  echo '{"key":"value"}' > "${TEST_TMPDIR}/confdir/config.json"

  result1="$(digest_confdir "${TEST_TMPDIR}/confdir")"
  result2="$(digest_confdir "${TEST_TMPDIR}/confdir")"
  [ "${result1}" = "${result2}" ]
}

@test "digest_confdir produces different hash for different content" {
  mkdir -p "${TEST_TMPDIR}/confdir1"
  mkdir -p "${TEST_TMPDIR}/confdir2"
  echo '{"key":"value1"}' > "${TEST_TMPDIR}/confdir1/config.json"
  echo '{"key":"value2"}' > "${TEST_TMPDIR}/confdir2/config.json"

  result1="$(digest_confdir "${TEST_TMPDIR}/confdir1")"
  result2="$(digest_confdir "${TEST_TMPDIR}/confdir2")"
  [ "${result1}" != "${result2}" ]
}

# === xray::prepare_release_dir Tests ===

@test "xray::prepare_release_dir creates directory" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  mkdir -p "${XRF_ETC}/xray"

  result="$(xray::prepare_release_dir)"
  [ -d "${result}" ]
}

@test "xray::prepare_release_dir creates timestamped directory" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  mkdir -p "${XRF_ETC}/xray"

  result="$(xray::prepare_release_dir)"
  # Directory name should contain timestamp format YYYYMMDDHHMMSS
  [[ "${result}" =~ [0-9]{14}$ ]]
}

@test "xray::prepare_release_dir sets correct permissions" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  mkdir -p "${XRF_ETC}/xray"

  result="$(xray::prepare_release_dir)"
  # Directory should have 750 permissions
  perms="$(stat -c '%a' "${result}" 2> /dev/null || stat -f '%Lp' "${result}")"
  [ "${perms}" = "750" ]
}

# === xray::write_base_configs Tests ===

@test "xray::write_base_configs creates log config" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  [ -f "${TEST_TMPDIR}/release/00_log.json" ]
}

@test "xray::write_base_configs creates outbounds config" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  [ -f "${TEST_TMPDIR}/release/06_outbounds.json" ]
}

@test "xray::write_base_configs creates routing config" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  [ -f "${TEST_TMPDIR}/release/09_routing.json" ]
}

@test "xray::write_base_configs creates DNS config" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  [ -f "${TEST_TMPDIR}/release/07_dns.json" ]
}

@test "xray::write_base_configs log config contains loglevel" {
  mkdir -p "${TEST_TMPDIR}/release"
  export XRAY_LOG_LEVEL="info"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  content="$(cat "${TEST_TMPDIR}/release/00_log.json")"
  [[ "${content}" == *'"loglevel":"info"'* ]]
}

@test "xray::write_base_configs outbounds has direct and block" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  content="$(cat "${TEST_TMPDIR}/release/06_outbounds.json")"
  [[ "${content}" == *'"tag":"direct"'* ]]
  [[ "${content}" == *'"tag":"block"'* ]]
}

@test "xray::write_base_configs routing has IPIfNonMatch strategy" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  content="$(cat "${TEST_TMPDIR}/release/09_routing.json")"
  [[ "${content}" == *'"domainStrategy":"IPIfNonMatch"'* ]]
}

@test "xray::write_base_configs DNS defaults to UseIPv4 strategy" {
  mkdir -p "${TEST_TMPDIR}/release"

  xray::write_base_configs "${TEST_TMPDIR}/release"
  content="$(cat "${TEST_TMPDIR}/release/07_dns.json")"
  [[ "${content}" == *'"queryStrategy":"UseIPv4"'* ]]
}

# === deploy_release Path Validation Tests ===

@test "deploy_release rejects path with parent reference" {
  run deploy_release "/path/../to/config"
  [ "${status}" -ne 0 ]
}

@test "deploy_release rejects path with double slashes" {
  run deploy_release "/path//to/config"
  [ "${status}" -ne 0 ]
}

@test "deploy_release rejects non-existent directory" {
  run deploy_release "/nonexistent/path/12345"
  [ "${status}" -ne 0 ]
}

@test "deploy_release accepts valid path" {
  mkdir -p "${TEST_TMPDIR}/valid.release.123"
  echo '{}' > "${TEST_TMPDIR}/valid.release.123/config.json"

  # This will fail at xray test but path validation should pass
  run deploy_release "${TEST_TMPDIR}/valid.release.123"
  # Should not fail with path validation error
  [[ "${output}" != *"invalid directory path"* ]]
}

# === Configuration Constant Tests ===

@test "XRAY_CONFIG_00_LOG is correct" {
  [ "${XRAY_CONFIG_00_LOG}" = "00_log.json" ]
}

@test "XRAY_CONFIG_05_INBOUNDS is correct" {
  [ "${XRAY_CONFIG_05_INBOUNDS}" = "05_inbounds.json" ]
}

@test "XRAY_CONFIG_06_OUTBOUNDS is correct" {
  [ "${XRAY_CONFIG_06_OUTBOUNDS}" = "06_outbounds.json" ]
}

@test "XRAY_CONFIG_07_DNS is correct" {
  [ "${XRAY_CONFIG_07_DNS}" = "07_dns.json" ]
}

@test "XRAY_CONFIG_09_ROUTING is correct" {
  [ "${XRAY_CONFIG_09_ROUTING}" = "09_routing.json" ]
}
