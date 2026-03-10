#!/usr/bin/env bats
# Unit tests for plugins/available/cert-auto/plugin.sh
# shellcheck disable=SC2154  # Variables defined in test_helper.bash

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/validators.sh"
  source "${PROJECT_ROOT}/plugins/available/cert-auto/plugin.sh"

  # Stub caddy functions AFTER sourcing plugin (plugin sources caddy.sh)
  caddy::install() { return 0; }
  caddy::setup_auto_tls() { return 0; }
  caddy::setup_cert_sync() { return 0; }
  caddy::wait_for_cert() { return 0; }
}

teardown() {
  cleanup_test_env
  unset XRAY_DOMAIN XRAY_VISION_PORT XRAY_CERT_DIR
}

# === Plugin metadata ===

@test "cert-auto plugin - has correct metadata" {
  [ "$XRF_PLUGIN_ID" = "cert-auto" ]
  [ "$XRF_PLUGIN_VERSION" = "1.0.0" ]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"configure_pre"* ]]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"service_setup"* ]]
}

# === cert_auto::configure_pre Tests ===

@test "cert_auto::configure_pre - skips non-vision-reality topology" {
  run cert_auto::configure_pre "topology=reality-only" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 0 ]
}

@test "cert_auto::configure_pre - fails without domain for vision-reality" {
  unset XRAY_DOMAIN
  run cert_auto::configure_pre "topology=vision-reality" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 1 ]
}

@test "cert_auto::configure_pre - fails with invalid domain" {
  export XRAY_DOMAIN="not a valid domain!"
  run cert_auto::configure_pre "topology=vision-reality" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 1 ]
}

@test "cert_auto::configure_pre - succeeds with valid domain and certs present" {
  export XRAY_DOMAIN="example.com"
  export XRAY_CERT_DIR="${TEST_TMPDIR}/certs"
  mkdir -p "${XRAY_CERT_DIR}"
  touch "${XRAY_CERT_DIR}/fullchain.pem"
  touch "${XRAY_CERT_DIR}/privkey.pem"

  run cert_auto::configure_pre "topology=vision-reality" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 0 ]
}

@test "cert_auto::configure_pre - fails when certs not found after setup" {
  export XRAY_DOMAIN="example.com"
  export XRAY_CERT_DIR="${TEST_TMPDIR}/certs-missing"
  # Don't create cert files

  run cert_auto::configure_pre "topology=vision-reality" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 1 ]
}

@test "cert_auto::configure_pre - fails when caddy install fails" {
  export XRAY_DOMAIN="example.com"
  caddy::install() { return 1; }
  export -f caddy::install

  run cert_auto::configure_pre "topology=vision-reality" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 1 ]
}

# === cert_auto::service_setup Tests ===

@test "cert_auto::service_setup - returns 0 when no privkey exists" {
  export XRAY_CERT_DIR="${TEST_TMPDIR}/no-certs"
  run cert_auto::service_setup
  [ "$status" -eq 0 ]
}

@test "cert_auto::service_setup - sets permissions when certs exist" {
  export XRAY_CERT_DIR="${TEST_TMPDIR}/certs"
  mkdir -p "${XRAY_CERT_DIR}"
  touch "${XRAY_CERT_DIR}/privkey.pem"
  touch "${XRAY_CERT_DIR}/fullchain.pem"

  run cert_auto::service_setup
  [ "$status" -eq 0 ]
}
