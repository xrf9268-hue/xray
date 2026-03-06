#!/usr/bin/env bats
# Deterministic unit tests for lib/sni_validator.sh

load ../test_helper

install_sni_stubs() {
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
  install_sni_stubs
  export PATH="${TEST_TMPDIR}/bin:${PATH}"
  export XRF_JSON="false"
  export XRF_DEBUG="false"

  source "${PROJECT_ROOT}/lib/core.sh"
  core::init
  source "${PROJECT_ROOT}/lib/sni_validator.sh"
}

teardown() {
  export PATH="${ORIGINAL_PATH}"
  cleanup_test_env
}

@test "sni::check_tls13 succeeds when openssl reports TLSv1.3" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.3\nCipher    : TLS_AES_128_GCM_SHA256'

  run sni::check_tls13 "www.cloudflare.com" 8443

  [ "$status" -eq 0 ]
}

@test "sni::check_tls13 fails when openssl output lacks TLSv1.3" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.2\nCipher    : ECDHE-RSA-AES128-GCM-SHA256'

  run sni::check_tls13 "legacy.example.com" 443

  [ "$status" -eq 1 ]
  [[ "${output}" == *"TLS 1.3 not supported"* ]]
}

@test "sni::check_http2 succeeds when curl negotiates HTTP/2" {
  export MOCK_CURL_HTTP_VERSION="2"

  run sni::check_http2 "www.cloudflare.com"

  [ "$status" -eq 0 ]
}

@test "sni::check_http2 fails when curl reports HTTP/1.1" {
  export MOCK_CURL_HTTP_VERSION="1.1"

  run sni::check_http2 "old.example.com"

  [ "$status" -eq 1 ]
  [[ "${output}" == *"HTTP/2 not supported"* ]]
}

@test "sni::check_redirect succeeds when final URL stays on the same domain" {
  export MOCK_CURL_EFFECTIVE_URL="https://www.microsoft.com/download"

  run sni::check_redirect "www.microsoft.com"

  [ "$status" -eq 0 ]
}

@test "sni::check_redirect treats empty effective URL as no redirect" {
  export MOCK_CURL_EFFECTIVE_URL=""

  run sni::check_redirect "www.microsoft.com"

  [ "$status" -eq 0 ]
}

@test "sni::check_redirect fails on cross-domain redirects" {
  export MOCK_CURL_EFFECTIVE_URL="https://login.live.com/oauth"

  run sni::check_redirect "www.microsoft.com"

  [ "$status" -eq 1 ]
  [[ "${output}" == *"cross-domain redirect detected"* ]]
}

@test "sni::validate prints text summary when all checks pass" {
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.3\nCipher    : TLS_AES_128_GCM_SHA256'
  export MOCK_CURL_HTTP_VERSION="2"
  export MOCK_CURL_EFFECTIVE_URL="https://www.cloudflare.com/"

  run sni::validate "www.cloudflare.com" 8443

  [ "$status" -eq 0 ]
  [[ "${output}" == *"Testing SNI: www.cloudflare.com"* ]]
  [[ "${output}" == *"TLS 1.3 supported"* ]]
  [[ "${output}" == *"HTTP/2 enabled"* ]]
  [[ "${output}" == *"No cross-domain redirects"* ]]
  [[ "${output}" == *"suitable for REALITY protocol"* ]]
}

@test "sni::validate prints JSON and fails when any check fails" {
  export XRF_JSON="true"
  export MOCK_OPENSSL_OUTPUT=$'Protocol  : TLSv1.2\nCipher    : ECDHE-RSA-AES128-GCM-SHA256'
  export MOCK_CURL_HTTP_VERSION="1.1"
  export MOCK_CURL_EFFECTIVE_URL="https://redirected.example.net/"

  run sni::validate "bad.example.com" 443

  [ "$status" -eq 1 ]
  [[ "${output}" == *'"domain": "bad.example.com"'* ]]
  [[ "${output}" == *'"port": 443'* ]]
  [[ "${output}" == *'"tls13": false'* ]]
  [[ "${output}" == *'"http2": false'* ]]
  [[ "${output}" == *'"no_redirect": false'* ]]
  [[ "${output}" == *'"passed": false'* ]]
}
