#!/usr/bin/env bats
# shellcheck disable=SC2154  # Variables defined in test_helper.bash

load ../test_helper

setup() {
  setup_test_env
  create_user_mocks
  source "${PROJECT_ROOT}/modules/user/user.sh"
}

teardown() {
  cleanup_test_env
}

create_user_mocks() {
  mkdir -p "${TEST_TMPDIR}/bin"

  cat > "${TEST_TMPDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
"$@"
EOF

  cat > "${TEST_TMPDIR}/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
  echo "${MOCK_ID_U:-1000}"
  exit 0
fi
/usr/bin/id "$@"
EOF

  cat > "${TEST_TMPDIR}/bin/getent" <<'EOF'
#!/usr/bin/env bash
record="${TEST_TMPDIR}/${1}_${2}"
if [[ -f "${record}" ]]; then
  cat "${record}"
  exit 0
fi
exit 2
EOF

  cat > "${TEST_TMPDIR}/bin/groupadd" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${TEST_TMPDIR}/groupadd_calls"
if [[ "${MOCK_GROUPADD_FAIL:-0}" == "1" ]]; then
  exit 1
fi
group="${@: -1}"
gid="${MOCK_GROUP_GID:-998}"
printf "%s:x:%s:\n" "${group}" "${gid}" > "${TEST_TMPDIR}/group_${group}"
EOF

  cat > "${TEST_TMPDIR}/bin/useradd" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${TEST_TMPDIR}/useradd_calls"
if [[ "${MOCK_USERADD_FAIL:-0}" == "1" ]]; then
  exit 1
fi

group=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "--gid" ]]; then
    group="${arg}"
  fi
  prev="${arg}"
done

user="${@: -1}"
gid="${MOCK_GROUP_GID:-998}"
if [[ -n "${group}" && -f "${TEST_TMPDIR}/group_${group}" ]]; then
  IFS=':' read -r _ _ gid _ < "${TEST_TMPDIR}/group_${group}"
fi

printf "%s:x:1000:%s::/var/lib/%s:/usr/sbin/nologin\n" "${user}" "${gid}" "${user}" > "${TEST_TMPDIR}/passwd_${user}"
EOF

  chmod +x "${TEST_TMPDIR}/bin/"{sudo,id,getent,groupadd,useradd}
}

mock_path() {
  echo "${TEST_TMPDIR}/bin:${PATH}"
}

