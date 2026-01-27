#!/usr/bin/env bats
# Unit tests for core::is_strict_mode and core::ensure_strict_mode functions

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# core::is_strict_mode tests

@test "core::is_strict_mode - returns 0 when strict mode enabled" {
  # Explicitly enable strict mode and test
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -euo pipefail
    core::is_strict_mode
  '
  [ "$status" -eq 0 ]
}

@test "core::is_strict_mode - returns 1 when errexit disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +e  # Disable errexit
    core::is_strict_mode
  '
  [ "$status" -eq 1 ]
}

@test "core::is_strict_mode - returns 1 when nounset disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -e
    set +u  # Disable nounset
    set -o pipefail
    core::is_strict_mode
  '
  [ "$status" -eq 1 ]
}

@test "core::is_strict_mode - returns 1 when pipefail disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -eu
    set +o pipefail  # Disable pipefail
    core::is_strict_mode
  '
  [ "$status" -eq 1 ]
}

@test "core::is_strict_mode - returns 0 with all strict options enabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -euo pipefail
    core::is_strict_mode
  '
  [ "$status" -eq 0 ]
}

# core::ensure_strict_mode tests

@test "core::ensure_strict_mode - returns 0 when strict mode enabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -euo pipefail
    core::ensure_strict_mode "test_module"
  '
  [ "$status" -eq 0 ]
}

@test "core::ensure_strict_mode - returns 1 when strict mode disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +euo pipefail
    core::ensure_strict_mode "test_module"
  '
  [ "$status" -eq 1 ]
}

@test "core::ensure_strict_mode - no output when strict mode enabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set -euo pipefail
    core::ensure_strict_mode "test_module" 2>&1
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "core::ensure_strict_mode - no warning by default when strict mode disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +euo pipefail
    export XRF_STRICT_CHECK=false
    core::ensure_strict_mode "test_module" 2>&1
  '
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "core::ensure_strict_mode - warns when XRF_STRICT_CHECK=true and strict mode disabled" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +euo pipefail
    export XRF_STRICT_CHECK=true
    core::ensure_strict_mode "test_module" 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"strict mode not enabled"* ]]
  [[ "$output" == *"test_module"* ]]
}

@test "core::ensure_strict_mode - includes hint in warning" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +euo pipefail
    export XRF_STRICT_CHECK=true
    core::ensure_strict_mode "backup" 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"core::init"* ]]
}

@test "core::ensure_strict_mode - works without context argument" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    set +euo pipefail
    export XRF_STRICT_CHECK=true
    core::ensure_strict_mode 2>&1
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"strict mode not enabled"* ]]
}

# Integration with core::init

@test "core::init enables strict mode" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    core::init
    core::is_strict_mode
  '
  [ "$status" -eq 0 ]
}

@test "core::ensure_strict_mode passes after core::init" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    core::init
    core::ensure_strict_mode "test"
  '
  [ "$status" -eq 0 ]
}
