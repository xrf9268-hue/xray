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

  chmod +x "${TEST_TMPDIR}/bin/"{sudo,getent,groupadd,useradd}
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
