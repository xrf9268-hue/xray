#!/usr/bin/env bats
# Unit tests for Xray path functions (services/xray/common.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source xray/common.sh
  source "${PROJECT_ROOT}/services/xray/common.sh"
}

teardown() {
  cleanup_test_env
}

# Test: xray::prefix
@test "xray::prefix - returns default prefix" {
  unset XRF_PREFIX
  run xray::prefix
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local" ]]
}

@test "xray::prefix - respects XRF_PREFIX environment variable" {
  export XRF_PREFIX="/custom/prefix"
  run xray::prefix
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/prefix" ]]
}

@test "xray::prefix - handles empty XRF_PREFIX" {
  export XRF_PREFIX=""
  run xray::prefix
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local" ]]
}

# Test: xray::etc
@test "xray::etc - returns default etc" {
  unset XRF_ETC
  run xray::etc
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/etc" ]]
}

@test "xray::etc - respects XRF_ETC environment variable" {
  export XRF_ETC="/custom/etc"
  run xray::etc
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/etc" ]]
}

@test "xray::etc - handles empty XRF_ETC" {
  export XRF_ETC=""
  run xray::etc
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/etc" ]]
}

# Test: xray::confbase
@test "xray::confbase - returns correct path with default etc" {
  unset XRF_ETC
  run xray::confbase
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/etc/xray" ]]
}

@test "xray::confbase - uses custom XRF_ETC" {
  export XRF_ETC="/custom/etc"
  run xray::confbase
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/etc/xray" ]]
}

@test "xray::confbase - constructs path correctly" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  local expected="${TEST_TMPDIR}/etc/xray"

  run xray::confbase
  [ "$status" -eq 0 ]
  [[ "$output" == "${expected}" ]]
}

# Test: xray::releases
@test "xray::releases - returns correct path with default" {
  unset XRF_ETC
  run xray::releases
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/etc/xray/releases" ]]
}

@test "xray::releases - uses custom XRF_ETC" {
  export XRF_ETC="/custom/etc"
  run xray::releases
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/etc/xray/releases" ]]
}

@test "xray::releases - constructs nested path correctly" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  local expected="${TEST_TMPDIR}/etc/xray/releases"

  run xray::releases
  [ "$status" -eq 0 ]
  [[ "$output" == "${expected}" ]]
}

# Test: xray::active
@test "xray::active - returns correct path with default" {
  unset XRF_ETC
  run xray::active
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/etc/xray/active" ]]
}

@test "xray::active - uses custom XRF_ETC" {
  export XRF_ETC="/custom/etc"
  run xray::active
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/etc/xray/active" ]]
}

@test "xray::active - constructs path correctly" {
  export XRF_ETC="${TEST_TMPDIR}/etc"
  local expected="${TEST_TMPDIR}/etc/xray/active"

  run xray::active
  [ "$status" -eq 0 ]
  [[ "$output" == "${expected}" ]]
}

# Test: xray::bin
@test "xray::bin - returns correct path with default prefix" {
  unset XRF_PREFIX
  run xray::bin
  [ "$status" -eq 0 ]
  [[ "$output" == "/usr/local/bin/xray" ]]
}

@test "xray::bin - uses custom XRF_PREFIX" {
  export XRF_PREFIX="/custom/prefix"
  run xray::bin
  [ "$status" -eq 0 ]
  [[ "$output" == "/custom/prefix/bin/xray" ]]
}

@test "xray::bin - constructs path correctly" {
  export XRF_PREFIX="${TEST_TMPDIR}"
  local expected="${TEST_TMPDIR}/bin/xray"

  run xray::bin
  [ "$status" -eq 0 ]
  [[ "$output" == "${expected}" ]]
}

# Integration tests: path consistency
@test "all paths use consistent XRF_PREFIX" {
  export XRF_PREFIX="${TEST_TMPDIR}/custom"
  export XRF_ETC="${TEST_TMPDIR}/custom/etc"

  local prefix_result
  local etc_result
  local confbase_result
  local bin_result

  prefix_result=$(xray::prefix)
  etc_result=$(xray::etc)
  confbase_result=$(xray::confbase)
  bin_result=$(xray::bin)

  [[ "${prefix_result}" == "${TEST_TMPDIR}/custom" ]]
  [[ "${etc_result}" == "${TEST_TMPDIR}/custom/etc" ]]
  [[ "${confbase_result}" == "${TEST_TMPDIR}/custom/etc/xray" ]]
  [[ "${bin_result}" == "${TEST_TMPDIR}/custom/bin/xray" ]]
}

