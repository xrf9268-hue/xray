#!/usr/bin/env bats
# Unit tests for log viewing and export functions (lib/logs.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source log module
  source "${PROJECT_ROOT}/lib/logs.sh"
}

teardown() {
  cleanup_test_env
}

# Test helper: create mock journalctl
write_log_fixture() {
  local fixture_file="${TEST_TMPDIR}/journalctl.out"
  cat > "${fixture_file}" <<'EOF'
2023-01-01T12:00:00+0000 xray info: Starting service
2023-01-01T12:00:01+0000 xray warning: Configuration deprecated
2023-01-01T12:00:02+0000 xray error: Connection failed
2023-01-01T12:00:03+0000 xray info: Retrying connection
EOF
  printf '%s\n' "${fixture_file}"
}

mock_journalctl() {
  local fixture_file="${1:-}"
  local mode="${2:-success}"
  local fake_bin="${TEST_TMPDIR}/bin"
  local mock_script="${fake_bin}/journalctl"

  mkdir -p "${fake_bin}"
  export XRF_JOURNALCTL_ARGS_FILE="${TEST_TMPDIR}/journalctl.args"
  export XRF_JOURNALCTL_FIXTURE="${fixture_file}"
  export XRF_JOURNALCTL_MODE="${mode}"

  cat > "${mock_script}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${XRF_JOURNALCTL_ARGS_FILE}"

if [[ "${XRF_JOURNALCTL_MODE:-success}" == "fail" ]]; then
  printf 'mock journalctl failure\n' >&2
  exit 1
fi

if [[ -n "${XRF_JOURNALCTL_FIXTURE:-}" ]]; then
  cat "${XRF_JOURNALCTL_FIXTURE}"
fi
EOF
  chmod +x "${mock_script}"
  export PATH="${fake_bin}:${PATH}"
}

# logs::_format tests
@test "logs::_format - filters error level correctly" {
  input="info: test1
error: test2
warn: test3
error: test4"

  result=$(echo "$input" | LOG_NO_COLOR=true logs::_format "error" "true")
  [[ "$result" == *"error: test2"* ]]
  [[ "$result" == *"error: test4"* ]]
  [[ "$result" != *"info: test1"* ]]
  [[ "$result" != *"warn: test3"* ]]
}

@test "logs::_format - filters warn level correctly" {
  input="info: test1
warning: test2
error: test3
warn: test4"

  result=$(echo "$input" | LOG_NO_COLOR=true logs::_format "warn" "true")
  [[ "$result" == *"warning: test2"* ]]
  [[ "$result" == *"warn: test4"* ]]
  [[ "$result" != *"info: test1"* ]]
  [[ "$result" != *"error: test3"* ]]
}

@test "logs::_format - filters info level correctly" {
  input="info: test1
error: test2
Info: test3"

  result=$(echo "$input" | LOG_NO_COLOR=true logs::_format "info" "true")
  [[ "$result" == *"info: test1"* ]]
  [[ "$result" == *"Info: test3"* ]]
  [[ "$result" != *"error: test2"* ]]
}

@test "logs::_format - shows all levels when filter is 'all'" {
  input="info: test1
error: test2
warn: test3
debug: test4"

  result=$(echo "$input" | LOG_NO_COLOR=true logs::_format "all" "true")
  [[ "$result" == *"info: test1"* ]]
  [[ "$result" == *"error: test2"* ]]
  [[ "$result" == *"warn: test3"* ]]
  [[ "$result" == *"debug: test4"* ]]
}

@test "logs::_format - applies color codes when no_color=false" {
  input="error: test error"

  result=$(echo "$input" | logs::_format "all" "false")
  # Check for ANSI color codes (e.g., \033[0;31m for red)
  [[ "$result" == *$'\033'* ]]
}

@test "logs::_format - no color codes when no_color=true" {
  input="error: test error"

  result=$(echo "$input" | logs::_format "all" "true")
  # Should not contain ANSI escape sequences
  [[ "$result" != *$'\033'* ]]
}

# logs::stats tests
@test "logs::view - returns failure when journalctl fails" {
  mock_journalctl "$(write_log_fixture)" "fail"
  export LOG_NO_COLOR="true"

  run logs::view
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to retrieve logs"* ]]
}

