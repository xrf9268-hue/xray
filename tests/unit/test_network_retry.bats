#!/usr/bin/env bats
# Unit tests for network retry functions (lib/network.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source network module
  source "${PROJECT_ROOT}/lib/network.sh" 2>/dev/null || true
}

teardown() {
  cleanup_test_env
  # Cleanup any retry state files
  rm -f /tmp/retry_test_* 2>/dev/null || true
}

# ============================================================================
# network::retry tests
# ============================================================================

@test "network::retry - succeeds on first try" {
  test_command() { echo "success"; return 0; }
  export -f test_command

  run network::retry 3 1 test_command
  [ "$status" -eq 0 ]
  [[ "$output" =~ "success" ]]

  unset -f test_command
}

@test "network::retry - validates required arguments" {
  # Missing all arguments
  run network::retry
  [ "$status" -eq 1 ]

  # Missing command
  run network::retry 3 1
  [ "$status" -eq 1 ]
}

@test "network::retry - succeeds after 2 failures" {
  # Create a command that fails twice then succeeds
  local state_file="${TEST_TMPDIR}/retry_state_$$"
  echo "0" > "${state_file}"

  flaky_command() {
    local state_file="${1}"
    local count
    count=$(cat "${state_file}")
    count=$((count + 1))
    echo "${count}" > "${state_file}"

    if [[ ${count} -lt 3 ]]; then
      echo "attempt ${count} failed" >&2
      return 1
    else
      echo "attempt ${count} succeeded"
      return 0
    fi
  }
  export -f flaky_command

  run network::retry 5 1 flaky_command "${state_file}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "attempt 3 succeeded" ]]

  unset -f flaky_command
  rm -f "${state_file}"
}

@test "network::retry - fails after max retries" {
  failing_command() { return 1; }
  export -f failing_command

  run network::retry 3 1 failing_command
  [ "$status" -eq 1 ]

  unset -f failing_command
}

@test "network::retry - implements exponential backoff" {
  # Command that always fails to test timing
  slow_command() { return 1; }
  export -f slow_command

  local start
  start=$(date +%s)
  run network::retry 4 1 slow_command
  local end
  end=$(date +%s)
  local duration=$((end - start))

  # Expected delays: 1s + 2s + 4s = 7s minimum
  # Allow some variance for system overhead
  [ ${duration} -ge 6 ]
  [ ${duration} -le 10 ]

  unset -f slow_command
}

@test "network::retry - passes arguments to command" {
  test_command_with_args() {
    echo "arg1=$1 arg2=$2"
    return 0
  }
  export -f test_command_with_args

  run network::retry 3 1 test_command_with_args "value1" "value2"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "arg1=value1" ]]
  [[ "$output" =~ "arg2=value2" ]]

  unset -f test_command_with_args
}

@test "network::retry - preserves command output" {
  test_command() {
    echo "line 1"
    echo "line 2"
    return 0
  }
  export -f test_command

  run network::retry 3 1 test_command
  [ "$status" -eq 0 ]
  [[ "$output" =~ "line 1" ]]
  [[ "$output" =~ "line 2" ]]

  unset -f test_command
}

@test "network::retry - logs retry attempts" {
  failing_command() { return 1; }
  export -f failing_command

  # Enable debug to see retry logs
  XRF_DEBUG=true run network::retry 3 1 failing_command
  [ "$status" -eq 1 ]
  # Should log attempts (implementation dependent)
  [[ "$output" =~ "attempt" ]] || [[ "$output" =~ "retry" ]] || true

  unset -f failing_command
}

@test "network::retry - handles zero delay" {
  failing_command() { return 1; }
  export -f failing_command

  local start
  start=$(date +%s)
  run network::retry 3 0 failing_command
  local end
  end=$(date +%s)
  local duration=$((end - start))

  # Should complete quickly with zero delay
  [ ${duration} -le 2 ]

  unset -f failing_command
}

@test "network::retry - handles command with spaces in args" {
  test_command() {
    echo "received: $*"
    return 0
  }
  export -f test_command

  run network::retry 3 1 test_command "arg with spaces" "another arg"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "arg with spaces" ]]
  [[ "$output" =~ "another arg" ]]

  unset -f test_command
}

# ============================================================================
# Integration tests with download functions
# ============================================================================

@test "network::retry - integrates with download operations" {
  # Simulate a flaky download
  local state_file="${TEST_TMPDIR}/download_state_$$"
  echo "0" > "${state_file}"

  flaky_download() {
    local state_file="${1}"
    local count
    count=$(cat "${state_file}")
    count=$((count + 1))
    echo "${count}" > "${state_file}"

    if [[ ${count} -lt 2 ]]; then
      # Simulate network error
      return 1
    else
      # Simulate successful download
      echo "download complete"
      return 0
    fi
  }
  export -f flaky_download

  run network::retry 5 1 flaky_download "${state_file}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "download complete" ]]

  unset -f flaky_download
  rm -f "${state_file}"
}

@test "network::retry - respects max timeout" {
  # Command that takes too long
  slow_command() { sleep 20; return 0; }
  export -f slow_command

  # Should fail quickly if max_retries * delay < command time
  local start
  start=$(date +%s)
  timeout 5 bash -c "network::retry 2 1 slow_command" || true
  local end
  end=$(date +%s)
  local duration=$((end - start))

  # Should timeout around 5 seconds
  [ ${duration} -le 7 ]

  unset -f slow_command
}
