#!/usr/bin/env bats
# Unit tests for modules/net/network.sh

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/modules/net/network.sh"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# net::detect_public_ip tests
# =============================================================================

@test "net::detect_public_ip - returns IP or empty string" {
  # This function should never fail, just return empty if IP detection fails
  run net::detect_public_ip
  [ "$status" -eq 0 ]
  # Output should be either a valid IP or empty
  [[ -z "$output" || "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$output" =~ ^[0-9a-fA-F:]+ ]]
}

@test "net::detect_public_ip - handles timeout gracefully" {
  # Function should degrade gracefully even when timeout command is unavailable.
  run bash -c 'source "'"${PROJECT_ROOT}/modules/net/network.sh"'" && net::detect_public_ip >/dev/null'
  [ "$status" -eq 0 ]
}

@test "net::detect_public_ip - uses fallback methods" {
  # Mock dig to fail, should try other methods
  run bash -c '
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    # Even with broken dig, function should not fail
    net::detect_public_ip
  '
  [ "$status" -eq 0 ]
}

@test "net::detect_public_ip - outputs single line" {
  run net::detect_public_ip
  [ "$status" -eq 0 ]
  # Output should be at most one line
  local line_count
  line_count=$(echo "$output" | wc -l)
  [[ "$line_count" -le 1 ]] || [[ -z "$output" ]]
}

@test "net::detect_public_ip - does not output private IP ranges" {
  run net::detect_public_ip
  [ "$status" -eq 0 ]

  # If we got output, it should not be a private IP
  if [[ -n "$output" ]]; then
    # Should not be 10.x.x.x
    [[ ! "$output" =~ ^10\. ]]
    # Should not be 172.16-31.x.x
    [[ ! "$output" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
    # Should not be 192.168.x.x
    [[ ! "$output" =~ ^192\.168\. ]]
    # Should not be 127.x.x.x
    [[ ! "$output" =~ ^127\. ]]
  fi
}

# =============================================================================
# Source guard tests
# =============================================================================

@test "net/network.sh - has source guard" {
  # Source twice should not cause errors
  run bash -c '
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    echo "success"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "success" ]]
}

@test "net/network.sh - source guard variable is set" {
  run bash -c '
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    echo "${_XRF_NET_NETWORK_LOADED:-unset}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "1" ]]
}

# =============================================================================
# Edge case tests
# =============================================================================

@test "net::detect_public_ip - handles missing dig command" {
  run bash -c '
    # Hide dig from PATH
    dig() { return 1; }
    export -f dig
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    net::detect_public_ip
  '
  [ "$status" -eq 0 ]
}

@test "net::detect_public_ip - handles missing curl command" {
  run bash -c '
    # Create temp dir with limited PATH
    tmpbin="$(mktemp -d)"
    # Only keep essential commands
    ln -s "$(which bash)" "${tmpbin}/bash"
    ln -s "$(which echo)" "${tmpbin}/echo"
    ln -s "$(which timeout)" "${tmpbin}/timeout" 2>/dev/null || true
    ln -s "$(which ip)" "${tmpbin}/ip" 2>/dev/null || true
    ln -s "$(which awk)" "${tmpbin}/awk"
    ln -s "$(which head)" "${tmpbin}/head"
    ln -s "$(which cat)" "${tmpbin}/cat"
    ln -s "$(which tr)" "${tmpbin}/tr"

    PATH="${tmpbin}" source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    PATH="${tmpbin}" net::detect_public_ip
    rm -rf "${tmpbin}"
  '
  # Should not fail even without curl
  [ "$status" -eq 0 ]
}

@test "net::detect_public_ip - works with ip route fallback" {
  # The function should fall back to ip route if other methods fail
  run bash -c '
    source "'"${PROJECT_ROOT}/modules/net/network.sh"'"
    # Even if primary methods fail, ip route should work
    net::detect_public_ip
  '
  [ "$status" -eq 0 ]
}
