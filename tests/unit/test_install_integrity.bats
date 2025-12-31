#!/usr/bin/env bats
# Unit tests for install.sh integrity enforcement helpers

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# Helper to create a minimal git repo with a single commit
create_temp_repo() {
  local path="${1}"
  mkdir -p "${path}"
  pushd "${path}" >/dev/null || return
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  echo "test content" > file.txt
  git add file.txt
  git commit -m "initial commit" >/dev/null 2>&1
  popd >/dev/null || return
}

@test "install.sh - integrity check fails on commit mismatch" {
  local repo="${TEST_TMPDIR}/repo-mismatch"
  create_temp_repo "${repo}"

  local actual_commit
  actual_commit="$(git -C "${repo}" rev-parse HEAD)"
  local wrong_commit="0000000000000000000000000000000000000001"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${actual_commit}"'" "'"${wrong_commit}"'" "false"; exit $?'

  [ "$status" -eq 1 ]
  [[ "$output" =~ "commit hash mismatch" ]]
}

@test "install.sh - requires GPG verification when enforced" {
  local repo="${TEST_TMPDIR}/repo-gpg-required"
  create_temp_repo "${repo}"

  local commit
  commit="$(git -C "${repo}" rev-parse HEAD)"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${commit}"'" "'"${commit}"'" "true"; exit $?'

  [ "$status" -eq 1 ]
  [[ "$output" =~ "GPG verification" ]] || [[ "$output" =~ "gpg is not installed" ]]
}

@test "install.sh - passes when commits match and signatures optional" {
  local repo="${TEST_TMPDIR}/repo-match"
  create_temp_repo "${repo}"

  local commit
  commit="$(git -C "${repo}" rev-parse HEAD)"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${commit}"'" "'"${commit}"'" "false"; exit $?'

  [ "$status" -eq 0 ]
}
