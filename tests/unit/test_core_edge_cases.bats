#!/usr/bin/env bats
# Edge case tests for core functions (lib/core.sh)
# These tests cover less common scenarios and boundary conditions

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/core.sh"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# core::ensure_lock_writable edge cases
# =============================================================================

@test "core::ensure_lock_writable - returns 0 when file does not exist" {
  local lock_file="${TEST_TMPDIR}/nonexistent.lock"
  run core::ensure_lock_writable "${lock_file}"
  [ "$status" -eq 0 ]
}

@test "core::ensure_lock_writable - succeeds for writable file owned by current user" {
  local lock_file="${TEST_TMPDIR}/writable.lock"
  touch "${lock_file}"
  chmod 644 "${lock_file}"

  run core::ensure_lock_writable "${lock_file}"
  [ "$status" -eq 0 ]
}

@test "core::ensure_lock_writable - fixes permissions on file" {
  local lock_file="${TEST_TMPDIR}/perms.lock"
  touch "${lock_file}"
  chmod 600 "${lock_file}"

  run core::ensure_lock_writable "${lock_file}"
  [ "$status" -eq 0 ]

  # Check permissions are now 644
  local perms
  perms=$(stat -c "%a" "${lock_file}" 2>/dev/null || stat -f "%Lp" "${lock_file}")
  [[ "${perms}" == "644" ]]
}

@test "core::ensure_lock_writable - handles already correct permissions" {
  local lock_file="${TEST_TMPDIR}/correct.lock"
  touch "${lock_file}"
  chmod 644 "${lock_file}"

  run core::ensure_lock_writable "${lock_file}"
  [ "$status" -eq 0 ]

  local perms
  perms=$(stat -c "%a" "${lock_file}" 2>/dev/null || stat -f "%Lp" "${lock_file}")
  [[ "${perms}" == "644" ]]
}

# =============================================================================
# core::log_format edge cases
# =============================================================================

@test "core::log_format - handles empty message" {
  XRF_JSON=false
  run core::log_format info "" "{}"
  [ "$status" -eq 0 ]
  # Should still output timestamp and level
  [[ "$output" =~ ^\[[0-9T:Z-]+\] ]]
}

@test "core::log_format - handles empty context in text mode" {
  XRF_JSON=false
  run core::log_format info "test message" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"test message"* ]]
  # Should not have trailing context
}

@test "core::log_format - handles whitespace-only context" {
  XRF_JSON=false
  run core::log_format info "test message" "   "
  [ "$status" -eq 0 ]
  [[ "$output" == *"test message"* ]]
}

@test "core::log_format - handles {} empty object context" {
  XRF_JSON=true
  run core::log_format info "test" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ctx":{}'* ]]
}

@test "core::log_format - fatal level shows as FATAL in text mode" {
  XRF_JSON=false
  run core::log_format fatal "fatal error" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FATAL"* ]]
}

@test "core::log_format - critical level shows as CRITICAL in text mode" {
  XRF_JSON=false
  run core::log_format critical "critical error" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRITICAL"* ]]
}

@test "core::log_format - info level stays lowercase in text mode" {
  XRF_JSON=false
  run core::log_format info "info message" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"info"* ]]
  [[ "$output" != *"INFO"* ]]
}

@test "core::log_format - JSON output includes all required fields" {
  XRF_JSON=true
  run core::log_format warn "warning message" '{"key":"value"}'
  [ "$status" -eq 0 ]
  # Check all required fields
  [[ "$output" == *'"ts":'* ]]
  [[ "$output" == *'"level":"warn"'* ]]
  [[ "$output" == *'"msg":"warning message"'* ]]
  [[ "$output" == *'"ctx":{"key":"value"}'* ]]
}

@test "core::log_format - JSON preserves nested context" {
  XRF_JSON=true
  run core::log_format info "test" '{"outer":{"inner":"value"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ctx":{"outer":{"inner":"value"}}'* ]]
}

# =============================================================================
# core::log edge cases
# =============================================================================

@test "core::log - handles special characters in message" {
  XRF_JSON=false
  run core::log info 'message with "quotes" and $vars'
  [ "$status" -eq 0 ]
  [[ "$output" == *"message with"* ]]
}

@test "core::log - handles newlines in message (text mode)" {
  XRF_JSON=false
  run core::log info $'line1\nline2'
  [ "$status" -eq 0 ]
  # Output will be on multiple lines
}

@test "core::log - handles unicode characters" {
  XRF_JSON=false
  run core::log info "Unicode test: "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unicode test"* ]]
}

