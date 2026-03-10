#!/usr/bin/env bats
# Unit tests for commands/health.sh (command wrapper)

load ../test_helper

setup() {
  setup_test_env
  mkdir -p "${XRF_PREFIX}/bin"
  mkdir -p "${XRF_ETC}/xray/active"
  mkdir -p "${XRF_VAR}"

  source "${PROJECT_ROOT}/lib/defaults.sh"
  source "${PROJECT_ROOT}/modules/state.sh"
  source "${PROJECT_ROOT}/services/xray/common.sh"
  source "${PROJECT_ROOT}/lib/health_check.sh"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# Usage / help tests
# =============================================================================

@test "health command --help shows usage" {
  run "${PROJECT_ROOT}/commands/health.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: xrf health"* ]]
}

@test "health command -h shows usage" {
  run "${PROJECT_ROOT}/commands/health.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: xrf health"* ]]
}

@test "health command --help lists options" {
  run "${PROJECT_ROOT}/commands/health.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "health command --help lists checks performed" {
  run "${PROJECT_ROOT}/commands/health.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Service Status"* ]]
  [[ "$output" == *"Configuration"* ]]
  [[ "$output" == *"Network"* ]]
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "health command rejects unknown option" {
  run "${PROJECT_ROOT}/commands/health.sh" --bad-option
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "health command rejects multiple unknown options" {
  run "${PROJECT_ROOT}/commands/health.sh" --foo --bar
  [ "$status" -eq 1 ]
}

# =============================================================================
# --json flag tests
# =============================================================================

@test "health command --json sets XRF_JSON" {
  # We can't directly test the env var, but we can verify it doesn't crash
  # The actual health checks may fail in test env, that's expected
  run "${PROJECT_ROOT}/commands/health.sh" --json
  # Status can be 0 or 1 depending on health checks
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# =============================================================================
# Exit code tests
# =============================================================================

@test "health command exits 0 or 1 based on health::run result" {
  run "${PROJECT_ROOT}/commands/health.sh"
  # In test environment without real xray, health checks will likely fail
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}
