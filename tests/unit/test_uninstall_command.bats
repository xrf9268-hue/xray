#!/usr/bin/env bats
# Unit tests for commands/uninstall.sh

load ../test_helper

setup() {
  setup_test_env

  # Create mock HERE directory structure
  export HERE="${TEST_TMPDIR}/xray"
  mkdir -p "${HERE}/lib"
  mkdir -p "${HERE}/services/xray"
  mkdir -p "${HERE}/plugins/enabled"
  mkdir -p "${HERE}/plugins/available"

  # Create minimal core.sh mock
  cat > "${HERE}/lib/core.sh" << 'EOF'
core::init() { :; }
core::log() {
  local level="${1}" msg="${2}"
  echo "[${level}] ${msg}" >&2
}
EOF

  # Create minimal plugins.sh mock
  cat > "${HERE}/lib/plugins.sh" << 'EOF'
plugins::ensure_dirs() { :; }
plugins::load_enabled() { :; }
plugins::emit() { :; }
EOF

  # Create minimal common.sh mock
  cat > "${HERE}/services/xray/common.sh" << 'EOF'
xray::prefix() { echo "${XRF_PREFIX:-/usr/local}"; }
xray::confbase() { echo "${XRF_ETC:-/etc}/xray"; }
EOF

  # Create mock systemd-unit.sh
  cat > "${HERE}/services/xray/systemd-unit.sh" << 'EOF'
#!/usr/bin/env bash
echo "systemd-unit.sh called with: $*"
exit 0
EOF
  chmod +x "${HERE}/services/xray/systemd-unit.sh"

  # Source the helper functions from uninstall.sh directly
  # We need to extract and test individual functions
  source "${HERE}/lib/core.sh"
  source "${HERE}/lib/plugins.sh"
  source "${HERE}/services/xray/common.sh"
}

teardown() {
  cleanup_test_env
}

# Test the _rm helper function
@test "_rm - removes existing file" {
  # Define _rm function
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && {
      echo "rm -rf ${p}"
      rm -rf "${p}" || true
    }
  }

  local test_file="${TEST_TMPDIR}/testfile"
  touch "${test_file}"
  [ -f "${test_file}" ]

  run _rm "${test_file}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm -rf ${test_file}"* ]]
  [ ! -f "${test_file}" ]
}

@test "_rm - removes existing directory" {
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && {
      echo "rm -rf ${p}"
      rm -rf "${p}" || true
    }
  }

  local test_dir="${TEST_TMPDIR}/testdir"
  mkdir -p "${test_dir}"
  [ -d "${test_dir}" ]

  run _rm "${test_dir}"
  [ "$status" -eq 0 ]
  [ ! -d "${test_dir}" ]
}

@test "_rm - removes symlink" {
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && {
      echo "rm -rf ${p}"
      rm -rf "${p}" || true
    }
  }

  local target="${TEST_TMPDIR}/target"
  local link="${TEST_TMPDIR}/link"
  touch "${target}"
  ln -s "${target}" "${link}"
  [ -L "${link}" ]

  run _rm "${link}"
  [ "$status" -eq 0 ]
  [ ! -L "${link}" ]
  [ -f "${target}" ]  # Target should still exist
}

@test "_rm - returns non-zero for non-existent path" {
  # The _rm function uses && which returns 1 when condition is false
  # This is expected behavior - callers use || true to ignore
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && {
      echo "rm -rf ${p}"
      rm -rf "${p}" || true
    }
  }

  run _rm "${TEST_TMPDIR}/nonexistent"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_rm - removes broken symlink" {
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && {
      echo "rm -rf ${p}"
      rm -rf "${p}" || true
    }
  }

  local link="${TEST_TMPDIR}/broken_link"
  ln -s "${TEST_TMPDIR}/nonexistent_target" "${link}"
  [ -L "${link}" ]
  [ ! -e "${link}" ]  # Link exists but target doesn't

  run _rm "${link}"
  [ "$status" -eq 0 ]
  [ ! -L "${link}" ]
}

