#!/usr/bin/env bats
# Integration-style tests for systemd unit installation handling

load test_helper

setup() {
  setup_integration_env
  mkdir -p "${XRF_ETC}/systemd/system" "${XRF_VAR}"

  cat > "${TEST_ROOT}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "${XRF_VAR}/systemctl.log"
case "${1:-}" in
  daemon-reload) exit 0 ;;
  enable) exit 1 ;; # simulate start failure
  disable) exit 0 ;;
  reset-failed) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${TEST_ROOT}/bin/systemctl"

  cat > "${TEST_ROOT}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "${XRF_VAR}/sudo.log"
exit 0
EOF
  chmod +x "${TEST_ROOT}/bin/sudo"

  cat > "${TEST_ROOT}/bin/getent" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${TEST_ROOT}/bin/getent"
}

teardown() {
  cleanup_integration_env
}

@test "install_unit rolls back when systemctl enable fails" {
  export XRF_SYSTEMD_DIR="${XRF_ETC}/systemd/system"

  run "${PROJECT_ROOT}/services/xray/systemd-unit.sh" install

  [ "$status" -ne 0 ]
  [ ! -f "${XRF_SYSTEMD_DIR}/xray.service" ]
  [ -f "${XRF_VAR}/systemctl.log" ]
  reload_count="$(grep -c 'systemctl daemon-reload' "${XRF_VAR}/systemctl.log")"
  [ "${reload_count}" -ge 2 ]
  grep -q "systemctl enable --now xray" "${XRF_VAR}/systemctl.log"
  grep -q "systemctl disable --now xray" "${XRF_VAR}/systemctl.log"
  grep -q "systemctl reset-failed xray.service" "${XRF_VAR}/systemctl.log"
}
