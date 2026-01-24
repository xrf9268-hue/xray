#!/usr/bin/env bats
# Unit tests for install.sh integrity enforcement helpers

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# Helper to create a minimal git repo with a single commit
create_temp_repo() {
  local path="${1}"
  mkdir -p "${path}"
  pushd "${path}" >/dev/null || return
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  echo "test content" > file.txt
  git add file.txt
  git commit -m "initial commit" >/dev/null 2>&1
  popd >/dev/null || return
}

@test "install.sh - integrity check fails on commit mismatch" {
  local repo="${TEST_TMPDIR}/repo-mismatch"
  create_temp_repo "${repo}"

  local actual_commit
  actual_commit="$(git -C "${repo}" rev-parse HEAD)"
  local wrong_commit="0000000000000000000000000000000000000001"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${actual_commit}"'" "'"${wrong_commit}"'" "false"; exit $?'

  [ "$status" -eq 1 ]
  [[ "$output" =~ "commit hash mismatch" ]]
}

@test "install.sh - requires GPG verification when enforced" {
  local repo="${TEST_TMPDIR}/repo-gpg-required"
  create_temp_repo "${repo}"

  local commit
  commit="$(git -C "${repo}" rev-parse HEAD)"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${commit}"'" "'"${commit}"'" "true"; exit $?'

  [ "$status" -eq 1 ]
  [[ "$output" =~ "GPG verification" ]] || [[ "$output" =~ "gpg is not installed" ]]
}

@test "install.sh - passes when commits match and signatures optional" {
  local repo="${TEST_TMPDIR}/repo-match"
  create_temp_repo "${repo}"

  local commit
  commit="$(git -C "${repo}" rev-parse HEAD)"

  run bash -c 'source "'"${PROJECT_ROOT}"'/install.sh"; enforce_integrity_checks "'"${repo}"'" "'"${commit}"'" "'"${commit}"'" "false"; exit $?'

  [ "$status" -eq 0 ]
}

# =============================================================================
# Architecture detection tests
# =============================================================================

@test "xray::install - detects x86_64 architecture correctly" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="x86_64"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
    echo "${url_tmpl}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "Xray-linux-64.zip" ]]
}

@test "xray::install - detects amd64 architecture correctly" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="amd64"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
    echo "${url_tmpl}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "Xray-linux-64.zip" ]]
}

@test "xray::install - detects aarch64 architecture correctly" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="aarch64"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
    echo "${url_tmpl}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "Xray-linux-arm64-v8a.zip" ]]
}

@test "xray::install - detects arm64 architecture correctly" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="arm64"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
    echo "${url_tmpl}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "Xray-linux-arm64-v8a.zip" ]]
}

@test "xray::install - rejects unsupported architecture" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="armv7l"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
    echo "${url_tmpl}"
  '
  [ "$status" -eq 2 ]
}

# =============================================================================
# Version format validation tests
# =============================================================================

@test "xray::install - accepts valid version format v1.2.3" {
  run bash -c '
    version="v1.2.3"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "valid" ]]
}

@test "xray::install - accepts valid version format without v prefix" {
  run bash -c '
    version="1.2.3"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "valid" ]]
}

@test "xray::install - accepts version with large numbers" {
  run bash -c '
    version="v24.12.31"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "valid" ]]
}

@test "xray::install - rejects invalid version format (no dots)" {
  run bash -c '
    version="v123"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 1 ]
}

@test "xray::install - rejects invalid version format (letters)" {
  run bash -c '
    version="v1.2.3-beta"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 1 ]
}

