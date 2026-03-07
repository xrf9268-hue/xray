#!/usr/bin/env bats
# Regression tests for the bats runtime environment guard.

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

@test "check-bats-runtime succeeds when fd root is readable" {
  local fd_root="${TEST_TMPDIR}/fd-root"
  mkdir -p "${fd_root}"
  : > "${fd_root}/0"

  run env XRF_BATS_FD_ROOT="${fd_root}" bash "${PROJECT_ROOT}/scripts/ci/check-bats-runtime.sh"

  [ "${status}" -eq 0 ]
}

@test "check-bats-runtime fails fast with actionable guidance when fd root is missing" {
  local fd_root="${TEST_TMPDIR}/missing-fd-root"

  run env XRF_BATS_FD_ROOT="${fd_root}" bash "${PROJECT_ROOT}/scripts/ci/check-bats-runtime.sh"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"bats-core requires a readable file-descriptor filesystem"* ]]
  [[ "${output}" == *"${fd_root}/0"* ]]
  [[ "${output}" == *"/proc/self/fd"* ]]
}
