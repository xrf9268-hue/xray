#!/usr/bin/env bats
# Unit tests for argument validation (lib/args.sh)

load ../test_helper

setup() {
  setup_test_env
  # Initialize args module
  args::init
}

teardown() {
  cleanup_test_env
}

@test "args::validate_topology - accepts 'reality-only'" {
  run args::validate_topology "reality-only"
  [ "$status" -eq 0 ]
}

@test "args::validate_topology - accepts 'vision-reality'" {
  run args::validate_topology "vision-reality"
  [ "$status" -eq 0 ]
}

@test "args::validate_topology - rejects invalid topology" {
  run args::validate_topology "invalid-topology"
  [ "$status" -ne 0 ]
}

@test "args::validate_topology - rejects empty value" {
  run args::validate_topology ""
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - accepts valid domain" {
  run args::validate_domain "example.com"
  [ "$status" -eq 0 ]
}

@test "args::validate_domain - accepts subdomain" {
  run args::validate_domain "sub.example.com"
  [ "$status" -eq 0 ]
}

@test "args::validate_domain - accepts empty (optional)" {
  run args::validate_domain ""
  [ "$status" -eq 0 ]
}

@test "args::validate_domain - rejects localhost" {
  run args::validate_domain "localhost"
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - rejects .local domain" {
  run args::validate_domain "test.local"
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - rejects IP 127.0.0.1" {
  run args::validate_domain "127.0.0.1"
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - rejects IP 10.0.0.1" {
  run args::validate_domain "10.0.0.1"
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - rejects IP 192.168.1.1" {
  run args::validate_domain "192.168.1.1"
  [ "$status" -ne 0 ]
}

@test "args::validate_domain - rejects invalid format" {
  run args::validate_domain "invalid..domain"
  [ "$status" -ne 0 ]
}

@test "args::validate_version - accepts 'latest'" {
  run args::validate_version "latest"
  [ "$status" -eq 0 ]
}

@test "args::validate_version - accepts semantic version v1.8.1" {
  run args::validate_version "v1.8.1"
  [ "$status" -eq 0 ]
}

@test "args::validate_version - accepts semantic version without 'v' prefix" {
  run args::validate_version "1.8.1"
  [ "$status" -eq 0 ]
}

@test "args::validate_version - rejects invalid version format" {
  run args::validate_version "1.8"
  [ "$status" -ne 0 ]
}

@test "args::validate_version - rejects empty value" {
  run args::validate_version ""
  [ "$status" -ne 0 ]
}

@test "args::validate_config - vision-reality requires domain" {
  TOPOLOGY="vision-reality"
  DOMAIN=""
  run args::validate_config
  [ "$status" -ne 0 ]
}

@test "args::validate_config - vision-reality with domain succeeds" {
  TOPOLOGY="vision-reality"
  DOMAIN="example.com"
  run args::validate_config
  [ "$status" -eq 0 ]
}

@test "args::validate_config - reality-only without domain succeeds" {
  TOPOLOGY="reality-only"
  DOMAIN=""
  run args::validate_config
  [ "$status" -eq 0 ]
}

@test "args::parse - accepts --enable-vless-encryption" {
  args::parse --enable-vless-encryption
  [[ "${VLESS_ENCRYPTION_ENABLED}" == "true" ]]
}

@test "args::parse - accepts --vless-decryption value" {
  args::parse --vless-decryption "mlkem768x25519plus.native.600s.testkey"
  [[ "${VLESS_DECRYPTION}" == "mlkem768x25519plus.native.600s.testkey" ]]
}

@test "args::parse - accepts --vless-encryption value" {
  args::parse --vless-encryption "mlkem768x25519plus.native.0rtt.clientkey"
  [[ "${VLESS_ENCRYPTION}" == "mlkem768x25519plus.native.0rtt.clientkey" ]]
}

@test "args::export_vars - exports vless encryption variables" {
  args::parse --enable-vless-encryption \
    --vless-decryption "mlkem768x25519plus.native.600s.serverkey" \
    --vless-encryption "mlkem768x25519plus.native.0rtt.clientkey"
  args::export_vars

  [[ "${XRAY_VLESS_ENCRYPTION_ENABLED}" == "true" ]]
  [[ "${XRAY_VLESS_DECRYPTION}" == "mlkem768x25519plus.native.600s.serverkey" ]]
  [[ "${XRAY_VLESS_ENCRYPTION}" == "mlkem768x25519plus.native.0rtt.clientkey" ]]
}
