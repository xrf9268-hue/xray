#!/usr/bin/env bats
# Unit tests for backup module jq dependency checking

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/backup.sh"
}

teardown() {
  cleanup_test_env
}

# backup::_require_jq tests

@test "backup::_require_jq - returns 0 when jq is available" {
  # jq should be available in most test environments
  if command -v jq > /dev/null 2>&1; then
    run backup::_require_jq
    [ "$status" -eq 0 ]
  else
    skip "jq not available in test environment"
  fi
}

@test "backup::_require_jq - returns 1 when jq is not available" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    source '"${PROJECT_ROOT}"'/modules/state.sh
    source '"${PROJECT_ROOT}"'/services/xray/common.sh
    source '"${PROJECT_ROOT}"'/lib/backup.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    backup::_require_jq
  '
  [ "$status" -eq 1 ]
}

@test "backup::_require_jq - logs error with installation hint" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    source '"${PROJECT_ROOT}"'/modules/state.sh
    source '"${PROJECT_ROOT}"'/services/xray/common.sh
    source '"${PROJECT_ROOT}"'/lib/backup.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    backup::_require_jq 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
  [[ "$output" == *"hint"* ]] || [[ "$output" == *"Install"* ]]
}

# Integration tests - functions fail early when jq unavailable

@test "backup::create - fails early when jq unavailable" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    source '"${PROJECT_ROOT}"'/modules/state.sh
    source '"${PROJECT_ROOT}"'/services/xray/common.sh
    source '"${PROJECT_ROOT}"'/lib/backup.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    backup::create "test-backup" 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "backup::list - fails early when jq unavailable" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    source '"${PROJECT_ROOT}"'/modules/state.sh
    source '"${PROJECT_ROOT}"'/services/xray/common.sh
    source '"${PROJECT_ROOT}"'/lib/backup.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    backup::list 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "backup::verify - fails early when jq unavailable" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    source '"${PROJECT_ROOT}"'/modules/state.sh
    source '"${PROJECT_ROOT}"'/services/xray/common.sh
    source '"${PROJECT_ROOT}"'/lib/backup.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    backup::verify "test-backup" 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
}

# Verify jq check doesn't break normal operation

@test "backup::_require_jq - does not log when jq is available" {
  if ! command -v jq > /dev/null 2>&1; then
    skip "jq not available in test environment"
  fi

  run backup::_require_jq
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
