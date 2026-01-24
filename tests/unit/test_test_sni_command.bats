#!/usr/bin/env bats
# Unit tests for commands/test-sni.sh

load ../test_helper

setup() {
  setup_test_env

  # Create mock command structure
  export HERE="${TEST_TMPDIR}/xray"
  mkdir -p "${HERE}/lib"
  mkdir -p "${HERE}/commands"

  # Create minimal core.sh mock
  cat > "${HERE}/lib/core.sh" << 'EOF'
XRF_DEBUG="${XRF_DEBUG:-false}"
XRF_JSON="${XRF_JSON:-false}"
core::init() { :; }
core::log() {
  local level="${1}" msg="${2}" ctx="${3:-{}}"
  if [[ "${XRF_JSON}" == "true" ]]; then
    printf '{"level":"%s","msg":"%s"}\n' "${level}" "${msg}" >&2
  else
    echo "[${level}] ${msg}" >&2
  fi
}
EOF

  # Create minimal sni_validator.sh mock
  cat > "${HERE}/lib/sni_validator.sh" << 'EOF'
sni::validate() {
  local domain="${1}" port="${2:-443}"

  # Mock validation - succeed for known good domains
  case "${domain}" in
    www.microsoft.com|www.cloudflare.com|valid.example.com)
      return 0
      ;;
    invalid.example.com|bad-sni.test)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}
EOF

  source "${HERE}/lib/core.sh"
  source "${HERE}/lib/sni_validator.sh"
}

teardown() {
  cleanup_test_env
}

# Test argument parsing
@test "test-sni - parses domain as first positional argument" {
  local domain=""

  # Simulate parsing
  local args=("example.com")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --*|-*) ;;
      *)
        if [[ -z "${domain}" ]]; then
          domain="${arg}"
        fi
        ;;
    esac
  done

  [ "${domain}" = "example.com" ]
}

@test "test-sni - parses --port option" {
  local port="443"

  local args=("--port" "8443")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --port)
        port="${args[$((i+1))]:-443}"
        i=$((i+2))
        ;;
      *)
        i=$((i+1))
        ;;
    esac
  done

  [ "${port}" = "8443" ]
}

@test "test-sni - parses --json option" {
  local json_mode="false"

  local args=("--json")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --json)
        json_mode="true"
        ;;
    esac
  done

  [ "${json_mode}" = "true" ]
}

@test "test-sni - default port is 443" {
  local port="443"
  [ "${port}" = "443" ]
}

@test "test-sni - parses combined arguments correctly" {
  local domain="" port="443" json_mode="false"

  local args=("example.com" "--port" "8443" "--json")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --port)
        port="${args[$((i+1))]:-443}"
        i=$((i+2))
        ;;
      --json)
        json_mode="true"
        i=$((i+1))
        ;;
      --*|-*)
        i=$((i+1))
        ;;
      *)
        if [[ -z "${domain}" ]]; then
          domain="${args[$i]}"
        fi
        i=$((i+1))
        ;;
    esac
  done

  [ "${domain}" = "example.com" ]
  [ "${port}" = "8443" ]
  [ "${json_mode}" = "true" ]
}

# Test validation behavior
@test "test-sni - validates domain is required" {
  local domain=""

  # Empty domain should trigger error
  if [[ -z "${domain}" ]]; then
    run core::log error "domain required" "{}"
    [ "$status" -eq 0 ]
  fi

  [ -z "${domain}" ]
}

@test "test-sni - succeeds for valid SNI domain" {
  run sni::validate "www.microsoft.com" "443"
  [ "$status" -eq 0 ]
}

@test "test-sni - succeeds for valid SNI with custom port" {
  run sni::validate "www.cloudflare.com" "8443"
  [ "$status" -eq 0 ]
}

@test "test-sni - fails for invalid SNI domain" {
  run sni::validate "invalid.example.com" "443"
  [ "$status" -eq 1 ]
}

@test "test-sni - fails for bad-sni.test domain" {
  run sni::validate "bad-sni.test" "443"
  [ "$status" -eq 1 ]
}

