#!/usr/bin/env bats
# Unit tests for commands/test-sni.sh using real command execution

load ../test_helper

install_network_stubs() {
  mkdir -p "${TEST_TMPDIR}/bin"

  cat > "${TEST_TMPDIR}/bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF
  chmod +x "${TEST_TMPDIR}/bin/timeout"

  cat > "${TEST_TMPDIR}/bin/openssl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "s_client" ]]; then
  printf '%b\n' "${MOCK_OPENSSL_OUTPUT:-Protocol  : TLSv1.3\nCipher    : TLS_AES_128_GCM_SHA256}"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_TMPDIR}/bin/openssl"

  cat > "${TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
args="$*"
url="${@: -1}"

if [[ "${args}" == *"%{http_version}"* ]]; then
  printf '%s\n' "${MOCK_CURL_HTTP_VERSION:-2}"
  exit 0
fi

if [[ "${args}" == *"%{url_effective}"* ]]; then
  printf '%s\n' "${MOCK_CURL_EFFECTIVE_URL:-${url}}"
  exit 0
fi

exit 1
EOF
  chmod +x "${TEST_TMPDIR}/bin/curl"
}

setup() {
  setup_test_env
  ORIGINAL_PATH="${PATH}"
  install_network_stubs
  export PATH="${TEST_TMPDIR}/bin:${PATH}"
  export XRF_JSON="false"
  export XRF_DEBUG="false"
}

teardown() {
  export PATH="${ORIGINAL_PATH}"
  cleanup_test_env
}

@test "test-sni command prints usage with --help" {
  run "${PROJECT_ROOT}/commands/test-sni.sh" --help

  [ "$status" -eq 0 ]
  [[ "${output}" == *"Usage: xrf test-sni <domain> [options]"* ]]
  [[ "${output}" == *"--port <port>"* ]]
  [[ "${output}" == *"--json"* ]]
}

@test "test-sni command rejects unknown options" {
  run "${PROJECT_ROOT}/commands/test-sni.sh" example.com --bad-option

  [ "$status" -eq 1 ]
  [[ "${output}" == *"unknown option"* ]]
  [[ "${output}" == *"Usage: xrf test-sni"* ]]
}

@test "test-sni command requires a domain" {
  run "${PROJECT_ROOT}/commands/test-sni.sh"

  [ "$status" -eq 1 ]
  [[ "${output}" == *"domain required"* ]]
  [[ "${output}" == *"Usage: xrf test-sni"* ]]
}

@test "test-sni command rejects unexpected extra positional arguments" {
  run "${PROJECT_ROOT}/commands/test-sni.sh" example.com extra.example.com

  [ "$status" -eq 1 ]
  [[ "${output}" == *"unexpected argument"* ]]
  [[ "${output}" == *"extra.example.com"* ]]
}

@test "test-sni command passes custom port and json flag to validator" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.3\nCipher    : TLS_AES_128_GCM_SHA256'
  export MOCK_CURL_HTTP_VERSION="2"
  export MOCK_CURL_EFFECTIVE_URL="https://valid.example.com/"

  run "${PROJECT_ROOT}/commands/test-sni.sh" valid.example.com --port 8443 --json

  [ "$status" -eq 0 ]
  [[ "${output}" == *'"domain": "valid.example.com"'* ]]
  [[ "${output}" == *'"port": 8443'* ]]
  [[ "${output}" == *'"passed": true'* ]]
}

@test "test-sni command uses port 443 by default" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.3\nCipher    : TLS_AES_128_GCM_SHA256'
  export MOCK_CURL_HTTP_VERSION="2"
  export MOCK_CURL_EFFECTIVE_URL="https://default.example.com/"

  run "${PROJECT_ROOT}/commands/test-sni.sh" default.example.com --json

  [ "$status" -eq 0 ]
  [[ "${output}" == *'"port": 443'* ]]
  [[ "${output}" == *'"passed": true'* ]]
}

@test "test-sni command returns non-zero when validation fails" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.2\nCipher    : ECDHE-RSA-AES128-GCM-SHA256'
  export MOCK_CURL_HTTP_VERSION="1.1"
  export MOCK_CURL_EFFECTIVE_URL="https://redirected.example.net/"

  run "${PROJECT_ROOT}/commands/test-sni.sh" broken.example.com --json

  [ "$status" -eq 1 ]
  [[ "${output}" == *'"domain": "broken.example.com"'* ]]
  [[ "${output}" == *'"passed": false'* ]]
}
