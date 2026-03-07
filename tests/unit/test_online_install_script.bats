#!/usr/bin/env bats
# Unit tests for the top-level online install.sh wrapper.

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

@test "install.sh - parse_args accepts --yes" {
  run bash -lc '
    source "'"${PROJECT_ROOT}"'/install.sh"
    TMP_DIR="$(mktemp -d)"
    trap '"'"'rm -rf "${TMP_DIR}"'"'"' EXIT
    source_args_module
    parse_args --topology reality-only --yes
    printf "%s" "${XRF_YES}"
  '

  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

@test "install.sh - help documents --yes" {
  run grep -n -- '--yes, -y' "${PROJECT_ROOT}/install.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Auto-confirm installation"* ]]
}

@test "install.sh - run_xray_install forwards --yes to xrf install" {
  run bash -lc '
    source "'"${PROJECT_ROOT}"'/install.sh"
    workdir="$(mktemp -d)"
    trap '"'"'rm -rf "${workdir}"'"'"' EXIT

    INSTALL_DIR="${workdir}/install"
    SYMLINK_PATH="${workdir}/xrf"
    mkdir -p "${INSTALL_DIR}/bin"

    cat > "${INSTALL_DIR}/bin/xrf" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "__CALLS_FILE__"
exit 0
EOF
    sed -i "s|__CALLS_FILE__|${workdir}/calls.log|" "${INSTALL_DIR}/bin/xrf"
    chmod +x "${INSTALL_DIR}/bin/xrf"

    TOPOLOGY="reality-only"
    DOMAIN=""
    VERSION="latest"
    PLUGINS=""
    DEBUG="false"
    XRF_YES="true"
    INTEGRITY_VERIFIED="true"

    run_xray_install >/dev/null
    cat "${workdir}/calls.log"
  '

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"install --topology reality-only --yes"* ]]
  [[ "${output}" == *"status"* ]]
}
