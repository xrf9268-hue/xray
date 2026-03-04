#!/usr/bin/env bats
# Regression tests for e2e install lifecycle smoke mirror fallbacks.

load '../test_helper'

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

smoke_mirror_block() {
  awk '/^[[:space:]]*local mirrors=\(/,/^[[:space:]]*\)/ { print }' \
    "${PROJECT_ROOT}/scripts/e2e/install-lifecycle-smoke.sh"
}

has_https_fallback_mirror() {
  smoke_mirror_block | grep -Eq '"https://mirrors\.[^"]+"'
}

has_http_fallback_mirror() {
  smoke_mirror_block | grep -Eq '"http://mirrors\.[^"]+"'
}

@test "install lifecycle smoke mirror fallbacks include HTTPS mirrors" {
  run has_https_fallback_mirror
  [ "${status}" -eq 0 ]
}

@test "install lifecycle smoke mirror fallbacks include HTTP mirrors" {
  run has_http_fallback_mirror
  [ "${status}" -eq 0 ]
}
