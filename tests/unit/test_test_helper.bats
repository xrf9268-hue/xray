#!/usr/bin/env bats
# Compatibility tests for tests/test_helper.bash

load ../test_helper

@test "setup_test_env falls back to TEST_TMPDIR when BATS_TEST_TMPDIR is unset" {
  local old_bats_tmpdir="${BATS_TEST_TMPDIR-}"
  local had_bats_tmpdir=0
  if [[ -n "${BATS_TEST_TMPDIR+x}" ]]; then
    had_bats_tmpdir=1
  fi

  unset BATS_TEST_TMPDIR || true
  setup_test_env

  [ -n "${TEST_TMPDIR:-}" ]
  [ -n "${BATS_TEST_TMPDIR:-}" ]
  [ "${BATS_TEST_TMPDIR}" = "${TEST_TMPDIR}" ]

  cleanup_test_env
  if [[ "${had_bats_tmpdir}" -eq 1 ]]; then
    export BATS_TEST_TMPDIR="${old_bats_tmpdir}"
  else
    unset BATS_TEST_TMPDIR || true
  fi
}

@test "test_helper defines bats_require_minimum_version compatibility shim when missing" {
  run bash -c '
    set -euo pipefail
    unset -f bats_require_minimum_version 2>/dev/null || true
    # shellcheck source=tests/test_helper.bash
    . "'"${PROJECT_ROOT}"'/tests/test_helper.bash"
    declare -F bats_require_minimum_version >/dev/null
  '
  [ "$status" -eq 0 ]
}