@test "creates system user and group when missing" {
  rm -f "${TEST_TMPDIR}/group_demo" "${TEST_TMPDIR}/passwd_demo"
  PATH="$(mock_path)" run user::ensure_system_user demo demo
  [ "${status}" -eq 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_demo"
  assert_file_exists "${TEST_TMPDIR}/passwd_demo"
  assert_file_exists "${TEST_TMPDIR}/useradd_calls"
  assert_file_exists "${TEST_TMPDIR}/groupadd_calls"
}

@test "fails when group creation fails" {
  PATH="$(mock_path)" MOCK_GROUPADD_FAIL=1 run user::ensure_system_user demo demo
  [ "${status}" -ne 0 ]
  [ ! -f "${TEST_TMPDIR}/group_demo" ]
  [ ! -f "${TEST_TMPDIR}/passwd_demo" ]
}

@test "fails when user creation fails" {
  PATH="$(mock_path)" MOCK_USERADD_FAIL=1 run user::ensure_system_user demo demo
  [ "${status}" -ne 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_demo"
  [ ! -f "${TEST_TMPDIR}/passwd_demo" ]
}

@test "fails when existing user has different primary group" {
  printf "demo:x:2000:\n" > "${TEST_TMPDIR}/group_demo"
  printf "demo:x:1000:999::/home/demo:/bin/bash\n" > "${TEST_TMPDIR}/passwd_demo"

  PATH="$(mock_path)" run user::ensure_system_user demo demo
  [ "${status}" -ne 0 ]
  [ ! -f "${TEST_TMPDIR}/useradd_calls" ]
}

@test "succeeds when user already matches expected group" {
  printf "demo:x:2000:\n" > "${TEST_TMPDIR}/group_demo"
  printf "demo:x:1000:2000::/home/demo:/bin/bash\n" > "${TEST_TMPDIR}/passwd_demo"

  PATH="$(mock_path)" run user::ensure_system_user demo demo
  [ "${status}" -eq 0 ]
  [ ! -f "${TEST_TMPDIR}/useradd_calls" ]
}

# =============================================================================
# Additional edge case tests
# =============================================================================

@test "defaults to xray user and group when no arguments" {
  rm -f "${TEST_TMPDIR}/group_xray" "${TEST_TMPDIR}/passwd_xray"

  PATH="$(mock_path)" run user::ensure_system_user
  [ "${status}" -eq 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_xray"
  assert_file_exists "${TEST_TMPDIR}/passwd_xray"
}

@test "creates user when group already exists" {
  # Pre-create the group
  printf "mygroup:x:1500:\n" > "${TEST_TMPDIR}/group_mygroup"
  rm -f "${TEST_TMPDIR}/passwd_myuser"

  PATH="$(mock_path)" run user::ensure_system_user myuser mygroup
  [ "${status}" -eq 0 ]
  # Group should not be recreated (no groupadd call)
  [ ! -f "${TEST_TMPDIR}/groupadd_calls" ]
  # User should be created
  assert_file_exists "${TEST_TMPDIR}/passwd_myuser"
}

@test "creates group when group does not exist but user creation succeeds" {
  rm -f "${TEST_TMPDIR}/group_newgroup" "${TEST_TMPDIR}/passwd_newuser"

  PATH="$(mock_path)" run user::ensure_system_user newuser newgroup
  [ "${status}" -eq 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_newgroup"
  assert_file_exists "${TEST_TMPDIR}/passwd_newuser"
  # Both should have been called
  assert_file_exists "${TEST_TMPDIR}/groupadd_calls"
  assert_file_exists "${TEST_TMPDIR}/useradd_calls"
}

@test "passes correct flags to useradd" {
  rm -f "${TEST_TMPDIR}/group_testuser" "${TEST_TMPDIR}/passwd_testuser"

  PATH="$(mock_path)" run user::ensure_system_user testuser testgroup
  [ "${status}" -eq 0 ]

  # Check useradd was called with expected flags
  local useradd_args
  useradd_args="$(cat "${TEST_TMPDIR}/useradd_calls")"
  [[ "${useradd_args}" == *"--system"* ]]
  [[ "${useradd_args}" == *"--gid testgroup"* ]]
  [[ "${useradd_args}" == *"--home-dir /var/lib/testuser"* ]]
  [[ "${useradd_args}" == *"--no-create-home"* ]]
  [[ "${useradd_args}" == *"--shell /usr/sbin/nologin"* ]]
}

@test "passes --system flag to groupadd" {
  rm -f "${TEST_TMPDIR}/group_sysgroup" "${TEST_TMPDIR}/passwd_sysuser"

  PATH="$(mock_path)" run user::ensure_system_user sysuser sysgroup
  [ "${status}" -eq 0 ]

  local groupadd_args
  groupadd_args="$(cat "${TEST_TMPDIR}/groupadd_calls")"
  [[ "${groupadd_args}" == *"--system"* ]]
}

@test "handles user with empty primary group ID gracefully" {
  # Create a malformed group entry with empty GID
  printf "badgroup:x::\n" > "${TEST_TMPDIR}/group_badgroup"
  rm -f "${TEST_TMPDIR}/passwd_baduser"

  PATH="$(mock_path)" run user::ensure_system_user baduser badgroup
  # Should fail due to empty GID
  [ "${status}" -ne 0 ]
}

@test "does not recreate existing user with correct group" {
  # Pre-create both user and group with matching GID
  printf "existing:x:500:\n" > "${TEST_TMPDIR}/group_existing"
  printf "existing:x:1000:500::/var/lib/existing:/usr/sbin/nologin\n" > "${TEST_TMPDIR}/passwd_existing"

  PATH="$(mock_path)" run user::ensure_system_user existing existing
  [ "${status}" -eq 0 ]
  # Neither groupadd nor useradd should be called
  [ ! -f "${TEST_TMPDIR}/groupadd_calls" ]
  [ ! -f "${TEST_TMPDIR}/useradd_calls" ]
}

@test "logs debug message when group already exists" {
  printf "debuggroup:x:999:\n" > "${TEST_TMPDIR}/group_debuggroup"
  printf "debuguser:x:1000:999::/var/lib/debuguser:/usr/sbin/nologin\n" > "${TEST_TMPDIR}/passwd_debuguser"

  XRF_DEBUG=true PATH="$(mock_path)" run user::ensure_system_user debuguser debuggroup
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"system group already exists"* ]] || [[ "${output}" == *"system user already exists"* ]]
}

@test "logs info when creating new group" {
  rm -f "${TEST_TMPDIR}/group_newgroup" "${TEST_TMPDIR}/passwd_newuser"

  PATH="$(mock_path)" run user::ensure_system_user newuser newgroup
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"creating system group"* ]]
}