@test "logs::view - filters journalctl output and passes arguments" {
  mock_journalctl "$(write_log_fixture)"
  export LOG_LEVEL="error"
  export LOG_SINCE="2 hours ago"
  export LOG_LINES="25"
  export LOG_NO_COLOR="true"

  run logs::view
  [ "$status" -eq 0 ]
  [ "$output" = "2023-01-01T12:00:02+0000 xray error: Connection failed" ]

  args="$(cat "${XRF_JOURNALCTL_ARGS_FILE}")"
  [[ "${args}" == *"-u xray.service"* ]]
  [[ "${args}" == *"-n 25"* ]]
  [[ "${args}" == *"--since 2 hours ago"* ]]
  [[ "${args}" == *"--output=short-iso --no-pager"* ]]
}

@test "logs::follow - returns failure when journalctl fails" {
  mock_journalctl "$(write_log_fixture)" "fail"
  export LOG_NO_COLOR="true"

  run logs::follow
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to follow logs"* ]]
}

@test "logs::follow - includes follow flag and formatted output" {
  mock_journalctl "$(write_log_fixture)"
  export LOG_LEVEL="warn"
  export LOG_NO_COLOR="true"

  run logs::follow
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Ctrl+C to stop]"* ]]
  [[ "$output" == *"2023-01-01T12:00:01+0000 xray warning: Configuration deprecated"* ]]
  [[ "$output" != *"Starting service"* ]]
  [[ "$output" != *"Connection failed"* ]]

  args="$(cat "${XRF_JOURNALCTL_ARGS_FILE}")"
  [[ "${args}" == *"-u xray.service -f"* ]]
}

@test "logs::stats - returns valid JSON" {
  mock_journalctl "$(write_log_fixture)"
  export LOG_SINCE="1 hour ago"

  run logs::stats
  [ "$status" -eq 0 ]

  # Validate JSON structure
  echo "$output" | jq empty
  echo "$output" | jq -e 'has("total_lines")'
  echo "$output" | jq -e 'has("errors")'
  echo "$output" | jq -e 'has("warnings")'
  echo "$output" | jq -e 'has("info")'
}

@test "logs::stats - counts levels correctly" {
  mock_journalctl "$(write_log_fixture)"
  export LOG_SINCE="2 hours ago"

  run logs::stats
  [ "$status" -eq 0 ]
  [ "$output" = '{"total_lines":4,"errors":1,"warnings":1,"info":2,"since":"2 hours ago"}' ]
}

@test "logs::stats - returns failure when journalctl fails" {
  mock_journalctl "$(write_log_fixture)" "fail"

  run logs::stats
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to retrieve logs for statistics"* ]]
}

# logs::export tests
@test "logs::export - requires output file parameter" {
  run logs::export ""
  [ "$status" -ne 0 ]
}

@test "logs::export - creates output file with filtered plain text" {
  local export_file="${TEST_TMPDIR}/exported-logs.txt"
  mock_journalctl "$(write_log_fixture)"
  export LOG_LEVEL="error"
  export LOG_SINCE="30 minutes ago"
  export LOG_LINES="10"

  run logs::export "${export_file}"
  [ "$status" -eq 0 ]
  [ -f "${export_file}" ]
  content="$(cat "${export_file}")"
  [ "${content}" = "2023-01-01T12:00:02+0000 xray error: Connection failed" ]
  [[ "${content}" != *$'\033'* ]]

  args="$(cat "${XRF_JOURNALCTL_ARGS_FILE}")"
  [[ "${args}" == *"-n 10"* ]]
  [[ "${args}" == *"--since 30 minutes ago"* ]]
}

@test "logs::export - returns failure when journalctl fails" {
  local export_file="${TEST_TMPDIR}/exported-logs.txt"
  mock_journalctl "$(write_log_fixture)" "fail"

  run logs::export "${export_file}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to export logs"* ]]
  [[ ! -s "${export_file}" ]]
}

# Environment variable tests
@test "LOG_LEVEL environment variable is respected" {
  input="info: test1
error: test2"

  export LOG_LEVEL="error"
  result=$(echo "$input" | LOG_NO_COLOR=true logs::_format "${LOG_LEVEL}" "true")

  [[ "$result" == *"error: test2"* ]]
  [[ "$result" != *"info: test1"* ]]
}

@test "LOG_NO_COLOR environment variable disables colors" {
  input="error: test"

  export LOG_NO_COLOR="true"
  result=$(echo "$input" | logs::_format "all" "${LOG_NO_COLOR}")

  # Should not contain color codes
  [[ "$result" != *$'\033'* ]]
}
