#!/usr/bin/env bats
# Unit tests for commands/status.sh

load ../test_helper

setup() {
  setup_test_env
  mkdir -p "${XRF_PREFIX}/bin"
  mkdir -p "${XRF_ETC}/xray/active"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# Basic execution tests
# =============================================================================

@test "status command - runs without error when xray binary exists" {
  cat > "${XRF_PREFIX}/bin/xray" << 'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "Xray v1.8.24 (Xray, Penetrates Everything.)"
fi
SCRIPT
  chmod +x "${XRF_PREFIX}/bin/xray"

  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
}

@test "status command - reports version from xray binary" {
  cat > "${XRF_PREFIX}/bin/xray" << 'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "Xray v1.8.24 (Xray, Penetrates Everything.)"
fi
SCRIPT
  chmod +x "${XRF_PREFIX}/bin/xray"

  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.8.24"* ]]
}

@test "status command - reports unknown when xray binary missing" {
  # No xray binary installed
  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

@test "status command - reports active confdir" {
  cat > "${XRF_PREFIX}/bin/xray" << 'SCRIPT'
#!/usr/bin/env bash
echo "Xray v1.8.24"
SCRIPT
  chmod +x "${XRF_PREFIX}/bin/xray"

  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"active"* ]]
}

@test "status command - handles non-executable xray binary" {
  echo "not-executable" > "${XRF_PREFIX}/bin/xray"
  # Don't chmod +x

  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

@test "status command - handles xray version fallback" {
  # Binary that only responds to "version" not "-version"
  cat > "${XRF_PREFIX}/bin/xray" << 'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "version" ]]; then
  echo "Xray v24.11.30"
elif [[ "${1:-}" == "-version" ]]; then
  exit 1
fi
SCRIPT
  chmod +x "${XRF_PREFIX}/bin/xray"

  run "${PROJECT_ROOT}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"24.11.30"* ]]
}