@test "all paths have correct hierarchy" {
  export XRF_PREFIX="${TEST_TMPDIR}/usr/local"
  export XRF_ETC="${TEST_TMPDIR}/usr/local/etc"

  local confbase
  local releases
  local active

  confbase=$(xray::confbase)
  releases=$(xray::releases)
  active=$(xray::active)

  # Check hierarchy
  [[ "${releases}" == "${confbase}/releases" ]]
  [[ "${active}" == "${confbase}/active" ]]
}

# Test: xray::generate_shortid
@test "xray::generate_shortid - generates 16-character hex string" {
  run xray::generate_shortid
  [ "$status" -eq 0 ]

  # Check length
  [ "${#output}" -eq 16 ]

  # Check hex format (lowercase)
  [[ "$output" =~ ^[0-9a-f]{16}$ ]]
}

@test "xray::generate_shortid - generates unique values" {
  local id1 id2 id3

  id1=$(xray::generate_shortid)
  id2=$(xray::generate_shortid)
  id3=$(xray::generate_shortid)

  # All three should be different
  [ "${id1}" != "${id2}" ]
  [ "${id2}" != "${id3}" ]
  [ "${id1}" != "${id3}" ]
}

@test "xray::generate_shortid - works with xxd" {
  if ! command -v xxd > /dev/null 2>&1; then
    skip "xxd not available"
  fi

  run xray::generate_shortid
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 16 ]
}

@test "xray::generate_shortid - works with od (fallback)" {
  if ! command -v od > /dev/null 2>&1; then
    skip "od not available"
  fi

  # This test assumes xxd might not be available
  run xray::generate_shortid
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 16 ]
}

@test "xray::generate_shortid - works with openssl (final fallback)" {
  if ! command -v openssl > /dev/null 2>&1; then
    skip "openssl not available (should never happen)"
  fi

  run xray::generate_shortid
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 16 ]
}

@test "xray::generate_shortid - output is valid shortId format" {
  # Source validators to check output
  source "${PROJECT_ROOT}/lib/validators.sh"

  local shortid
  shortid=$(xray::generate_shortid)

  # Should pass validator
  run validators::shortid "${shortid}"
  [ "$status" -eq 0 ]
}

# Test: xray::generate_shortids (batch generation)
@test "xray::generate_shortids - generates 3 shortIds by default" {
  run xray::generate_shortids
  [ "$status" -eq 0 ]

  # Count lines (should be 3)
  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "${line_count}" -eq 3 ]
}

@test "xray::generate_shortids - generates specified count" {
  run xray::generate_shortids 5
  [ "$status" -eq 0 ]

  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "${line_count}" -eq 5 ]
}

@test "xray::generate_shortids - each shortId is 16 characters" {
  local shortids
  mapfile -t shortids < <(xray::generate_shortids 3)

  [ "${#shortids[@]}" -eq 3 ]
  for sid in "${shortids[@]}"; do
    [ "${#sid}" -eq 16 ]
  done
}

@test "xray::generate_shortids - all shortIds are unique" {
  local shortids
  mapfile -t shortids < <(xray::generate_shortids 5)

  # Compare all pairs
  for ((i = 0; i < 5; i++)); do
    for ((j = i + 1; j < 5; j++)); do
      [ "${shortids[$i]}" != "${shortids[$j]}" ]
    done
  done
}

@test "xray::generate_shortids - all shortIds are valid hex" {
  local shortids
  mapfile -t shortids < <(xray::generate_shortids 3)

  for sid in "${shortids[@]}"; do
    [[ "${sid}" =~ ^[0-9a-f]{16}$ ]]
  done
}

@test "xray::generate_shortids - validates against validators::shortid" {
  source "${PROJECT_ROOT}/lib/validators.sh"

  local shortids
  mapfile -t shortids < <(xray::generate_shortids 3)

  for sid in "${shortids[@]}"; do
    run validators::shortid "${sid}"
    [ "$status" -eq 0 ]
  done
}

@test "xray::generate_shortids - rejects invalid count" {
  run xray::generate_shortids 0
  [ "$status" -eq 1 ]
  [[ "$output" =~ error.*"invalid count" ]]
}

@test "xray::generate_shortids - rejects negative count" {
  run xray::generate_shortids -1
  [ "$status" -eq 1 ]
  [[ "$output" =~ error.*"invalid count" ]]
}

@test "xray::generate_shortids - rejects non-numeric count" {
  run xray::generate_shortids abc
  [ "$status" -eq 1 ]
  [[ "$output" =~ error.*"invalid count" ]]
}

