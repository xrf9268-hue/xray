#!/usr/bin/env bats
# Unit tests for lib/dependencies.sh

load '../test_helper'

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

create_fake_cmd() {
  local dir="${1}"
  local name="${2}"
  local body="${3}"

  mkdir -p "${dir}"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "${body}"
  } > "${dir}/${name}"
  chmod +x "${dir}/${name}"
}

# =============================================================================
# deps::check_critical
# =============================================================================

@test "deps::check_critical - succeeds when all tools available" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  # macOS test environments may not ship systemctl; provide a lightweight stub.
  local fake_bin="${TEST_TMPDIR}/bin"
  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/systemctl" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/systemctl"
  export PATH="${fake_bin}:${PATH}"

  run deps::check_critical
  [ "$status" -eq 0 ]
}

@test "deps::check_critical - detects when no downloader available" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  # Mock command to report all downloaders missing
  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      curl|wget|git) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "download tool" ]]

  unset -f command
}

@test "deps::check_critical - succeeds with only git" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        git|systemctl|mktemp|tar|gzip) return 0 ;;
        curl|wget) return 1 ;;
        *) return 0 ;;
      esac
    fi
    builtin command "$@" 2>/dev/null
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 0 ]

  unset -f command
}

@test "deps::check_critical - succeeds with only curl" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        curl|systemctl|mktemp|tar|gzip) return 0 ;;
        git|wget) return 1 ;;
        *) return 0 ;;
      esac
    fi
    builtin command "$@" 2>/dev/null
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 0 ]

  unset -f command
}

@test "deps::check_critical - succeeds with only wget" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        wget|systemctl|mktemp|tar|gzip) return 0 ;;
        git|curl) return 1 ;;
        *) return 0 ;;
      esac
    fi
    builtin command "$@" 2>/dev/null
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 0 ]

  unset -f command
}

@test "deps::check_critical - detects missing systemctl" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      systemctl) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "systemctl" ]]

  unset -f command
}

@test "deps::check_critical - detects missing tar" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      tar) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "tar" ]]

  unset -f command
}

@test "deps::check_critical - detects missing mktemp" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      mktemp) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "mktemp" ]]

  unset -f command
}

@test "deps::check_critical - detects missing gzip" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      gzip) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "gzip" ]]

  unset -f command
}

@test "deps::check_critical - detects multiple missing tools" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      tar|mktemp) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_critical
  [ "$status" -eq 1 ]
  [[ "$output" =~ "tar" ]]
  [[ "$output" =~ "mktemp" ]]

  unset -f command
}

# =============================================================================
# deps::check_optional
# =============================================================================

@test "deps::check_optional - always succeeds" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  run deps::check_optional
  [ "$status" -eq 0 ]
}

@test "deps::check_optional - warns about missing jq" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      jq) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_optional
  [ "$status" -eq 0 ]
  [[ "$output" =~ "jq" ]] || [[ "$output" =~ "optional" ]]

  unset -f command
}

@test "deps::check_optional - warns about missing openssl" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      openssl) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_optional
  [ "$status" -eq 0 ]
  [[ "$output" =~ "openssl" ]] || [[ "$output" =~ "optional" ]]

  unset -f command
}

@test "deps::check_optional - warns about missing gpg" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      gpg) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_optional
  [ "$status" -eq 0 ]
  [[ "$output" =~ "gpg" ]] || [[ "$output" =~ "optional" ]]

  unset -f command
}

@test "deps::check_optional - warns about multiple missing optional tools" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    builtin command "$@" 2>/dev/null || return 1
    case "${2}" in
      jq|openssl|gpg) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f command

  run deps::check_optional
  [ "$status" -eq 0 ]
  [[ "$output" =~ "jq" ]] || [[ "$output" =~ "optional" ]]
  [[ "$output" =~ "openssl" ]] || [[ "$output" =~ "optional" ]]
  [[ "$output" =~ "gpg" ]] || [[ "$output" =~ "optional" ]]

  unset -f command
}

@test "deps::check_optional - succeeds silently when all tools present" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  # Assume test environment has these tools
  if command -v jq >/dev/null 2>&1 && \
     command -v openssl >/dev/null 2>&1 && \
     command -v gpg >/dev/null 2>&1; then
    run deps::check_optional
    [ "$status" -eq 0 ]
    # Should have no warnings if all tools present
  else
    skip "Test environment missing some optional tools"
  fi
}

# =============================================================================
# deps::print_install_help
# =============================================================================

@test "deps::print_install_help - maps systemctl to systemd across package managers" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  run deps::print_install_help "curl" "systemctl" "tar"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Missing tools: curl systemctl tar" ]]
  [[ "$output" =~ "apt-get install -y curl systemd tar" ]]
  [[ "$output" =~ "yum install -y curl systemd tar" ]]
  [[ "$output" =~ "pacman -S curl systemd tar" ]]
}

# =============================================================================
# deps::detect_package_manager
# =============================================================================

@test "deps::detect_package_manager - returns first supported manager in priority order" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/bin"
  create_fake_cmd "${fake_bin}" "apt-get" 'exit 0'
  create_fake_cmd "${fake_bin}" "dnf" 'exit 0'
  export PATH="${fake_bin}:${PATH}"

  run deps::detect_package_manager
  [ "$status" -eq 0 ]
  [ "$output" = "apt-get" ]
}

