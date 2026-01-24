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

# =============================================================================
# Additional edge case tests
# =============================================================================

@test "client-links uses custom fingerprint when specified" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey==",
      "fingerprint": "firefox"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  [[ "${output}" =~ fp=firefox ]]
  [[ ! "${output}" =~ fp=chrome ]]
}

@test "client-links defaults to chrome fingerprint when not specified" {
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
  [[ "${output}" =~ fp=chrome ]]
}

@test "client-links uses first SNI from comma-separated list" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com,www.google.com,www.apple.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  # Should use only the first SNI
  [[ "${output}" =~ sni=www.microsoft.com ]]
  # Should NOT contain the commas or other SNIs in the link
  [[ ! "${output}" =~ sni=www.microsoft.com,www.google.com ]]
}

@test "client-links uses default port 443 when not specified" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  assert_contains "${output}" "@203.0.113.10:443?"
}

@test "client-links uses default SNI when not specified" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  # Default SNI should be www.microsoft.com
  [[ "${output}" =~ sni=www.microsoft.com ]]
}

@test "client-links defaults to reality-only topology" {
  write_state '{
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh"

  [ "$status" -eq 0 ]
  # Should output REALITY link (reality-only topology)
  assert_contains "${output}" "REALITY:"
  # Should NOT output VISION link
  [[ ! "${output}" =~ "VISION :" ]]
}

@test "client-links shows placeholder when uuid is missing" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  # Should show placeholder when uuid is missing
  assert_contains "${output}" "<UUID>"
}

@test "client-links shows placeholder when public key is missing" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  # Should show placeholder when public key is missing
  assert_contains "${output}" "<PUBLIC_KEY>"
}

@test "client-links uses YOUR_SERVER_IP when IP detection fails" {
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

  # Run the actual client-links.sh with mocked IP detection
  # Pre-source network.sh to set the guard, then override net::detect_public_ip.
  # When client-links.sh sources network.sh, the guard prevents re-sourcing,
  # so our mock persists.
  run bash -c '
    export XRF_VAR="'"${XRF_VAR}"'"
    export XRF_ETC="'"${XRF_ETC}"'"
    export XRF_JSON=false
    export XRF_DEBUG=false

    # Pre-source network module to establish the source guard
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"

    # Override IP detection to return empty string (simulating failure)
    net::detect_public_ip() { echo ""; }

    # Do NOT set XRAY_SERVER_IP to test the fallback path
    unset XRAY_SERVER_IP 2>/dev/null || true

    # Run the actual client-links.sh script
    # It will use our mocked net::detect_public_ip because the source guard
    # in network.sh prevents re-sourcing
    source "'"${PROJECT_ROOT}/services/xray/client-links.sh"'" reality-only
  '

  [ "$status" -eq 0 ]
  assert_contains "${output}" "@YOUR_SERVER_IP:"
}

@test "client-links outputs header and footer markers" {
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
  assert_contains "${output}" "========== LINKS =========="
  assert_contains "${output}" "=========================="
}

@test "client-links vision-reality uses correct vision port" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "vision_port": 9443,
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
  # Vision link should use vision_port (9443)
  assert_contains "${output}" "@example.com:9443?"
  # Reality link should use reality_port (443)
  assert_contains "${output}" "@203.0.113.10:443?"
}

@test "client-links vision-reality uses default ports when not specified" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "uuid_vision": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "uuid_reality": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" vision-reality

  [ "$status" -eq 0 ]
  # Default vision port is 8443
  assert_contains "${output}" "@example.com:8443?"
  # Default reality port is 443
  assert_contains "${output}" "@203.0.113.10:443?"
}

@test "client-links vision-reality skips vision link when domain missing" {
  write_state '{
    "name": "vision-reality",
    "xray": {
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
  # Should NOT have VISION link (missing domain)
  [[ ! "${output}" =~ "VISION :" ]]
  # Should still have REALITY link
  assert_contains "${output}" "REALITY:"
}

@test "client-links vision-reality skips reality link when uuid_reality missing" {
  write_state '{
    "name": "vision-reality",
    "xray": {
      "domain": "example.com",
      "vision_port": 8443,
      "reality_port": 443,
      "uuid_vision": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" vision-reality

  [ "$status" -eq 0 ]
  # Should have VISION link
  assert_contains "${output}" "VISION :"
  # Should NOT have REALITY link (missing uuid_reality)
  [[ ! "${output}" =~ "REALITY:" ]]
}

@test "client-links handles topology from state.topology field" {
  write_state '{
    "topology": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey=="
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh"

  [ "$status" -eq 0 ]
  assert_contains "${output}" "REALITY:"
}

@test "client-links uses safari fingerprint correctly" {
  write_state '{
    "name": "reality-only",
    "xray": {
      "port": 443,
      "uuid": "11111111-2222-3333-4444-555555555555",
      "reality_sni": "www.microsoft.com",
      "short_id": "abcd1234ef567890",
      "reality_public_key": "Base64PublicKey==",
      "fingerprint": "safari"
    }
  }'

  run env XRAY_SERVER_IP=203.0.113.10 "${PROJECT_ROOT}/services/xray/client-links.sh" reality-only

  [ "$status" -eq 0 ]
  [[ "${output}" =~ fp=safari ]]
}