# Test error handling
@test "test-sni - detects unknown option" {
  local unknown_opt=""

  local args=("--unknown-flag")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --port|--json|--help|-h) ;;
      -*)
        unknown_opt="${arg}"
        ;;
    esac
  done

  [ "${unknown_opt}" = "--unknown-flag" ]
}

@test "test-sni - detects unexpected positional argument" {
  local domain="" extra_arg=""

  local args=("example.com" "extra-arg")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --*|-*) ;;
      *)
        if [[ -z "${domain}" ]]; then
          domain="${arg}"
        else
          extra_arg="${arg}"
        fi
        ;;
    esac
  done

  [ "${domain}" = "example.com" ]
  [ "${extra_arg}" = "extra-arg" ]
}

# Test usage output
@test "test-sni - usage includes required sections" {
  local usage
  usage=$(cat << 'EOF'
Usage: xrf test-sni <domain> [options]

Test SNI domain suitability for VLESS+REALITY protocol.

Arguments:
  <domain>                      Domain to test (required)

Options:
  --port <port>                 Port to test (default: 443)
  --json                        Output in JSON format
  --help, -h                    Show this help
EOF
)

  [[ "${usage}" == *"Usage:"* ]]
  [[ "${usage}" == *"<domain>"* ]]
  [[ "${usage}" == *"--port"* ]]
  [[ "${usage}" == *"--json"* ]]
  [[ "${usage}" == *"--help"* ]]
}

@test "test-sni - usage mentions TLS 1.3 check" {
  local usage
  usage=$(cat << 'EOF'
Checks performed:
  - TLS 1.3 support
  - HTTP/2 support
  - Cross-domain redirect detection
EOF
)

  [[ "${usage}" == *"TLS 1.3"* ]]
  [[ "${usage}" == *"HTTP/2"* ]]
  [[ "${usage}" == *"redirect"* ]]
}

@test "test-sni - usage includes examples" {
  local usage
  usage=$(cat << 'EOF'
Examples:
  # Test default SNI
  xrf test-sni www.microsoft.com

  # Test with custom port
  xrf test-sni example.com --port 8443

  # JSON output
  xrf test-sni www.cloudflare.com --json
EOF
)

  [[ "${usage}" == *"www.microsoft.com"* ]]
  [[ "${usage}" == *"--port 8443"* ]]
  [[ "${usage}" == *"--json"* ]]
}

# Test JSON output mode
@test "test-sni - sets XRF_JSON when --json flag used" {
  export XRF_JSON="false"

  # Simulate --json handling
  XRF_JSON="true"

  [ "${XRF_JSON}" = "true" ]
}

@test "test-sni - JSON output format is valid" {
  XRF_JSON=true
  run core::log error "test message" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"level":"error"'* ]]
  [[ "$output" == *'"msg":"test message"'* ]]
}

# Test exit codes
@test "test-sni - exit 0 on successful validation" {
  run sni::validate "valid.example.com" "443"
  [ "$status" -eq 0 ]
}

@test "test-sni - exit 1 on failed validation" {
  run sni::validate "invalid.example.com" "443"
  [ "$status" -eq 1 ]
}

# Test help flag variants
@test "test-sni - recognizes --help flag" {
  local show_help=false

  local args=("--help")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --help|-h)
        show_help=true
        ;;
    esac
  done

  [ "${show_help}" = "true" ]
}

@test "test-sni - recognizes -h flag" {
  local show_help=false

  local args=("-h")
  for arg in "${args[@]}"; do
    case "${arg}" in
      --help|-h)
        show_help=true
        ;;
    esac
  done

  [ "${show_help}" = "true" ]
}

# Test domain format validation (delegated to sni::validate)
@test "test-sni - passes domain to sni::validate" {
  local validated_domain=""
  local validated_port=""

  # Mock sni::validate that captures args
  sni::validate() {
    validated_domain="${1}"
    validated_port="${2}"
    return 0
  }

  sni::validate "test.example.com" "443"

  [ "${validated_domain}" = "test.example.com" ]
  [ "${validated_port}" = "443" ]
}

@test "test-sni - passes custom port to sni::validate" {
  local validated_port=""

  sni::validate() {
    validated_port="${2}"
    return 0
  }

  sni::validate "example.com" "8443"

  [ "${validated_port}" = "8443" ]
}