@test "deps::detect_package_manager - uses cached manager when available" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  _XRF_DETECTED_PM="cached-manager"
  run deps::detect_package_manager
  [ "$status" -eq 0 ]
  [ "$output" = "cached-manager" ]
}

@test "deps::detect_package_manager - returns failure when no supported manager exists" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        apt-get|dnf|yum|apk|zypper|pacman) return 1 ;;
        *) ;;
      esac
    fi
    builtin command "$@" 2>/dev/null
  }
  export -f command

  run deps::detect_package_manager
  [ "$status" -eq 1 ]

  unset -f command
}

# =============================================================================
# deps::install_packages
# =============================================================================

@test "deps::install_packages - succeeds when package list is empty" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  run deps::install_packages
  [ "$status" -eq 0 ]
}

@test "deps::install_packages - fails when no package manager is detected" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  deps::detect_package_manager() {
    return 1
  }

  run deps::install_packages "curl"
  [ "$status" -eq 1 ]
}

@test "deps::install_packages - runs apt-get directly when sudo is unavailable" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/bin"
  local cmd_log="${TEST_TMPDIR}/apt-get.log"
  create_fake_cmd "${fake_bin}" "apt-get" "printf '%s\\n' \"\$*\" > \"${cmd_log}\""
  export PATH="${fake_bin}:${PATH}"

  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "sudo" ]]; then
      return 1
    fi
    builtin command "$@" 2>/dev/null
  }
  export -f command

  deps::detect_package_manager() {
    echo "apt-get"
  }

  run deps::install_packages "curl" "jq"
  [ "$status" -eq 0 ]
  [ -f "${cmd_log}" ]
  run cat "${cmd_log}"
  [ "$status" -eq 0 ]
  [ "$output" = "install -y curl jq" ]

  unset -f command
}

@test "deps::install_packages - prefixes sudo when available and not root" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  if [[ "${EUID}" -eq 0 ]]; then
    skip "requires non-root user to verify sudo path"
  fi

  local fake_bin="${TEST_TMPDIR}/bin"
  local sudo_log="${TEST_TMPDIR}/sudo.log"
  local apt_log="${TEST_TMPDIR}/apt-get.log"
  create_fake_cmd "${fake_bin}" "apt-get" "printf '%s\\n' \"\$*\" > \"${apt_log}\""
  create_fake_cmd "${fake_bin}" "sudo" "printf '%s\\n' \"\$*\" > \"${sudo_log}\"; \"\$@\""
  export PATH="${fake_bin}:${PATH}"

  deps::detect_package_manager() {
    echo "apt-get"
  }

  run deps::install_packages "curl"
  [ "$status" -eq 0 ]
  run cat "${sudo_log}"
  [ "$status" -eq 0 ]
  [ "$output" = "apt-get install -y curl" ]
  run cat "${apt_log}"
  [ "$status" -eq 0 ]
  [ "$output" = "install -y curl" ]
}

@test "deps::install_packages - returns failure when package command fails" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/bin"
  create_fake_cmd "${fake_bin}" "apt-get" "exit 42"
  export PATH="${fake_bin}:${PATH}"

  deps::detect_package_manager() {
    echo "apt-get"
  }

  run deps::install_packages "curl"
  [ "$status" -eq 1 ]
}

@test "deps::install_packages - fails for unsupported package manager value" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  deps::detect_package_manager() {
    echo "unknown-pm"
  }

  run deps::install_packages "curl"
  [ "$status" -eq 1 ]
}

# =============================================================================
# deps::check_and_install_plugin_deps
# =============================================================================

@test "deps::check_and_install_plugin_deps - succeeds when no deps declared" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  run deps::check_and_install_plugin_deps "demo-plugin"
  [ "$status" -eq 0 ]
}

@test "deps::check_and_install_plugin_deps - succeeds when all deps already installed" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/bin"
  create_fake_cmd "${fake_bin}" "dep-ok" "exit 0"
  export PATH="${fake_bin}:${PATH}"

  run deps::check_and_install_plugin_deps "demo-plugin" "dep-ok"
  [ "$status" -eq 0 ]
}

@test "deps::check_and_install_plugin_deps - auto-installs missing deps in non-interactive mode" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/empty-bin"
  local install_log="${TEST_TMPDIR}/install.log"
  mkdir -p "${fake_bin}"
  export PATH="${fake_bin}:${PATH}"
  unset XRF_AUTO_INSTALL_DEPS

  deps::install_packages() {
    printf '%s\n' "$*" > "${install_log}"
    return 0
  }

  run deps::check_and_install_plugin_deps "demo-plugin" "dep-a" "dep-b"
  [ "$status" -eq 0 ]
  run cat "${install_log}"
  [ "$status" -eq 0 ]
  [ "$output" = "dep-a dep-b" ]
}

@test "deps::check_and_install_plugin_deps - returns failure when auto-install fails" {
  source "${PROJECT_ROOT}/lib/dependencies.sh"

  local fake_bin="${TEST_TMPDIR}/empty-bin"
  local install_log="${TEST_TMPDIR}/install.log"
  mkdir -p "${fake_bin}"
  export PATH="${fake_bin}:${PATH}"
  export XRF_AUTO_INSTALL_DEPS="true"

  deps::install_packages() {
    printf '%s\n' "$*" > "${install_log}"
    return 1
  }

  run deps::check_and_install_plugin_deps "demo-plugin" "dep-a"
  [ "$status" -eq 1 ]
  run cat "${install_log}"
  [ "$status" -eq 0 ]
  [ "$output" = "dep-a" ]
}
