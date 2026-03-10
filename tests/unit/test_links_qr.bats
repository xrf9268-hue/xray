#!/usr/bin/env bats
# Unit tests for plugins/available/links-qr/plugin.sh
# shellcheck disable=SC2154  # Variables defined in test_helper.bash

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/plugins/available/links-qr/plugin.sh"
}

teardown() {
  cleanup_test_env
}

# === Plugin metadata ===

@test "links-qr plugin - has correct metadata" {
  [ "$XRF_PLUGIN_ID" = "links-qr" ]
  [ "$XRF_PLUGIN_VERSION" = "1.2.0" ]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"links_render"* ]]
  [[ "${XRF_PLUGIN_DEPS[*]}" == *"qrencode"* ]]
}

# === links_qr::links_render Tests ===

@test "links_qr::links_render - returns 0 with empty link" {
  run links_qr::links_render "link=" "topology=reality-only"
  [ "$status" -eq 0 ]
}

@test "links_qr::links_render - returns 0 with no arguments" {
  run links_qr::links_render
  [ "$status" -eq 0 ]
}

@test "links_qr::links_render - warns when qrencode not available" {
  # Use a PATH without qrencode
  PATH="/usr/bin:/bin" run links_qr::links_render "link=vless://test@1.2.3.4:443" "topology=reality-only"
  [ "$status" -eq 0 ]
}

@test "links_qr::links_render - parses topology argument" {
  # Verify it doesn't crash on valid arguments even without qrencode
  PATH="/usr/bin:/bin" run links_qr::links_render "link=test-link" "topology=vision-reality"
  [ "$status" -eq 0 ]
}