@test "xray::generate_shortids - handles count=1" {
  run xray::generate_shortids 1
  [ "$status" -eq 0 ]

  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "${line_count}" -eq 1 ]
  [ "${#output}" -eq 16 ]
}

# Test: xray version parsing helpers
@test "xray::parse_version_text - parses semver from xray output" {
  run xray::parse_version_text "Xray 26.2.6 (Xray, Penetrates Everything.)"
  [ "$status" -eq 0 ]
  [[ "$output" == "v26.2.6" ]]
}

@test "xray::parse_version_text - accepts existing v prefix" {
  run xray::parse_version_text "Xray v26.2.6 custom-build"
  [ "$status" -eq 0 ]
  [[ "$output" == "v26.2.6" ]]
}

@test "xray::parse_version_text - returns empty on invalid output" {
  run xray::parse_version_text "Xray unknown version"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "xray::installed_version - returns unknown for missing binary" {
  run xray::installed_version "/nonexistent/xray"
  [ "$status" -eq 0 ]
  [[ "$output" == "unknown" ]]
}

@test "xray::installed_version - falls back from -version to version command" {
  local mock_bin="${TEST_TMPDIR}/mock-xray"
  cat > "${mock_bin}" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  exit 1
fi
if [[ "${1:-}" == "version" ]]; then
  echo "Xray 26.2.6 (mock build)"
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin}"

  run xray::installed_version "${mock_bin}"
  [ "$status" -eq 0 ]
  [[ "$output" == "v26.2.6" ]]
}

@test "xray::installed_version - uses -version output when it is parseable" {
  local mock_bin="${TEST_TMPDIR}/mock-xray-version"
  cat > "${mock_bin}" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "Xray 27.0.1 (mock build)"
  exit 0
fi
if [[ "${1:-}" == "version" ]]; then
  echo "Xray 99.0.0 (should not be used)"
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin}"

  run xray::installed_version "${mock_bin}"
  [ "$status" -eq 0 ]
  [[ "$output" == "v27.0.1" ]]
}

@test "xray::extract_compat_warnings - reports specific TLS deprecations" {
  run xray::extract_compat_warnings "allowInsecure and serverNameToVerify are deprecated"

  [ "$status" -eq 0 ]
  [[ "$output" == *"allowInsecure detected"* ]]
  [[ "$output" == *"verifyPeerCertInNames or serverNameToVerify detected"* ]]
  [[ "$output" != *"generic deprecation"* ]]
}

@test "xray::extract_compat_warnings - reports generic deprecations when needed" {
  run xray::extract_compat_warnings "Deprecated transport setting encountered"

  [ "$status" -eq 0 ]
  [[ "$output" == *"generic deprecation warnings"* ]]
}

@test "xray::extract_compat_warnings - detects REALITY non-443 port warning" {
  run xray::extract_compat_warnings "REALITY warning: dest port is not 443, this may reduce stealth"

  [ "$status" -eq 0 ]
  [[ "$output" == *"non-443 port"* ]]
  [[ "$output" == *"port 443 is recommended"* ]]
}

@test "xray::extract_compat_warnings - detects Apple/iCloud destination warning" {
  run xray::extract_compat_warnings "WARNING: Apple/iCloud destination may block your IP"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Apple/iCloud REALITY destinations"* ]]
  [[ "$output" == *"choose a different target"* ]]
}

@test "xray::extract_compat_warnings - detects iCloud risk warning" {
  run xray::extract_compat_warnings "icloud.com dest risk of IP blocking detected"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Apple/iCloud REALITY destinations"* ]]
}

@test "xray::extract_compat_warnings - no false positive for unrelated apple text" {
  run xray::extract_compat_warnings "apple pie recipe is delicious"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "xray::generate_vless_encryption_pair - extracts decryption and encryption values" {
  local mock_bin="${TEST_TMPDIR}/mock-xray-vlessenc"
  cat > "${mock_bin}" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "vlessenc" ]]; then
  cat <<'JSON'
{"decryption":"decryption-token","encryption":"encryption-token"}
JSON
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin}"

  run xray::generate_vless_encryption_pair "${mock_bin}"

  [ "$status" -eq 0 ]
  [[ "$output" == $'decryption-token\nencryption-token' ]]
}

@test "xray::generate_vless_encryption_pair - fails when output is incomplete" {
  local mock_bin="${TEST_TMPDIR}/mock-xray-vlessenc-bad"
  cat > "${mock_bin}" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "vlessenc" ]]; then
  echo '{"decryption":"only-one-value"}'
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin}"

  run xray::generate_vless_encryption_pair "${mock_bin}"

  [ "$status" -eq 1 ]
}
