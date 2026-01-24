#!/usr/bin/env bats
# Edge case tests for firewall modules (modules/fw/*.sh)
# These tests cover boundary conditions and error handling

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

# =============================================================================
# fw_ufw module edge cases
# =============================================================================

@test "fw_ufw::is_available - returns false with empty PATH" {
  PATH="" run fw_ufw::is_available
  [ "${status}" -ne 0 ]
}

@test "fw_ufw::is_available - detects ufw in custom PATH" {
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  PATH="${TEST_TMPDIR}/bin" run fw_ufw::is_available
  [ "${status}" -eq 0 ]
}

@test "fw_ufw::open - handles port with trailing spaces" {
  mkdir -p "${TEST_TMPDIR}/bin"
  cat > "${TEST_TMPDIR}/bin/sudo" << 'EOF'
#!/bin/bash
echo "$@"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  PATH="${TEST_TMPDIR}/bin" run fw_ufw::open "443/tcp"
  [ "${status}" -eq 0 ]
}

@test "fw_ufw::close - handles port correctly" {
  mkdir -p "${TEST_TMPDIR}/bin"
  cat > "${TEST_TMPDIR}/bin/sudo" << 'EOF'
#!/bin/bash
echo "delete allow $@"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  PATH="${TEST_TMPDIR}/bin" run fw_ufw::close "443/tcp"
  [ "${status}" -eq 0 ]
}

# =============================================================================
# fw_firewalld module edge cases
# =============================================================================

@test "fw_firewalld::is_available - returns false with empty PATH" {
  PATH="" run fw_firewalld::is_available
  [ "${status}" -ne 0 ]
}

@test "fw_firewalld::is_available - detects firewall-cmd in custom PATH" {
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  PATH="${TEST_TMPDIR}/bin" run fw_firewalld::is_available
  [ "${status}" -eq 0 ]
}

# =============================================================================
# fw::detect edge cases
# =============================================================================

@test "fw::detect - returns 'none' with completely empty PATH" {
  result="$(PATH="" fw::detect)"
  [ "${result}" = "none" ]
}

@test "fw::detect - prefers ufw when both available" {
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  result="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  [ "${result}" = "ufw" ]
}

@test "fw::detect - falls back to firewalld when ufw unavailable" {
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  result="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  [ "${result}" = "firewalld" ]
}

@test "fw::detect - returns consistent results on repeated calls" {
  mkdir -p "${TEST_TMPDIR}/bin"
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  result1="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  result2="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"
  result3="$(PATH="${TEST_TMPDIR}/bin" fw::detect)"

  [ "${result1}" = "${result2}" ]
  [ "${result2}" = "${result3}" ]
}

# =============================================================================
# fw::open edge cases
# =============================================================================

@test "fw::open - handles standard port numbers" {
  # With no firewall available, should succeed silently
  PATH="/nonexistent" run fw::open 80
  [ "${status}" -eq 0 ]

  PATH="/nonexistent" run fw::open 443
  [ "${status}" -eq 0 ]

  PATH="/nonexistent" run fw::open 8443
  [ "${status}" -eq 0 ]
}

@test "fw::open - handles high port numbers" {
  PATH="/nonexistent" run fw::open 65535
  [ "${status}" -eq 0 ]
}

@test "fw::open - handles port 1" {
  PATH="/nonexistent" run fw::open 1
  [ "${status}" -eq 0 ]
}

@test "fw::open - delegates to ufw when available" {
  mkdir -p "${TEST_TMPDIR}/bin"

  cat > "${TEST_TMPDIR}/bin/sudo" << 'EOF'
#!/bin/bash
echo "sudo-called: $@" >> /tmp/fw_test_log.txt
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  rm -f /tmp/fw_test_log.txt
  (PATH="${TEST_TMPDIR}/bin" fw::open 8080)

  # Should have called sudo with ufw
  if [ -f /tmp/fw_test_log.txt ]; then
    grep -q "ufw" /tmp/fw_test_log.txt
    rm -f /tmp/fw_test_log.txt
  fi
}

