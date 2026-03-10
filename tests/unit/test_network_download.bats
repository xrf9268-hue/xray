#!/usr/bin/env bats
# Unit tests for lib/network.sh - network::download_with_retry

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/network.sh"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# network::download_with_retry argument validation
# =============================================================================

@test "network::download_with_retry - fails with no arguments" {
  run network::download_with_retry
  [ "$status" -eq 1 ]
}

@test "network::download_with_retry - fails with empty url" {
  run network::download_with_retry "" "/tmp/output"
  [ "$status" -eq 1 ]
}

@test "network::download_with_retry - fails with empty output" {
  run network::download_with_retry "https://example.com" ""
  [ "$status" -eq 1 ]
}

@test "network::download_with_retry - fails with only url" {
  run network::download_with_retry "https://example.com"
  [ "$status" -eq 1 ]
}

# =============================================================================
# network::download_with_retry with mock download
# =============================================================================

@test "network::download_with_retry - succeeds with valid download" {
  # Create a mock curl that writes expected content
  local mock_bin="${TEST_TMPDIR}/mock_bin"
  mkdir -p "${mock_bin}"
  cat > "${mock_bin}/curl" << 'SCRIPT'
#!/usr/bin/env bash
# Find -o flag and write to that file
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) echo "downloaded" > "$2"; exit 0 ;;
    *) shift ;;
  esac
done
exit 1
SCRIPT
  chmod +x "${mock_bin}/curl"

  local output_file="${TEST_TMPDIR}/downloaded_file"
  PATH="${mock_bin}:${PATH}" run network::download_with_retry "https://example.com/file" "${output_file}" 1 1
  [ "$status" -eq 0 ]
}

@test "network::download_with_retry - uses default retries (3) and delay (2)" {
  # Count how many times curl is called to verify default max_retries=3
  local call_count_file="${TEST_TMPDIR}/default_call_count"
  echo "0" > "${call_count_file}"

  local mock_bin="${TEST_TMPDIR}/mock_bin"
  mkdir -p "${mock_bin}"
  cat > "${mock_bin}/curl" << SCRIPT
#!/usr/bin/env bash
count=\$(cat "${call_count_file}")
count=\$((count + 1))
echo "\${count}" > "${call_count_file}"
exit 1
SCRIPT
  cat > "${mock_bin}/wget" << 'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "${mock_bin}/curl" "${mock_bin}/wget"

  # Override sleep to avoid actual delays in tests
  sleep() { :; }
  export -f sleep

  local output_file="${TEST_TMPDIR}/downloaded_file"
  # Call WITHOUT explicit retries/delay to exercise defaults (3 retries, 2s delay)
  PATH="${mock_bin}:${PATH}" run network::download_with_retry "https://example.com/file" "${output_file}"
  [ "$status" -eq 1 ]

  # Verify default max_retries=3 was used
  local count
  count="$(cat "${call_count_file}")"
  [ "${count}" -eq 3 ]
}

@test "network::download_with_retry - falls back to wget when curl missing" {
  local mock_bin="${TEST_TMPDIR}/mock_bin"
  mkdir -p "${mock_bin}"
  # No curl, only wget
  cat > "${mock_bin}/wget" << 'SCRIPT'
#!/usr/bin/env bash
# Find -O flag and write to that file
while [[ $# -gt 0 ]]; do
  case "$1" in
    -O) echo "wget-download" > "$2"; exit 0 ;;
    *) shift ;;
  esac
done
exit 1
SCRIPT
  chmod +x "${mock_bin}/wget"
  # Add essential commands
  for cmd in bash echo cat head tr; do
    ln -sf "$(which "${cmd}")" "${mock_bin}/${cmd}" 2> /dev/null || true
  done

  local output_file="${TEST_TMPDIR}/downloaded_file"
  PATH="${mock_bin}" run network::download_with_retry "https://example.com/file" "${output_file}" 1 1
  [ "$status" -eq 0 ]
}

# =============================================================================
# network::download_with_retry custom retry settings
# =============================================================================

@test "network::download_with_retry - respects custom max_retries" {
  local call_count_file="${TEST_TMPDIR}/call_count"
  echo "0" > "${call_count_file}"

  local mock_bin="${TEST_TMPDIR}/mock_bin"
  mkdir -p "${mock_bin}"
  cat > "${mock_bin}/curl" << SCRIPT
#!/usr/bin/env bash
count=\$(cat "${call_count_file}")
count=\$((count + 1))
echo "\${count}" > "${call_count_file}"
exit 1
SCRIPT
  cat > "${mock_bin}/wget" << 'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "${mock_bin}/curl" "${mock_bin}/wget"

  local output_file="${TEST_TMPDIR}/downloaded_file"
  PATH="${mock_bin}:${PATH}" run network::download_with_retry "https://example.com/file" "${output_file}" 2 1
  [ "$status" -eq 1 ]

  local count
  count="$(cat "${call_count_file}")"
  [ "${count}" -eq 2 ]
}

@test "network::download_with_retry - fails when no download tool available" {
  local mock_bin="${TEST_TMPDIR}/mock_bin"
  mkdir -p "${mock_bin}"
  # Add essential commands but no curl/wget
  for cmd in bash echo cat head tr; do
    ln -sf "$(which "${cmd}")" "${mock_bin}/${cmd}" 2> /dev/null || true
  done

  local output_file="${TEST_TMPDIR}/downloaded_file"
  PATH="${mock_bin}" run network::download_with_retry "https://example.com/file" "${output_file}" 1 1
  [ "$status" -eq 1 ]
}
