#!/usr/bin/env bats
# Unit tests for lib/dependencies.sh

load '../test_helper'

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
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
