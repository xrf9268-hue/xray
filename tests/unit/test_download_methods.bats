#!/usr/bin/env bats
# Unit tests for download methods (lib/download.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source download module
  source "${PROJECT_ROOT}/lib/download.sh" 2>/dev/null || true

  # Create test fixtures
  export TEST_REPO_DIR="${TEST_TMPDIR}/test-repo"
  export TEST_DOWNLOAD_DIR="${TEST_TMPDIR}/download"
  mkdir -p "${TEST_REPO_DIR}" "${TEST_DOWNLOAD_DIR}"
}

teardown() {
  cleanup_test_env
}

# Helper: Create a fake tarball for testing
create_fake_tarball() {
  local branch="${1}"
  local dest="${2}"

  # Create a fake repo structure
  local fake_repo="${TEST_TMPDIR}/fake-repo"
  mkdir -p "${fake_repo}/bin"
  echo "#!/bin/bash" > "${fake_repo}/bin/xrf"
  chmod +x "${fake_repo}/bin/xrf"
  echo "test content" > "${fake_repo}/README.md"

  # Create tarball
  cd "${TEST_TMPDIR}"
  tar -czf "${dest}" -C "${TEST_TMPDIR}" --transform "s|^fake-repo|xray-fusion-${branch}|" fake-repo
  cd - >/dev/null
}

# ============================================================================
# download::via_tarball tests
# ============================================================================

@test "download::via_tarball - validates required arguments" {
  # Missing all arguments
  run download::via_tarball
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required arguments" ]]

  # Missing some arguments
  run download::via_tarball "http://test.url"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required arguments" ]]

  run download::via_tarball "http://test.url" "/tmp"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required arguments" ]]
}

@test "download::via_tarball - prefers curl over wget" {
  skip "Requires network mocking"

  # This test would require mocking curl/wget
  # In a real scenario, we'd use a test HTTP server
}

@test "download::via_tarball - fails when no download tool available" {
  # Mock command to simulate missing tools
  command() {
    case "${2:-}" in
      curl|wget) return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  export -f command

  run download::via_tarball "http://test.url" "${TEST_DOWNLOAD_DIR}" "main"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "all download attempts failed" ]] || [[ "$output" =~ "download failed" ]]

  unset -f command
}

@test "download::via_tarball - extracts tarball correctly" {
  # Create a fake tarball
  local tarball="${TEST_DOWNLOAD_DIR}/archive.tar.gz"
  create_fake_tarball "main" "${tarball}"

  # Mock curl to use our fake tarball
  curl() {
    if [[ "$*" == *"-o"* ]]; then
      # Find output file (after -o flag)
      local output_file=""
      local next_is_output=false
      for arg in "$@"; do
        if [[ "${next_is_output}" == "true" ]]; then
          output_file="${arg}"
          break
        fi
        if [[ "${arg}" == "-o" ]]; then
          next_is_output=true
        fi
      done
      # Copy our fake tarball to the output location
      cp "${tarball}" "${output_file}"
      return 0
    fi
    return 1
  }
  export -f curl

  # Run the function
  run download::via_tarball "http://test.url/archive.tar.gz" "${TEST_DOWNLOAD_DIR}" "main"
  [ "$status" -eq 0 ]

  # Verify extraction
  [ -d "${TEST_DOWNLOAD_DIR}/xray-fusion" ]
  [ -f "${TEST_DOWNLOAD_DIR}/xray-fusion/bin/xrf" ]
  [ -x "${TEST_DOWNLOAD_DIR}/xray-fusion/bin/xrf" ]
  [ -f "${TEST_DOWNLOAD_DIR}/xray-fusion/README.md" ]

  # Verify tarball cleanup
  [ ! -f "${TEST_DOWNLOAD_DIR}/archive.tar.gz" ]

  unset -f curl
}

