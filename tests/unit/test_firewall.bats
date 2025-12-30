#!/usr/bin/env bats
# Test modules/fw/*.sh - Firewall management

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/modules/fw/ufw.sh"
  source "${PROJECT_ROOT}/modules/fw/firewalld.sh"
  source "${PROJECT_ROOT}/modules/fw/fw.sh"
}

teardown() {
  cleanup_test_env
}

# === fw_ufw::is_available Tests ===

@test "fw_ufw::is_available returns true when ufw exists" {
  # Create a mock ufw command
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  PATH="${TEST_TMPDIR}/bin:${PATH}" run fw_ufw::is_available
  [ "${status}" -eq 0 ]
}

@test "fw_ufw::is_available returns false when ufw not found" {
  PATH="/nonexistent" run fw_ufw::is_available
  [ "${status}" -ne 0 ]
}

# === fw_firewalld::is_available Tests ===

@test "fw_firewalld::is_available returns true when firewall-cmd exists" {
  # Create a mock firewall-cmd command
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  PATH="${TEST_TMPDIR}/bin:${PATH}" run fw_firewalld::is_available
  [ "${status}" -eq 0 ]
}

@test "fw_firewalld::is_available returns false when firewall-cmd not found" {
  PATH="/nonexistent" run fw_firewalld::is_available
  [ "${status}" -ne 0 ]
}

# === fw::detect Tests ===

@test "fw::detect returns ufw when only ufw is available" {
  # Create mock ufw only
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  result="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  [ "${result}" = "ufw" ]
}

@test "fw::detect returns firewalld when only firewalld is available" {
  # Create mock firewall-cmd only
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  result="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  [ "${result}" = "firewalld" ]
}

@test "fw::detect returns none when no firewall available" {
  result="$(PATH="/nonexistent" fw::detect)"
  [ "${result}" = "none" ]
}

@test "fw::detect prefers ufw over firewalld when both available" {
  # Create both mocks
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  result="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  [ "${result}" = "ufw" ]
}

# === fw::open Tests ===

@test "fw::open succeeds without error when no firewall available" {
  PATH="/nonexistent" run fw::open 443
  [ "${status}" -eq 0 ]
}

@test "fw::open appends /tcp to port" {
  # Create a mock directory for capturing arguments
  mkdir -p "${TEST_TMPDIR}/bin"

  # Create mock sudo that captures the full command
  cat > "${TEST_TMPDIR}/bin/sudo" << EOF
#!/bin/bash
echo "\$@" >> "${TEST_TMPDIR}/captured_args.txt"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  # Create mock ufw (needed for detection)
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  rm -f "${TEST_TMPDIR}/captured_args.txt"
  (PATH="${TEST_TMPDIR}/bin" fw::open 443)
  [ -f "${TEST_TMPDIR}/captured_args.txt" ]
  grep -q "443/tcp" "${TEST_TMPDIR}/captured_args.txt"
}

# === fw::close Tests ===

@test "fw::close succeeds without error when no firewall available" {
  PATH="/nonexistent" run fw::close 443
  [ "${status}" -eq 0 ]
}

@test "fw::close appends /tcp to port" {
  # Create a mock directory for capturing arguments
  mkdir -p "${TEST_TMPDIR}/bin"

  # Create mock sudo that captures the full command
  cat > "${TEST_TMPDIR}/bin/sudo" << EOF
#!/bin/bash
echo "\$@" >> "${TEST_TMPDIR}/captured_args.txt"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  # Create mock ufw (needed for detection)
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  rm -f "${TEST_TMPDIR}/captured_args.txt"
  (PATH="${TEST_TMPDIR}/bin" fw::close 443)
  [ -f "${TEST_TMPDIR}/captured_args.txt" ]
  grep -q "443/tcp" "${TEST_TMPDIR}/captured_args.txt"
}

# === Integration Tests ===

@test "fw module sources all submodules" {
  # Verify functions exist
  declare -f fw_ufw::is_available > /dev/null
  declare -f fw_firewalld::is_available > /dev/null
  declare -f fw::detect > /dev/null
  declare -f fw::open > /dev/null
  declare -f fw::close > /dev/null
}
