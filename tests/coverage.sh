#!/usr/bin/env bash
# Coverage analysis script for xray-fusion
# Usage: bash tests/coverage.sh generate

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# List of modules to analyze
MODULES=(
  "lib/args.sh"
  "lib/backup.sh"
  "lib/core.sh"
  "lib/defaults.sh"
  "lib/dependencies.sh"
  "lib/download.sh"
  "lib/error_codes.sh"
  "lib/errors.sh"
  "lib/health_check.sh"
  "lib/logs.sh"
  "lib/network.sh"
  "lib/plugins.sh"
  "lib/preview.sh"
  "lib/sni_validator.sh"
  "lib/templates.sh"
  "lib/uuid.sh"
  "lib/validators.sh"
  "lib/x25519.sh"
  "modules/io.sh"
  "modules/state.sh"
  "modules/fw/fw.sh"
  "modules/fw/ufw.sh"
  "modules/fw/firewalld.sh"
  "modules/web/caddy.sh"
  "services/xray/common.sh"
  "services/xray/configure.sh"
  "services/xray/install_utils.sh"
)

count_functions() {
  local file="${1}"
  grep -cE '^[a-zA-Z_][a-zA-Z0-9_:]*\s*\(\)\s*\{?' "${file}" 2> /dev/null || echo 0
}

list_functions() {
  local file="${1}"
  grep -oE '^[a-zA-Z_][a-zA-Z0-9_:]*\s*\(\)' "${file}" 2> /dev/null | sed 's/()//' || true
}

find_test_file() {
  local module="${1}"
  local basename="${module##*/}"
  basename="${basename%.sh}"

  # Special mappings for modules that don't follow naming convention
  case "${module}" in
    "modules/fw/"*) basename="firewall" ;;
    "services/xray/common.sh") basename="xray_paths" ;;
  esac

  for testfile in "${PROJECT_ROOT}"/tests/unit/*.bats; do
    testname="${testfile##*/}"
    if [[ "${testname}" == *"${basename}"* ]]; then
      echo "${testfile}"
      return 0
    fi
  done
  echo ""
}

count_tests() {
  local testfile="${1}"
  if [[ -f "${testfile}" ]]; then
    grep -cE '^@test' "${testfile}" 2> /dev/null || echo 0
  else
    echo 0
  fi
}

generate_report() {
  local total_funcs=0
  local tested_funcs=0
  local total_tests=0

  echo "=============================================="
  echo "         Xray-Fusion Coverage Report"
  echo "=============================================="
  echo ""
  printf "%-40s %6s %6s %8s\n" "Module" "Funcs" "Tests" "Status"
  echo "----------------------------------------------"

  for module in "${MODULES[@]}"; do
    local modpath="${PROJECT_ROOT}/${module}"
    [[ -f "${modpath}" ]] || continue

    local funcs testfile tests
    funcs=$(count_functions "${modpath}")
    testfile=$(find_test_file "${module}")
    tests=$(count_tests "${testfile}")

    total_funcs=$((total_funcs + funcs))
    total_tests=$((total_tests + tests))

    local status="NO TEST"
    if [[ -n "${testfile}" ]]; then
      if [[ ${tests} -ge ${funcs} ]]; then
        status="FULL"
        tested_funcs=$((tested_funcs + funcs))
      elif [[ ${tests} -gt 0 ]]; then
        status="PARTIAL"
        tested_funcs=$((tested_funcs + tests))
      fi
    fi

    printf "%-40s %6d %6d %8s\n" "${module}" "${funcs}" "${tests}" "${status}"
  done

  echo "----------------------------------------------"
  printf "%-40s %6d %6d\n" "TOTAL" "${total_funcs}" "${total_tests}"
  echo ""

  if [[ ${total_funcs} -gt 0 ]]; then
    local coverage=$((total_tests * 100 / total_funcs))
    echo "Estimated Coverage: ${coverage}%"
    echo "Target: 95%"
    echo ""
    if [[ ${coverage} -ge 95 ]]; then
      echo "✅ Coverage target met!"
    else
      local needed=$((total_funcs * 95 / 100 - total_tests))
      echo "⚠️  Need ~${needed} more tests to reach 95%"
    fi
  fi
}

case "${1:-}" in
  generate)
    generate_report
    ;;
  list)
    for module in "${MODULES[@]}"; do
      modpath="${PROJECT_ROOT}/${module}"
      [[ -f "${modpath}" ]] || continue
      echo "=== ${module} ==="
      list_functions "${modpath}"
      echo ""
    done
    ;;
  *)
    echo "Usage: ${0} {generate|list}"
    exit 1
    ;;
esac
