#!/usr/bin/env bats
# Integration test for uninstall idempotency

load test_helper

setup() {
  setup_integration_env
}

teardown() {
  cleanup_integration_env
}

@test "uninstall command is idempotent on missing targets" {
  run env \
    XRF_PREFIX="${XRF_PREFIX}" \
    XRF_ETC="${XRF_ETC}" \
    XRF_VAR="${XRF_VAR}" \
    "${PROJECT_ROOT}/commands/uninstall.sh"
  [ "$status" -eq 0 ]

  run env \
    XRF_PREFIX="${XRF_PREFIX}" \
    XRF_ETC="${XRF_ETC}" \
    XRF_VAR="${XRF_VAR}" \
    "${PROJECT_ROOT}/commands/uninstall.sh"
  [ "$status" -eq 0 ]
}
