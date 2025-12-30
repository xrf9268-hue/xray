#!/usr/bin/env bats
# Verify modules can be sourced multiple times (idempotent guards)

load '../test_helper'

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

@test "modules/io.sh is idempotent when sourced multiple times" {
  run bash -c 'source "${PROJECT_ROOT}/modules/io.sh"; source "${PROJECT_ROOT}/modules/io.sh"; io::writable "/tmp" >/dev/null'
  [ "$status" -eq 0 ]
}

@test "modules/state.sh is idempotent when sourced multiple times" {
  run bash -c 'source "${PROJECT_ROOT}/modules/state.sh"; source "${PROJECT_ROOT}/modules/state.sh"; state::path >/dev/null'
  [ "$status" -eq 0 ]
}

@test "modules/net/network.sh is idempotent when sourced multiple times" {
  run bash -c 'source "${PROJECT_ROOT}/modules/net/network.sh"; source "${PROJECT_ROOT}/modules/net/network.sh"; type net::detect_public_ip >/dev/null'
  [ "$status" -eq 0 ]
}
