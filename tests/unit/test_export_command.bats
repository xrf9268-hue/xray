#!/usr/bin/env bats
# Unit tests for commands/export.sh

load ../test_helper

setup() {
  setup_test_env
  mkdir -p "${XRF_VAR}"
}

teardown() {
  cleanup_test_env
}

write_state() {
  local json="${1}"
  cat <<JSON > "${XRF_VAR}/state.json"
${json}
JSON
}

write_active_inbounds() {
  local json="${1}"
  local active_dir="${XRF_ETC}/xray/active"
  mkdir -p "${active_dir}"
  cat <<JSON > "${active_dir}/05_inbounds.json"
${json}
JSON
}

decode_base64() {
  local input="${1}"
  if decoded="$(printf '%s' "${input}" | base64 --decode 2> /dev/null)"; then
    printf '%s' "${decoded}"
    return 0
  fi
  decoded="$(printf '%s' "${input}" | base64 -d 2> /dev/null)"
  printf '%s' "${decoded}"
}

@test "export uri - emits REALITY link for reality-only topology" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" uri

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"REALITY:"* ]]
  [[ "${output}" == *"vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443"* ]]
}

@test "export sub - emits base64 subscription for all links" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "vision_port": 8443,
      "reality_port": 443,
      "uuid_vision": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "uuid_reality": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" sub

  [ "${status}" -eq 0 ]
  local decoded
  decoded="$(decode_base64 "${output}")"
  [[ "${decoded}" == *"vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443"* ]]
  [[ "${decoded}" == *"vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443"* ]]
}

@test "export clash - outputs valid Clash YAML skeleton" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey==",
      "fingerprint": "chrome"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" clash

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"proxies:"* ]]
  [[ "${output}" == *"type: vless"* ]]
  [[ "${output}" == *"reality-opts:"* ]]
  [[ "${output}" == *"proxy-groups:"* ]]
}

@test "export v2rayn - outputs valid JSON config with outbounds" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" v2rayn

  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.outbounds | type == "array"'
  echo "${output}" | jq -e '.outbounds[0].protocol == "vless"'
}

@test "export all - writes all export files to target directory" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  local out_dir="${TEST_TMPDIR}/exports"
  run env XRAY_SERVER_IP=203.0.113.10 XRF_EXPORT_DIR="${out_dir}" "${PROJECT_ROOT}/commands/export.sh" all

  [ "${status}" -eq 0 ]
  [ -f "${out_dir}/uri.txt" ]
  [ -f "${out_dir}/v2rayn.json" ]
  [ -f "${out_dir}/clash.yaml" ]
  [ -f "${out_dir}/subscription.txt" ]
}

@test "export help - shows usage and exits 0" {
  run "${PROJECT_ROOT}/commands/export.sh" --help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: xrf export"* ]]
  [[ "${output}" == *"Formats:"* ]]
}

@test "export without format - shows usage and exits 0" {
  run "${PROJECT_ROOT}/commands/export.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: xrf export"* ]]
}

@test "export all --out-dir without value - exits with error" {
  run "${PROJECT_ROOT}/commands/export.sh" all --out-dir

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"missing value for --out-dir"* ]]
}

@test "export all --out-dir writes files to explicit directory" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  local out_dir="${TEST_TMPDIR}/exports-opt"
  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" all --out-dir "${out_dir}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Export files written to: ${out_dir}"* ]]
  [ -f "${out_dir}/uri.txt" ]
  [ -f "${out_dir}/v2rayn.json" ]
  [ -f "${out_dir}/clash.yaml" ]
  [ -f "${out_dir}/subscription.txt" ]
}

@test "export uri --unknown-option - exits with error" {
  run "${PROJECT_ROOT}/commands/export.sh" uri --unknown-option

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unknown option"* ]]
  [[ "${output}" == *"Usage: xrf export"* ]]
}

@test "export uri - fails when no usable links exist in state" {
  write_state '{}'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" uri

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"no client links available in state"* ]]
}

@test "export uri - falls back to active shortIds when state short_id is missing" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "reality_public_key": "Base64PublicKey=="
    }
  }'
  write_active_inbounds '{
    "inbounds": [
      {
        "streamSettings": {
          "realitySettings": {
            "shortIds": ["", "fedcba9876543210"]
          }
        }
      }
    ]
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" uri

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sid=fedcba9876543210"* ]]
}

@test "export uri - vision link uses VISION label format" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "vision_port": 8443,
      "uuid_vision": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "fingerprint": "chrome"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" uri

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"VISION : vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443"* ]]
  [[ "${output}" != *"REALITY:"* ]]
}

@test "export v2rayn - vision-reality contains tls and reality outbounds" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "vision_port": 8443,
      "reality_port": 443,
      "uuid_vision": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "uuid_reality": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com,www.bing.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey==",
      "fingerprint": "chrome"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" v2rayn

  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.outbounds | map(select(.tag == "VISION")) | length == 1'
  echo "${output}" | jq -e '.outbounds | map(select(.tag == "REALITY")) | length == 1'
  echo "${output}" | jq -e '.outbounds[] | select(.tag == "VISION") | .streamSettings.security == "tls"'
  echo "${output}" | jq -e '.outbounds[] | select(.tag == "REALITY") | .streamSettings.security == "reality"'
}

@test "export qr - fails when qrencode is missing" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  local mock_bin="${TEST_TMPDIR}/mock-bin"
  mkdir -p "${mock_bin}"
  local required_cmd
  for required_cmd in bash cat date dirname head jq mkdir pwd; do
    ln -s "$(command -v "${required_cmd}")" "${mock_bin}/${required_cmd}"
  done

  run env PATH="${mock_bin}" XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" qr

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"qrencode not found"* ]]
}

@test "export qr - renders links when qrencode is available" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  local mock_bin="${TEST_TMPDIR}/mock-qr"
  mkdir -p "${mock_bin}"
  cat > "${mock_bin}/qrencode" << 'MOCK_QR'
#!/usr/bin/env bash
if [[ "${1:-}" == "-t" && "${2:-}" == "ANSIUTF8" ]]; then
  printf 'MOCK-QR:%s\n' "${3:-}"
else
  printf 'MOCK-QR:%s\n' "${*}"
fi
MOCK_QR
  chmod +x "${mock_bin}/qrencode"

  run env PATH="${mock_bin}:$PATH" XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/commands/export.sh" qr

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"REALITY"* ]]
  [[ "${output}" == *"MOCK-QR:vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443"* ]]
}

@test "export unknown subcommand - exits with error" {
  run "${PROJECT_ROOT}/commands/export.sh" invalid-subcmd
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Usage: xrf export"* ]]
}
