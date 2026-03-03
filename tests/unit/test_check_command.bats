#!/usr/bin/env bats
# Unit tests for commands/check.sh

load ../test_helper

setup() {
  setup_test_env
  mkdir -p "${XRF_ETC}/xray/active"
  mkdir -p "${XRF_PREFIX}/bin"

  cat > "${XRF_PREFIX}/bin/xray" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-test" ]]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${XRF_PREFIX}/bin/xray"

  cat > "${XRF_ETC}/xray/active/05_inbounds.json" <<'JSON'
{"inbounds":[{"tag":"reality","port":443,"protocol":"vless"}]}
JSON
  cat > "${XRF_ETC}/xray/active/06_outbounds.json" <<'JSON'
{"outbounds":[{"protocol":"freedom","tag":"direct"}]}
JSON
}

teardown() {
  cleanup_test_env
}

@test "check command --deep passes on valid config" {
  run "${PROJECT_ROOT}/commands/check.sh" --deep --confdir "${XRF_ETC}/xray/active"
  [ "$status" -eq 0 ]
}

@test "check command --deep fails on invalid json" {
  printf '{bad-json\n' > "${XRF_ETC}/xray/active/06_outbounds.json"
  run "${PROJECT_ROOT}/commands/check.sh" --deep --confdir "${XRF_ETC}/xray/active"
  [ "$status" -eq 1 ]
}

@test "check command without --deep runs binary validation" {
  run "${PROJECT_ROOT}/commands/check.sh" --confdir "${XRF_ETC}/xray/active"
  [ "$status" -eq 0 ]
}

@test "check command rejects unknown option" {
  run "${PROJECT_ROOT}/commands/check.sh" --bad-option
  [ "$status" -eq 1 ]
  [[ "${output}" == *"Usage: xrf check"* ]]
}