@test "logs info when creating new user" {
  rm -f "${TEST_TMPDIR}/group_loguser" "${TEST_TMPDIR}/passwd_loguser"

  PATH="$(mock_path)" run user::ensure_system_user loguser loguser
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"creating system user"* ]]
}

@test "handles different user and group names" {
  rm -f "${TEST_TMPDIR}/group_diffgroup" "${TEST_TMPDIR}/passwd_diffuser"

  PATH="$(mock_path)" run user::ensure_system_user diffuser diffgroup
  [ "${status}" -eq 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_diffgroup"
  assert_file_exists "${TEST_TMPDIR}/passwd_diffuser"
}

@test "fails when user verification fails after creation" {
  # Create a mock useradd that succeeds but doesn't create passwd entry
  cat > "${TEST_TMPDIR}/bin/useradd" <<'EOF'
#!/usr/bin/env bash
# Simulate successful useradd that somehow doesn't create user
echo "$@" >> "${TEST_TMPDIR}/useradd_calls"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/useradd"

  rm -f "${TEST_TMPDIR}/group_verifyuser" "${TEST_TMPDIR}/passwd_verifyuser"

  PATH="$(mock_path)" run user::ensure_system_user verifyuser verifyuser
  # Should fail because user doesn't exist after creation
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"system user missing after creation"* ]]
}

@test "fails when group verification fails after creation" {
  # Create a mock groupadd that succeeds but doesn't create group entry
  cat > "${TEST_TMPDIR}/bin/groupadd" <<'EOF'
#!/usr/bin/env bash
# Simulate successful groupadd that somehow doesn't create group
echo "$@" >> "${TEST_TMPDIR}/groupadd_calls"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/groupadd"

  rm -f "${TEST_TMPDIR}/group_verifyfail" "${TEST_TMPDIR}/passwd_verifyfail"

  PATH="$(mock_path)" run user::ensure_system_user verifyfail verifyfail
  # Should fail because group doesn't exist after creation
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"system group missing after creation"* ]]
}

@test "uses sudo for group creation" {
  rm -f "${TEST_TMPDIR}/group_sudotest" "${TEST_TMPDIR}/passwd_sudotest"

  # Track sudo calls
  cat > "${TEST_TMPDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo: $@" >> "${TEST_TMPDIR}/sudo_calls"
"$@"
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  PATH="$(mock_path)" run user::ensure_system_user sudotest sudotest
  [ "${status}" -eq 0 ]
  # Verify sudo was used for groupadd
  grep -q "sudo: groupadd" "${TEST_TMPDIR}/sudo_calls"
}

@test "uses sudo for user creation" {
  rm -f "${TEST_TMPDIR}/group_sudouser" "${TEST_TMPDIR}/passwd_sudouser"

  # Track sudo calls
  cat > "${TEST_TMPDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo: $@" >> "${TEST_TMPDIR}/sudo_calls"
"$@"
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  PATH="$(mock_path)" run user::ensure_system_user sudouser sudouser
  [ "${status}" -eq 0 ]
  # Verify sudo was used for useradd
  grep -q "sudo: useradd" "${TEST_TMPDIR}/sudo_calls"
}

@test "runs without sudo when effective user is root" {
  rm -f "${TEST_TMPDIR}/group_nosudo" "${TEST_TMPDIR}/passwd_nosudo" "${TEST_TMPDIR}/sudo_calls"

  # If sudo is called in root mode this test must fail.
  cat > "${TEST_TMPDIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo: $@" >> "${TEST_TMPDIR}/sudo_calls"
exit 99
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  PATH="$(mock_path)" MOCK_ID_U=0 run user::ensure_system_user nosudo nosudo
  [ "${status}" -eq 0 ]
  assert_file_exists "${TEST_TMPDIR}/group_nosudo"
  assert_file_exists "${TEST_TMPDIR}/passwd_nosudo"
  [ ! -f "${TEST_TMPDIR}/sudo_calls" ]
}