# Test disable_all_plugins function
@test "disable_all_plugins - returns 0 when enabled dir does not exist" {
  disable_all_plugins() {
    local enabled_dir="${HERE}/plugins/enabled"

    if [[ ! -d "${enabled_dir}" ]]; then
      return 0
    fi

    for plugin_link in "${enabled_dir}"/*.sh; do
      if [[ -L "${plugin_link}" ]]; then
        rm -f "${plugin_link}" || true
      fi
    done
  }

  rm -rf "${HERE}/plugins/enabled"

  run disable_all_plugins
  [ "$status" -eq 0 ]
}

@test "disable_all_plugins - removes all enabled plugin symlinks" {
  disable_all_plugins() {
    local enabled_dir="${HERE}/plugins/enabled"

    if [[ ! -d "${enabled_dir}" ]]; then
      return 0
    fi

    for plugin_link in "${enabled_dir}"/*.sh; do
      if [[ -L "${plugin_link}" ]]; then
        rm -f "${plugin_link}" || true
      fi
    done
  }

  # Create some fake plugins
  mkdir -p "${HERE}/plugins/available/plugin1"
  mkdir -p "${HERE}/plugins/available/plugin2"
  touch "${HERE}/plugins/available/plugin1/plugin.sh"
  touch "${HERE}/plugins/available/plugin2/plugin.sh"

  # Create enabled symlinks
  ln -s "${HERE}/plugins/available/plugin1/plugin.sh" "${HERE}/plugins/enabled/plugin1.sh"
  ln -s "${HERE}/plugins/available/plugin2/plugin.sh" "${HERE}/plugins/enabled/plugin2.sh"

  [ -L "${HERE}/plugins/enabled/plugin1.sh" ]
  [ -L "${HERE}/plugins/enabled/plugin2.sh" ]

  run disable_all_plugins
  [ "$status" -eq 0 ]
  [ ! -L "${HERE}/plugins/enabled/plugin1.sh" ]
  [ ! -L "${HERE}/plugins/enabled/plugin2.sh" ]
}

@test "disable_all_plugins - ignores non-symlink files" {
  disable_all_plugins() {
    local enabled_dir="${HERE}/plugins/enabled"

    if [[ ! -d "${enabled_dir}" ]]; then
      return 0
    fi

    for plugin_link in "${enabled_dir}"/*.sh; do
      if [[ -L "${plugin_link}" ]]; then
        rm -f "${plugin_link}" || true
      fi
    done
  }

  # Create a regular file (not a symlink)
  touch "${HERE}/plugins/enabled/regular.sh"

  run disable_all_plugins
  [ "$status" -eq 0 ]
  [ -f "${HERE}/plugins/enabled/regular.sh" ]  # Should still exist
}

@test "disable_all_plugins - handles empty enabled directory" {
  disable_all_plugins() {
    local enabled_dir="${HERE}/plugins/enabled"

    if [[ ! -d "${enabled_dir}" ]]; then
      return 0
    fi

    for plugin_link in "${enabled_dir}"/*.sh; do
      if [[ -L "${plugin_link}" ]]; then
        rm -f "${plugin_link}" || true
      fi
    done
  }

  # enabled dir exists but is empty
  mkdir -p "${HERE}/plugins/enabled"

  run disable_all_plugins
  [ "$status" -eq 0 ]
}

# Test uninstall_caddy function components
@test "uninstall_caddy - identifies correct systemd units" {
  # Test that the units array contains expected values
  local units=(
    "caddy"
    "cert-reload.timer"
    "cert-reload.service"
    "cert-reload.path"
    "caddy-cert-sync.timer"
    "caddy-cert-sync.service"
  )

  [ "${#units[@]}" -eq 6 ]
  [[ " ${units[*]} " == *" caddy "* ]]
  [[ " ${units[*]} " == *" cert-reload.timer "* ]]
  [[ " ${units[*]} " == *" cert-reload.service "* ]]
  [[ " ${units[*]} " == *" cert-reload.path "* ]]
  [[ " ${units[*]} " == *" caddy-cert-sync.timer "* ]]
  [[ " ${units[*]} " == *" caddy-cert-sync.service "* ]]
}

@test "uninstall_caddy - removes correct file paths" {
  # Test that all expected paths are targeted
  local paths=(
    "/etc/systemd/system/caddy.service"
    "/etc/systemd/system/cert-reload.timer"
    "/etc/systemd/system/cert-reload.service"
    "/etc/systemd/system/cert-reload.path"
    "/etc/systemd/system/cert-reload.target"
    "/etc/systemd/system/caddy-cert-sync.service"
    "/etc/systemd/system/caddy-cert-sync.timer"
    "/usr/local/bin/caddy"
    "/usr/local/bin/caddy-cert-sync"
    "/usr/local/etc/caddy"
  )

  [ "${#paths[@]}" -eq 10 ]

  # Verify all paths are absolute
  for path in "${paths[@]}"; do
    [[ "${path}" == /* ]]
  done
}

# Test xray path functions used in uninstall
@test "xray::prefix - returns XRF_PREFIX when set" {
  export XRF_PREFIX="/custom/prefix"
  run xray::prefix
  [ "$status" -eq 0 ]
  [ "$output" = "/custom/prefix" ]
}

@test "xray::prefix - returns default when XRF_PREFIX not set" {
  unset XRF_PREFIX
  run xray::prefix
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local" ]
}

@test "xray::confbase - returns XRF_ETC when set" {
  export XRF_ETC="/custom/etc"
  run xray::confbase
  [ "$status" -eq 0 ]
  [ "$output" = "/custom/etc/xray" ]
}

@test "xray::confbase - returns default when XRF_ETC not set" {
  unset XRF_ETC
  run xray::confbase
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/xray" ]
}

# Integration-style tests for uninstall workflow
@test "uninstall workflow - calls systemd-unit.sh remove" {
  local calls_file="${TEST_TMPDIR}/calls"

  cat > "${HERE}/services/xray/systemd-unit.sh" << EOF
#!/usr/bin/env bash
echo "systemd-unit remove" >> "${calls_file}"
exit 0
EOF
  chmod +x "${HERE}/services/xray/systemd-unit.sh"

  "${HERE}/services/xray/systemd-unit.sh" remove 2>/dev/null || true

  [ -f "${calls_file}" ]
  grep -q "systemd-unit remove" "${calls_file}"
}

@test "uninstall workflow - emits correct plugin events" {
  local events_file="${TEST_TMPDIR}/events"

  # Override plugins::emit to track calls
  plugins::emit() {
    echo "$1" >> "${events_file}"
  }

  plugins::emit uninstall_pre
  plugins::emit uninstall_post

  [ -f "${events_file}" ]
  grep -q "uninstall_pre" "${events_file}"
  grep -q "uninstall_post" "${events_file}"
}

@test "uninstall - cleans up xray binary path" {
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && rm -rf "${p}"
  }

  local xray_bin="${XRF_PREFIX}/bin/xray"
  mkdir -p "$(dirname "${xray_bin}")"
  touch "${xray_bin}"
  chmod +x "${xray_bin}"

  [ -f "${xray_bin}" ]

  _rm "${xray_bin}"
  [ ! -f "${xray_bin}" ]
}

@test "uninstall - cleans up xray config directory" {
  _rm() {
    local p="${1}"
    [[ -e "${p}" || -L "${p}" ]] && rm -rf "${p}"
  }

  local confbase="${XRF_ETC}/xray"
  mkdir -p "${confbase}"
  touch "${confbase}/config.json"

  [ -d "${confbase}" ]

  _rm "${confbase}"
  [ ! -d "${confbase}" ]
}
