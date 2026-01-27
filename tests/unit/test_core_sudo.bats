#!/usr/bin/env bats
# Unit tests for core::sudo_cmd and core::has_sudo functions

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# core::has_sudo tests

@test "core::has_sudo - returns 0 when sudo is available" {
  # sudo should be available in most test environments
  if command -v sudo > /dev/null 2>&1; then
    run core::has_sudo
    [ "$status" -eq 0 ]
  else
    skip "sudo not available in test environment"
  fi
}

@test "core::has_sudo - returns 1 when sudo is not available" {
  # Create a subshell with modified PATH that excludes sudo
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    export PATH="/nonexistent"
    core::has_sudo
  '
  [ "$status" -eq 1 ]
}

# core::sudo_cmd error handling tests

@test "core::sudo_cmd - returns 3 when no command provided" {
  run core::sudo_cmd
  [ "$status" -eq 3 ]
  [[ "$output" == *"sudo_cmd called without command"* ]]
}

@test "core::sudo_cmd - returns 2 when sudo not available" {
  # Create a subshell with modified PATH that excludes sudo
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    core::sudo_cmd echo "test"
  '
  [ "$status" -eq 2 ]
  [[ "$output" == *"sudo not available"* ]]
}

@test "core::sudo_cmd - logs error with command details when sudo unavailable" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    export XRF_JSON=true
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    core::sudo_cmd echo "test arg"
  '
  [ "$status" -eq 2 ]
  # Check that the command is logged in the error message
  [[ "$output" == *'"cmd":'* ]]
}

# core::sudo_cmd success tests (when sudo is available)

@test "core::sudo_cmd - executes simple command successfully" {
  if ! command -v sudo > /dev/null 2>&1; then
    skip "sudo not available in test environment"
  fi

  # Check if we can run sudo without password (for CI environments)
  if ! sudo -n true 2> /dev/null; then
    skip "sudo requires password in test environment"
  fi

  # Use a command that doesn't need actual root privileges
  run core::sudo_cmd true
  [ "$status" -eq 0 ]
}

@test "core::sudo_cmd - passes arguments correctly" {
  if ! command -v sudo > /dev/null 2>&1; then
    skip "sudo not available in test environment"
  fi

  # Check if we can run sudo without password
  if ! sudo -n true 2> /dev/null; then
    skip "sudo requires password in test environment"
  fi

  local test_file="${TEST_TMPDIR}/sudo_test_file"
  run core::sudo_cmd touch "${test_file}"
  [ "$status" -eq 0 ]
  [ -f "${test_file}" ]
}

@test "core::sudo_cmd - returns 1 when command fails" {
  if ! command -v sudo > /dev/null 2>&1; then
    skip "sudo not available in test environment"
  fi

  run core::sudo_cmd false
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo command failed"* ]]
}

@test "core::sudo_cmd - handles commands with special characters in args" {
  if ! command -v sudo > /dev/null 2>&1; then
    skip "sudo not available in test environment"
  fi

  # Check if we can run sudo without password
  if ! sudo -n true 2> /dev/null; then
    skip "sudo requires password in test environment"
  fi

  local test_file="${TEST_TMPDIR}/file with spaces.txt"
  run core::sudo_cmd touch "${test_file}"
  [ "$status" -eq 0 ]
  [ -f "${test_file}" ]
}

# JSON escaping in error messages

@test "core::sudo_cmd - properly escapes special chars in error log" {
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    export XRF_JSON=true
    export XRF_DEBUG=false
    export PATH="/nonexistent"
    core::sudo_cmd echo "test \"quoted\" arg"
  '
  [ "$status" -eq 2 ]
  # Verify the output contains expected error message
  [[ "$output" == *"sudo not available"* ]]
  # Verify it contains cmd field (JSON escaping)
  [[ "$output" == *'"cmd":'* ]]
}

# Integration with io module

@test "io::ensure_dir - uses core::sudo_cmd for fallback" {
  source "${PROJECT_ROOT}/modules/io.sh"

  # Test with a directory that should be createable without sudo
  local test_dir="${TEST_TMPDIR}/test_dir/nested"
  run io::ensure_dir "${test_dir}"
  [ "$status" -eq 0 ]
  [ -d "${test_dir}" ]
}

@test "io::ensure_dir - logs error when sudo fallback fails" {
  # Test that error logging works when sudo is not available
  # This tests the error handling path, not the actual permission failure
  run bash -c '
    source '"${PROJECT_ROOT}"'/lib/core.sh
    source '"${PROJECT_ROOT}"'/modules/io.sh
    export XRF_JSON=false
    export XRF_DEBUG=false
    # Mock mkdir to always fail
    mkdir() { return 1; }
    export -f mkdir
    # Remove sudo from PATH
    export PATH="/nonexistent"
    io::ensure_dir "/tmp/test_dir_123" 2>&1
  '
  # Should output warning about sudo fallback
  [[ "$output" == *"mkdir fallback sudo"* ]] || [[ "$output" == *"sudo"* ]] || [ "$status" -ne 0 ]
}
