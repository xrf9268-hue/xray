#!/usr/bin/env bats
# Unit tests for download verification functions (lib/download.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source download module
  source "${PROJECT_ROOT}/lib/download.sh" 2> /dev/null || true
}

teardown() {
  cleanup_test_env
}

# ============================================================================
# download::verify_commit tests
# ============================================================================

@test "download::verify_commit - detects valid commit hash" {
  # Setup mock git repo
  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}"

  cd "${tmpdir}"
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false  # Disable GPG signing for tests
  echo "test" > file.txt
  git add file.txt
  git commit -m "test commit" > /dev/null 2>&1

  local commit
  commit="$(git rev-parse HEAD)"

  # Test
  run download::verify_commit "${tmpdir}" "${commit}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "commit hash verified" ]] || [[ "$output" == "" ]]
}

@test "download::verify_commit - rejects invalid commit hash" {
  # Setup mock git repo
  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}"

  cd "${tmpdir}"
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false  # Disable GPG signing for tests
  echo "test" > file.txt
  git add file.txt
  git commit -m "test commit" > /dev/null 2>&1

  # Test with wrong hash
  run download::verify_commit "${tmpdir}" "0000000000000000000000000000000000000000"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "commit hash mismatch" ]]
}

@test "download::verify_commit - handles missing git repo" {
  local tmpdir="${TEST_TMPDIR}/not-a-repo"
  mkdir -p "${tmpdir}"

  run download::verify_commit "${tmpdir}" "any-hash"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not a git repository" ]]
}

@test "download::verify_commit - validates required arguments" {
  # Missing both arguments
  run download::verify_commit
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required parameter" ]]

  # Missing second argument
  run download::verify_commit "/tmp/repo"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required parameter" ]]
}

@test "download::verify_commit - handles non-existent directory" {
  run download::verify_commit "/nonexistent/path" "abc123"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not a git repository" ]]
}

# ============================================================================
# download::verify_gpg_signature tests
# ============================================================================

@test "download::verify_gpg_signature - handles missing gpg gracefully" {
  # Mock command to simulate missing gpg
  command() {
    if [[ "${2}" == "gpg" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}/.git"

  run download::verify_gpg_signature "${tmpdir}"
  [ "$status" -eq 0 ]  # Graceful degradation
  [[ "$output" =~ "gpg not available" ]] || [[ "$output" =~ "skipping" ]]

  unset -f command
}

@test "download::verify_gpg_signature - handles missing git repo" {
  local tmpdir="${TEST_TMPDIR}/not-a-repo"
  mkdir -p "${tmpdir}"

  run download::verify_gpg_signature "${tmpdir}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not a git repository" ]]
}

@test "download::verify_gpg_signature - handles unsigned commits gracefully" {
  # Setup unsigned git repo
  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}"

  cd "${tmpdir}"
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false  # Disable GPG signing for tests
  echo "test" > file.txt
  git add file.txt
  git commit -m "unsigned commit" > /dev/null 2>&1

  # Should not fail on unsigned commits (optional verification)
  run download::verify_gpg_signature "${tmpdir}"
  [ "$status" -eq 0 ]  # Graceful handling
}

@test "download::verify_gpg_signature - validates required arguments" {
  run download::verify_gpg_signature
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required parameter" ]] || [[ "$output" =~ "not a git repository" ]]
}

# ============================================================================
# Integration tests
# ============================================================================

@test "download verification - complete workflow with valid commit" {
  # Setup complete git repo
  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}"

  cd "${tmpdir}"
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false  # Disable GPG signing for tests

  # Create some content
  mkdir -p bin
  echo "#!/bin/bash" > bin/xrf
  chmod +x bin/xrf

  git add .
  git commit -m "initial commit" > /dev/null 2>&1

  local commit
  commit="$(git rev-parse HEAD)"

  # Verify commit
  run download::verify_commit "${tmpdir}" "${commit}"
  [ "$status" -eq 0 ]

  # Verify GPG (should gracefully handle unsigned)
  run download::verify_gpg_signature "${tmpdir}"
  [ "$status" -eq 0 ]

  # Verify repo structure
  [ -f "${tmpdir}/bin/xrf" ]
  [ -x "${tmpdir}/bin/xrf" ]
}

@test "download verification - rejects tampered repository" {
  # Setup git repo
  local tmpdir="${TEST_TMPDIR}/repo"
  mkdir -p "${tmpdir}"

  cd "${tmpdir}"
  git init > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false  # Disable GPG signing for tests
  echo "original" > file.txt
  git add file.txt
  git commit -m "original commit" > /dev/null 2>&1

  local original_commit
  original_commit="$(git rev-parse HEAD)"

  # Make another commit (simulate tampering)
  echo "tampered" > file.txt
  git add file.txt
  git commit -m "tampered commit" > /dev/null 2>&1

  # Verification should fail with original commit hash
  run download::verify_commit "${tmpdir}" "${original_commit}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "commit hash mismatch" ]]
}
