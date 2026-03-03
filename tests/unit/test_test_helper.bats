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