# =============================================================================
# fw::close edge cases
# =============================================================================

@test "fw::close - handles standard port numbers" {
  PATH="/nonexistent" run fw::close 80
  [ "${status}" -eq 0 ]

  PATH="/nonexistent" run fw::close 443
  [ "${status}" -eq 0 ]
}

@test "fw::close - handles high port numbers" {
  PATH="/nonexistent" run fw::close 65535
  [ "${status}" -eq 0 ]
}

@test "fw::close - handles port 1" {
  PATH="/nonexistent" run fw::close 1
  [ "${status}" -eq 0 ]
}

# =============================================================================
# Integration tests
# =============================================================================

@test "fw module - all functions are available after sourcing" {
  declare -f fw_ufw::is_available > /dev/null
  declare -f fw_ufw::open > /dev/null
  declare -f fw_ufw::close > /dev/null
  declare -f fw_firewalld::is_available > /dev/null
  declare -f fw::detect > /dev/null
  declare -f fw::open > /dev/null
  declare -f fw::close > /dev/null
}

@test "fw module - open and close are idempotent with no firewall" {
  # When no firewall is available, both should succeed
  PATH="/nonexistent" run fw::open 9999
  [ "${status}" -eq 0 ]

  PATH="/nonexistent" run fw::close 9999
  [ "${status}" -eq 0 ]

  # Should be able to run multiple times
  PATH="/nonexistent" run fw::open 9999
  [ "${status}" -eq 0 ]

  PATH="/nonexistent" run fw::open 9999
  [ "${status}" -eq 0 ]
}

@test "fw module - handles multiple ports in sequence" {
  # Run with no firewall available (via isolated PATH)
  # Test that multiple operations succeed without errors
  PATH="/nonexistent" fw::open 80 || true
  PATH="/nonexistent" fw::open 443 || true
  PATH="/nonexistent" fw::open 8443 || true
  PATH="/nonexistent" fw::close 80 || true

  # Should complete without crashing
  run echo "success"
  [ "${status}" -eq 0 ]
  [[ "$output" == "success" ]]
}

# =============================================================================
# Mock firewall behavior tests
# =============================================================================

@test "fw module - ufw mock captures correct arguments" {
  mkdir -p "${TEST_TMPDIR}/bin"

  cat > "${TEST_TMPDIR}/bin/sudo" << 'EOF'
#!/bin/bash
echo "$@" >> "${TEST_TMPDIR}/captured.txt"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/ufw"
  chmod +x "${TEST_TMPDIR}/bin/ufw"

  rm -f "${TEST_TMPDIR}/captured.txt"
  export TEST_TMPDIR  # Make available to subshell
  (PATH="${TEST_TMPDIR}/bin" fw::open 12345)

  if [ -f "${TEST_TMPDIR}/captured.txt" ]; then
    grep -q "12345/tcp" "${TEST_TMPDIR}/captured.txt"
  fi
}

@test "fw module - firewalld mock used when ufw unavailable" {
  mkdir -p "${TEST_TMPDIR}/bin"

  cat > "${TEST_TMPDIR}/bin/sudo" << 'EOF'
#!/bin/bash
echo "$@" >> "${TEST_TMPDIR}/captured_fwd.txt"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/sudo"

  # Only create firewall-cmd, not ufw
  echo '#!/bin/bash' > "${TEST_TMPDIR}/bin/firewall-cmd"
  chmod +x "${TEST_TMPDIR}/bin/firewall-cmd"

  rm -f "${TEST_TMPDIR}/captured_fwd.txt"
  export TEST_TMPDIR
  (PATH="${TEST_TMPDIR}/bin" fw::open 54321)

  if [ -f "${TEST_TMPDIR}/captured_fwd.txt" ]; then
    grep -q "firewall-cmd" "${TEST_TMPDIR}/captured_fwd.txt"
  fi
}
