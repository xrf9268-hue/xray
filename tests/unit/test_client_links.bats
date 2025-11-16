#!/usr/bin/env bats
# Unit tests for services/xray/client-links.sh

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

@test "client-links emits populated reality-only link" {
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

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  assert_contains "${output}" "REALITY: vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=Base64PublicKey==&sid=abcd1234ef567890&spx=%2F#REALITY-203.0.113.10"
  [[ "${output}" != *"<UUID>"* ]]
  [[ "${output}" != *"<PUBLIC_KEY>"* ]]
  [[ "${output}" != *"<SHORT_ID>"* ]]
}

@test "client-links emits vision link with TLS parameters" {
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

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" vision-reality

  [ "$status" -eq 0 ]
  assert_contains "${output}" "VISION : vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443?security=tls&flow=xtls-rprx-vision&sni=example.com&fp=chrome#Vision-example.com"
  [[ "${output}" =~ security=tls ]]
  [[ "${output}" =~ flow=xtls-rprx-vision ]]
  [[ "${output}" =~ sni=example.com ]]
  [[ "${output}" =~ fp=chrome ]]
}

@test "client-links emits both vision and reality links for dual topology" {
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

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" vision-reality

  [ "$status" -eq 0 ]
  # Should contain both VISION and REALITY lines
  assert_contains "${output}" "VISION :"
  assert_contains "${output}" "REALITY:"

  # Vision link validation
  assert_contains "${output}" "vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443"

  # Reality link validation
  assert_contains "${output}" "vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443"
  assert_contains "${output}" "pbk=Base64PublicKey=="
  assert_contains "${output}" "sid=abcd1234ef567890"
}

@test "client-links validates all required REALITY parameters present" {
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

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]

  # Verify all required REALITY parameters
  [[ "${output}" =~ encryption=none ]]
  [[ "${output}" =~ flow=xtls-rprx-vision ]]
  [[ "${output}" =~ security=reality ]]
  [[ "${output}" =~ sni=www.microsoft.com ]]
  [[ "${output}" =~ fp=chrome ]]
  [[ "${output}" =~ pbk=Base64PublicKey== ]]
  [[ "${output}" =~ sid=abcd1234ef567890 ]]
  [[ "${output}" =~ spx=%2F ]]
}

@test "client-links handles missing shortId by reading from config" {
  # Create active config directory with inbound configuration
  # xray::active() returns ${XRF_ETC}/xray/active
  mkdir -p "${XRF_ETC}/xray/active"
  cat > "${XRF_ETC}/xray/active/05_inbounds.json" <<'JSON'
{
  "inbounds": [{
    "streamSettings": {
      "realitySettings": {
        "shortIds": ["", "fedcba9876543210", "1234567890abcdef"]
      }
    }
  }]
}
JSON

  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  # Should fallback to shortIds[1] from config (fedcba9876543210)
  assert_contains "${output}" "sid=fedcba9876543210"
}