@test "core::log - debug suppressed by default" {
  XRF_DEBUG=false
  XRF_JSON=false
  run core::log debug "should not appear"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "core::log - debug shown when XRF_DEBUG=true" {
  XRF_DEBUG=true
  XRF_JSON=false
  run core::log debug "debug message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"debug message"* ]]
}

@test "core::log - multiple calls preserve output order" {
  XRF_JSON=false
  result=$(
    core::log info "first" 2>&1
    core::log info "second" 2>&1
    core::log info "third" 2>&1
  )
  # Check order
  [[ "$result" == *"first"*"second"*"third"* ]]
}

# =============================================================================
# core::retry edge cases
# =============================================================================

@test "core::retry - succeeds with default attempts when not specified" {
  run core::retry true
  [ "$status" -eq 0 ]
}

@test "core::retry - handles command with arguments" {
  run core::retry 3 test -z ""
  [ "$status" -eq 0 ]
}

@test "core::retry - handles commands that output data" {
  run core::retry 3 echo "test output"
  [ "$status" -eq 0 ]
  [[ "$output" == "test output" ]]
}

@test "core::retry - attempt 1 succeeds immediately (no delay)" {
  local start_time
  start_time=$(date +%s)
  run core::retry 3 true
  local end_time
  end_time=$(date +%s)
  [ "$status" -eq 0 ]
  # Should complete in less than 1 second
  local elapsed=$((end_time - start_time))
  [[ "$elapsed" -lt 2 ]]
}

@test "core::retry - max_attempts=1 means only one try" {
  local counter_file="${TEST_TMPDIR}/counter"
  echo "0" > "${counter_file}"

  fail_once() {
    local count
    count=$(cat "${counter_file}")
    count=$((count + 1))
    echo "${count}" > "${counter_file}"
    return 1
  }

  run core::retry 1 fail_once
  [ "$status" -eq 1 ]

  local final_count
  final_count=$(cat "${counter_file}")
  [[ "${final_count}" -eq 1 ]]
}

# =============================================================================
# core::with_flock edge cases
# =============================================================================

@test "core::with_flock - creates nested directories for lock file" {
  local lock_file="${TEST_TMPDIR}/deep/nested/dir/test.lock"

  run core::with_flock "${lock_file}" true
  [ "$status" -eq 0 ]
  [ -d "$(dirname "${lock_file}")" ]
}

@test "core::with_flock - command arguments are preserved" {
  local lock_file="${TEST_TMPDIR}/test.lock"
  local output_file="${TEST_TMPDIR}/output.txt"

  run core::with_flock "${lock_file}" bash -c "echo arg1 arg2 > ${output_file}"
  [ "$status" -eq 0 ]
  [[ "$(cat "${output_file}")" == "arg1 arg2" ]]
}

@test "core::with_flock - environment variables are accessible in command" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  export TEST_VAR="test_value"
  run core::with_flock "${lock_file}" bash -c 'echo "$TEST_VAR"'
  [ "$status" -eq 0 ]
  [[ "$output" == "test_value" ]]
}

@test "core::with_flock - exit code 2 when no command provided" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  run core::with_flock "${lock_file}"
  [ "$status" -eq 2 ]
}

@test "core::with_flock - releases lock after command completes" {
  local lock_file="${TEST_TMPDIR}/release.lock"

  # First command
  core::with_flock "${lock_file}" true
  local status1=$?

  # Second command should also succeed (lock released)
  core::with_flock "${lock_file}" true
  local status2=$?

  [[ "$status1" -eq 0 ]]
  [[ "$status2" -eq 0 ]]
}

@test "core::with_flock - handles command with complex quoting" {
  local lock_file="${TEST_TMPDIR}/test.lock"

  run core::with_flock "${lock_file}" bash -c 'echo "hello world"'
  [ "$status" -eq 0 ]
  [[ "$output" == "hello world" ]]
}

# =============================================================================
# core::ts edge cases
# =============================================================================

@test "core::ts - returns consistent format across calls" {
  local ts1 ts2
  ts1=$(core::ts)
  sleep 0.1
  ts2=$(core::ts)

  # Both should match ISO 8601 pattern
  [[ "$ts1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  [[ "$ts2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "core::ts - UTC timestamp (ends with Z)" {
  local ts
  ts=$(core::ts)
  [[ "$ts" == *"Z" ]]
}

@test "core::ts - no trailing newline in output" {
  local ts
  ts=$(core::ts)
  # Length should not change when stripping trailing newline
  local trimmed
  trimmed=$(echo -n "$ts")
  [[ "${#ts}" -eq "${#trimmed}" ]] || [[ "$ts" == "$trimmed"$'\n' ]]
}