@test "download::via_tarball - cleans up on extraction failure" {
  # Create an invalid tarball
  echo "not a valid tarball" > "${TEST_DOWNLOAD_DIR}/archive.tar.gz"

  # Mock curl to use our invalid tarball
  curl() {
    if [[ "$*" == *"-o"* ]]; then
      local output_file=""
      local next_is_output=false
      for arg in "$@"; do
        if [[ "${next_is_output}" == "true" ]]; then
          output_file="${arg}"
          break
        fi
        if [[ "${arg}" == "-o" ]]; then
          next_is_output=true
        fi
      done
      cp "${TEST_DOWNLOAD_DIR}/archive.tar.gz" "${output_file}"
      return 0
    fi
    return 1
  }
  export -f curl

  run download::via_tarball "http://test.url/archive.tar.gz" "${TEST_DOWNLOAD_DIR}" "main"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "failed to extract" ]]

  # Verify cleanup
  [ ! -f "${TEST_DOWNLOAD_DIR}/archive.tar.gz" ]

  unset -f curl
}

@test "download::via_tarball - handles curl failure gracefully" {
  # Mock curl to always fail
  curl() {
    return 1
  }
  export -f curl

  run download::via_tarball "http://test.url/archive.tar.gz" "${TEST_DOWNLOAD_DIR}" "main"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "curl download failed" ]] || [[ "$output" =~ "no download tool" ]]

  unset -f curl
}

@test "download::via_tarball - falls back to wget when curl unavailable" {
  skip "Complex function mocking unreliable; covered by install.sh integration tests"

  # Note: This test attempts to mock command availability which interacts poorly
  # with Bash's command resolution. The fallback logic is tested in install.sh
  # where it's inline and actually executed in real scenarios.
}

# ============================================================================
# download::with_fallback tests
# ============================================================================

@test "download::with_fallback - validates required arguments" {
  run download::with_fallback
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required arguments" ]]

  run download::with_fallback "http://test.url"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required arguments" ]]
}

@test "download::with_fallback - succeeds with git clone" {
  # Create a real git repo
  cd "${TEST_REPO_DIR}"
  command git init >/dev/null 2>&1
  command git config user.email "test@example.com"
  command git config user.name "Test"
  command git config commit.gpgsign false
  mkdir -p bin
  echo "#!/bin/bash" > bin/xrf
  chmod +x bin/xrf
  command git add .
  command git commit -m "initial" >/dev/null 2>&1
  cd - >/dev/null

  # Test with real git clone
  run download::with_fallback "file://${TEST_REPO_DIR}" "${TEST_DOWNLOAD_DIR}" "master"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "git clone successful" ]] || [[ "$output" == "" ]]

  # Verify .git exists (git clone preserves history)
  [ -d "${TEST_DOWNLOAD_DIR}/xray-fusion/.git" ]
  [ -f "${TEST_DOWNLOAD_DIR}/xray-fusion/bin/xrf" ]
}

@test "download::with_fallback - falls back to tarball when git fails" {
  skip "Complex function mocking unreliable; covered by install.sh integration tests"

  # Note: Git → tarball fallback is tested in real install.sh execution.
}

@test "download::with_fallback - fails when all methods fail" {
  # Mock all tools to fail
  git() {
    [[ "$1" == "clone" ]] && return 1
    builtin command git "$@"
  }
  curl() { return 1; }
  wget() { return 1; }
  export -f git curl wget

  run download::with_fallback "https://github.com/test/repo.git" "${TEST_DOWNLOAD_DIR}" "main"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "all download methods failed" ]] || [[ "$output" =~ "failed" ]]

  unset -f git curl wget
}

@test "download::with_fallback - skips git when not available" {
  skip "Complex function mocking unreliable; covered by install.sh integration tests"

  # Note: Skipping git when unavailable is tested in real install.sh execution.
}

# ============================================================================
# Integration tests
# ============================================================================

@test "download methods - complete fallback chain" {
  skip "Complex function mocking unreliable; covered by install.sh integration tests"

  # Note: Complete fallback chain (git → curl → wget) is tested in
  # real install.sh execution where it works reliably without mocking.
}