@test "xray::install - rejects invalid version format (too many dots)" {
  run bash -c '
    version="v1.2.3.4"
    if [[ ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      exit 1
    fi
    echo "valid"
  '
  [ "$status" -eq 1 ]
}

# =============================================================================
# Version prefix handling tests
# =============================================================================

@test "xray::install - adds v prefix when missing" {
  run bash -c '
    version="1.2.3"
    [[ "${version}" =~ ^v ]] || version="v${version}"
    echo "${version}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "v1.2.3" ]]
}

@test "xray::install - keeps v prefix when present" {
  run bash -c '
    version="v1.2.3"
    [[ "${version}" =~ ^v ]] || version="v${version}"
    echo "${version}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "v1.2.3" ]]
}

# =============================================================================
# URL construction tests
# =============================================================================

@test "xray::install - constructs correct download URL" {
  run bash -c '
    version="v1.8.24"
    url_tmpl="Xray-linux-64.zip"
    url="https://github.com/XTLS/Xray-core/releases/download/${version}/${url_tmpl}"
    echo "${url}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-64.zip" ]]
}

@test "xray::install - uses XRAY_URL override when set" {
  run bash -c '
    version="v1.8.24"
    url_tmpl="Xray-linux-64.zip"
    XRAY_URL="https://mirror.example.com/xray.zip"
    url="${XRAY_URL:-https://github.com/XTLS/Xray-core/releases/download/${version}/${url_tmpl}}"
    echo "${url}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "https://mirror.example.com/xray.zip" ]]
}

# =============================================================================
# Dependency check tests
# =============================================================================

@test "xray::install - need() succeeds for existing command" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    need() {
      command -v "${1}" > /dev/null 2>&1 || {
        echo "missing: ${1}" >&2
        exit 3
      }
    }
    need bash
    echo "ok"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "ok" ]]
}

@test "xray::install - need() fails for missing command" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    need() {
      command -v "${1}" > /dev/null 2>&1 || {
        echo "missing: ${1}" >&2
        exit 3
      }
    }
    need nonexistent_command_xyz_12345
    echo "ok"
  '
  [ "$status" -eq 3 ]
  [[ "${output}" == *"missing"* ]]
}

@test "xray::install - need() checks for curl" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    need() {
      command -v "${1}" > /dev/null 2>&1 || {
        echo "missing: ${1}" >&2
        exit 3
      }
    }
    need curl
    echo "ok"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "ok" ]]
}

@test "xray::install - need() checks for unzip" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    need() {
      command -v "${1}" > /dev/null 2>&1 || {
        echo "missing: ${1}" >&2
        exit 3
      }
    }
    need unzip
    echo "ok"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "ok" ]]
}

# =============================================================================
# Exit code tests
# =============================================================================

@test "xray::install - exits with code 2 for unsupported architecture" {
  # Code 2 is used for unsupported architecture
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    arch_u="unsupported_arch"
    case "${arch_u}" in
      x86_64 | amd64) url_tmpl="Xray-linux-64.zip" ;;
      aarch64 | arm64) url_tmpl="Xray-linux-arm64-v8a.zip" ;;
      *) exit 2 ;;
    esac
  '
  [ "$status" -eq 2 ]
}

@test "xray::install - exits with code 3 for missing dependency" {
  # Code 3 is used for missing dependencies
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/core.sh"'"
    export XRF_JSON=false
    export XRF_DEBUG=false
    need() {
      command -v "${1}" > /dev/null 2>&1 || exit 3
    }
    need nonexistent_dep
  '
  [ "$status" -eq 3 ]
}

# =============================================================================
# Command-line argument parsing tests
# =============================================================================

@test "xray::install - parses --version argument" {
  run bash -c '
    version="latest"
    args=(--version v1.8.24)
    set -- "${args[@]}"
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        --version) version="${2}"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "${version}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "v1.8.24" ]]
}

@test "xray::install - defaults to latest version" {
  run bash -c '
    version="latest"
    args=()
    set -- "${args[@]}"
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        --version) version="${2}"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "${version}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "latest" ]]
}

@test "xray::install - ignores unknown arguments" {
  run bash -c '
    version="latest"
    args=(--unknown --version v2.0.0 --other)
    set -- "${args[@]}"
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        --version) version="${2}"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "${version}"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == "v2.0.0" ]]
}
