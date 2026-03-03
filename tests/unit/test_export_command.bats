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

@test "export unknown subcommand - exits with error" {
  run "${PROJECT_ROOT}/commands/export.sh" invalid-subcmd
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Usage: xrf export"* ]]
}
