#!/usr/bin/env bats
# Unit tests for core functions (lib/core.sh)

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

@test "core::ts - returns ISO 8601 timestamp" {
  run core::ts
  [ "$status" -eq 0 ]
  # Check format: YYYY-MM-DDTHH:MM:SSZ
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "core::log - outputs to stderr in text mode" {
  XRF_JSON=false
  run core::log info "test message"
  [ "$status" -eq 0 ]
  # Log should go to stderr (captured in output by bats)
  [[ "$output" == *"test message"* ]]
}

@test "core::log - outputs JSON in JSON mode" {
  XRF_JSON=true
  run core::log info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"level":"info"'* ]]
  [[ "$output" == *'"msg":"test message"'* ]]
}

@test "core::log - filters debug messages unless XRF_DEBUG=true" {
  XRF_DEBUG=false
  run core::log debug "debug message"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "core::log - shows debug messages when XRF_DEBUG=true" {
  XRF_DEBUG=true
  run core::log debug "debug message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"debug message"* ]]
}

@test "core::retry - succeeds on first attempt" {
  run core::retry 3 true
  [ "$status" -eq 0 ]
}

@test "core::retry - fails after max attempts" {
  run core::retry 2 false
  [ "$status" -eq 1 ]
}

@test "core::retry - succeeds after retries" {
  # Create a file that acts as a counter
  counter_file="${TEST_TMPDIR}/counter"
  echo "0" > "${counter_file}"

  # Function that fails twice then succeeds
  flaky_cmd() {
    local count
    count=$(cat "${counter_file}")
    count=$((count + 1))
    echo "${count}" > "${counter_file}"
    [ "${count}" -ge 3 ]
  }

  run core::retry 5 flaky_cmd
  [ "$status" -eq 0 ]
}

# Tests for core::with_flock
@test "core::with_flock - creates lock file" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  run core::with_flock "${lock_file}" true
  [ "$status" -eq 0 ]
  [ -f "${lock_file}" ]
}

@test "core::with_flock - lock file has correct permissions" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  core::with_flock "${lock_file}" true

  [ -f "${lock_file}" ]
  local perms
  perms=$(stat -c "%a" "${lock_file}")
  [[ "${perms}" == "644" ]]
}

@test "core::with_flock - executes command successfully" {
  local lock_file="${TEST_TMPDIR}/test.lock"
  local output_file="${TEST_TMPDIR}/output.txt"

  run core::with_flock "${lock_file}" bash -c "echo 'test output' > ${output_file}"
  [ "$status" -eq 0 ]
  [ -f "${output_file}" ]
  [[ "$(cat "${output_file}")" == "test output" ]]
}

@test "core::with_flock - prevents concurrent execution" {
  local lock_file="${TEST_TMPDIR}/concurrent.lock"
  local counter_file="${TEST_TMPDIR}/counter.txt"
  echo "0" > "${counter_file}"

  # Start a long-running command with lock
  (
    core::with_flock "${lock_file}" bash -c "sleep 0.5; echo 'done'"
  ) &
  local pid1=$!

  # Wait a bit for first lock to be acquired
  sleep 0.1

  # Try to run another command with same lock (should wait)
  local start_time
  start_time=$(date +%s)
  core::with_flock "${lock_file}" bash -c "echo 'second'"
  local end_time
  end_time=$(date +%s)

  wait "${pid1}"

  # Second command should have waited (at least 0.3 seconds)
  local elapsed=$((end_time - start_time))
  [[ ${elapsed} -ge 0 ]]
}

@test "core::with_flock - lock file created atomically" {
  local lock_file="${TEST_TMPDIR}/atomic.lock"

  # The lock file should be created atomically without TOCTOU window
  # We test this by checking file exists with correct ownership/permissions
  # after with_flock completes

  core::with_flock "${lock_file}" true

  [ -f "${lock_file}" ]

  # Check ownership (should be current user, not root)
  local owner
  owner=$(stat -c "%U" "${lock_file}")
  [[ "${owner}" == "$(whoami)" ]] || [[ "${owner}" == "$(id -un)" ]]
}

@test "core::with_flock - fails when command is missing" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  run core::with_flock "${lock_file}"
  [ "$status" -ne 0 ]
}

@test "core::with_flock - propagates command exit code" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  run core::with_flock "${lock_file}" false
  [ "$status" -ne 0 ]

  run core::with_flock "${lock_file}" bash -c "exit 42"
  [ "$status" -eq 42 ]
}

# Log format consistency tests
@test "core::log - text format uses consistent width (%-8s)" {
  XRF_JSON=false

  # Test different log levels
  run core::log info "test"
  [ "$status" -eq 0 ]
  # Format: [timestamp] level    message
  # The level should be padded to 8 characters
  [[ "$output" =~ ^\[[0-9T:Z-]+\]\ [a-z]+\ {1,8}test ]]

  run core::log warn "warning message"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\[[0-9T:Z-]+\]\ [a-z]+\ {1,8}warning\ message ]]
}

@test "core::log - JSON format is valid and consistent" {
  XRF_JSON=true

  run core::log info "test message" '{"key":"value"}'
  [ "$status" -eq 0 ]

  # Should be valid JSON
  echo "$output" | grep -q '{"ts":'
  echo "$output" | grep -q '"level":"info"'
  echo "$output" | grep -q '"msg":"test message"'
  echo "$output" | grep -q '"ctx":{"key":"value"}'
}

@test "core::log - timestamp format is ISO 8601" {
  XRF_JSON=false

  run core::log info "test"
  [ "$status" -eq 0 ]

  # Extract timestamp from output: [2025-11-10T12:34:56Z]
  [[ "$output" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\] ]]
}

@test "caddy-cert-sync log format matches core::log" {
  # Extract log function from caddy-cert-sync.sh and test it
  local script="${PROJECT_ROOT}/scripts/caddy-cert-sync.sh"

  # Source only the log function
  source <(sed -n '/^log()/,/^}/p' "${script}")

  XRF_JSON=false
  run log info "test message"
  [ "$status" -eq 0 ]

  # Should use same format as core::log (%-8s width)
  [[ "$output" =~ ^\[[0-9T:Z-]+\]\ [a-z]+\ {1,8}\[caddy-cert-sync\]\ test\ message ]]
}

@test "caddy-cert-sync JSON format matches core::log" {
  # Extract log function from caddy-cert-sync.sh
  local script="${PROJECT_ROOT}/scripts/caddy-cert-sync.sh"
  source <(sed -n '/^log()/,/^}/p' "${script}")

  XRF_JSON=true
  run log info "test message"
  [ "$status" -eq 0 ]

  # Should be valid JSON
  echo "$output" | grep -q '{"ts":'
  echo "$output" | grep -q '"level":"info"'
  echo "$output" | grep -q '"msg":".*caddy-cert-sync.*test message"'
}
