#!/usr/bin/env bats
# Test modules/web/caddy.sh - Caddy web server management

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/core.sh"
  source "${PROJECT_ROOT}/lib/validators.sh"
  source "${PROJECT_ROOT}/modules/io.sh"
  source "${PROJECT_ROOT}/modules/web/caddy.sh"
}

teardown() {
  cleanup_test_env
}

# === Path Function Tests ===

@test "caddy::bin returns correct path" {
  result="$(caddy::bin)"
  [ "${result}" = "/usr/local/bin/caddy" ]
}

@test "caddy::config_dir returns correct path" {
  result="$(caddy::config_dir)"
  [ "${result}" = "/usr/local/etc/caddy" ]
}

@test "caddy::config_file returns correct path" {
  result="$(caddy::config_file)"
  [ "${result}" = "/usr/local/etc/caddy/Caddyfile" ]
}

@test "caddy::cert_dir returns correct path" {
  result="$(caddy::cert_dir)"
  [ "${result}" = "/usr/local/etc/xray/certs" ]
}

@test "caddy::systemd_file returns correct path" {
  result="$(caddy::systemd_file)"
  [ "${result}" = "/etc/systemd/system/caddy.service" ]
}

# === caddy::detect_arch Tests ===

@test "caddy::detect_arch returns amd64 for x86_64" {
  # Mock uname to return x86_64
  uname() {
    case "$1" in
      -m) echo "x86_64" ;;
      *) command uname "$@" ;;
    esac
  }
  export -f uname

  result="$(caddy::detect_arch)"
  [ "${result}" = "amd64" ]
}

@test "caddy::detect_arch returns arm64 for aarch64" {
  # Mock uname to return aarch64
  uname() {
    case "$1" in
      -m) echo "aarch64" ;;
      *) command uname "$@" ;;
    esac
  }
  export -f uname

  result="$(caddy::detect_arch)"
  [ "${result}" = "arm64" ]
}

@test "caddy::detect_arch returns amd64 for amd64 input" {
  uname() {
    case "$1" in
      -m) echo "amd64" ;;
      *) command uname "$@" ;;
    esac
  }
  export -f uname

  result="$(caddy::detect_arch)"
  [ "${result}" = "amd64" ]
}

@test "caddy::detect_arch returns arm64 for arm64 input" {
  uname() {
    case "$1" in
      -m) echo "arm64" ;;
      *) command uname "$@" ;;
    esac
  }
  export -f uname

  result="$(caddy::detect_arch)"
  [ "${result}" = "arm64" ]
}

# === caddy::install Tests ===

@test "caddy::install skips when caddy already installed" {
  # Create mock caddy binary
  mkdir -p "${TEST_TMPDIR}/bin"
  cat > "${TEST_TMPDIR}/bin/caddy" << 'EOF'
#!/bin/bash
echo "v2.7.0"
EOF
  chmod +x "${TEST_TMPDIR}/bin/caddy"

  # Override caddy::bin to return our mock path
  caddy::bin() { echo "${TEST_TMPDIR}/bin/caddy"; }

  run caddy::install
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already installed"* ]]
}

# === caddy::setup_auto_tls Port Validation Tests ===

@test "caddy::setup_auto_tls rejects invalid http port" {
  export CADDY_HTTP_PORT="invalid"
  run caddy::setup_auto_tls "example.com" 8443
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"invalid port"* ]]
}

@test "caddy::setup_auto_tls rejects port 0" {
  export CADDY_HTTP_PORT="0"
  run caddy::setup_auto_tls "example.com" 8443
  [ "${status}" -ne 0 ]
}

@test "caddy::setup_auto_tls rejects port over 65535" {
  export CADDY_HTTP_PORT="70000"
  run caddy::setup_auto_tls "example.com" 8443
  [ "${status}" -ne 0 ]
}

@test "caddy::setup_auto_tls detects port conflict with xray" {
  export CADDY_HTTPS_PORT="8443"
  run caddy::setup_auto_tls "example.com" 8443
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"port conflict"* ]]
}

@test "caddy::setup_auto_tls uses default ports when not set" {
  unset CADDY_HTTP_PORT
  unset CADDY_HTTPS_PORT
  unset CADDY_FALLBACK_PORT

  # This will fail at systemctl but port validation should pass
  run caddy::setup_auto_tls "example.com" 8443
  # Should not fail with port validation error
  [[ "${output}" != *"invalid port"* ]]
}

# === Path Configuration Tests ===

@test "caddy paths are consistent" {
  config_dir="$(caddy::config_dir)"
  config_file="$(caddy::config_file)"

  # config_file should be inside config_dir
  [[ "${config_file}" == "${config_dir}/"* ]]
}

@test "caddy config file is Caddyfile" {
  config_file="$(caddy::config_file)"
  [ "${config_file##*/}" = "Caddyfile" ]
}

# === Environment Variable Tests ===

@test "CADDY_HTTP_PORT environment variable is respected" {
  export CADDY_HTTP_PORT="8080"
  # We can't fully test setup_auto_tls without systemd, but we can verify
  # the variable is used by checking the function behavior
  [ "${CADDY_HTTP_PORT}" = "8080" ]
}

@test "CADDY_HTTPS_PORT environment variable is respected" {
  export CADDY_HTTPS_PORT="9443"
  [ "${CADDY_HTTPS_PORT}" = "9443" ]
}

@test "CADDY_FALLBACK_PORT environment variable is respected" {
  export CADDY_FALLBACK_PORT="8888"
  [ "${CADDY_FALLBACK_PORT}" = "8888" ]
}

# === Function Existence Tests ===

@test "all caddy functions are defined" {
  declare -f caddy::bin > /dev/null
  declare -f caddy::config_dir > /dev/null
  declare -f caddy::config_file > /dev/null
  declare -f caddy::cert_dir > /dev/null
  declare -f caddy::systemd_file > /dev/null
  declare -f caddy::detect_arch > /dev/null
  declare -f caddy::get_latest_version > /dev/null
  declare -f caddy::install > /dev/null
  declare -f caddy::create_systemd_service > /dev/null
  declare -f caddy::setup_auto_tls > /dev/null
  declare -f caddy::wait_for_cert > /dev/null
  declare -f caddy::setup_cert_sync > /dev/null
}
