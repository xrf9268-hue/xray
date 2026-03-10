#!/usr/bin/env bats
# Unit tests for commands/plugin.sh (command wrapper)

load ../test_helper

setup() {
  setup_test_env

  # Create test plugin directories
  export TEST_PLUGINS_DIR="${TEST_TMPDIR}/plugins"
  export XRF_PLUGINS="${TEST_PLUGINS_DIR}"
  mkdir -p "${TEST_PLUGINS_DIR}/available/test-plugin"
  mkdir -p "${TEST_PLUGINS_DIR}/enabled"

  # Create a test plugin
  cat > "${TEST_PLUGINS_DIR}/available/test-plugin/plugin.sh" << 'PLUGIN'
#!/usr/bin/env bash
XRF_PLUGIN_ID="test-plugin"
XRF_PLUGIN_VERSION="1.0.0"
XRF_PLUGIN_DESC="A test plugin"
XRF_PLUGIN_HOOKS=()
PLUGIN
}

teardown() {
  cleanup_test_env
  unset TEST_PLUGINS_DIR XRF_PLUGINS
}

# =============================================================================
# Usage tests
# =============================================================================

@test "plugin command - no subcommand shows usage" {
  run "${PROJECT_ROOT}/commands/plugin.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "plugin command - unknown subcommand shows usage" {
  run "${PROJECT_ROOT}/commands/plugin.sh" unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "plugin command - usage shows all subcommands" {
  run "${PROJECT_ROOT}/commands/plugin.sh"
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"enable"* ]]
  [[ "$output" == *"disable"* ]]
  [[ "$output" == *"info"* ]]
}

# =============================================================================
# list subcommand tests
# =============================================================================

@test "plugin command list - shows available and enabled sections" {
  run "${PROJECT_ROOT}/commands/plugin.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Available:"* ]]
  [[ "$output" == *"Enabled:"* ]]
}

@test "plugin command list - shows test plugin in available" {
  run "${PROJECT_ROOT}/commands/plugin.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-plugin"* ]]
}

# =============================================================================
# enable subcommand tests
# =============================================================================

@test "plugin command enable - enables a plugin" {
  run "${PROJECT_ROOT}/commands/plugin.sh" enable test-plugin
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled: test-plugin"* ]]
  [ -L "${TEST_PLUGINS_DIR}/enabled/test-plugin.sh" ]
}

@test "plugin command enable - missing id fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" enable
  [ "$status" -ne 0 ]
}

@test "plugin command enable - non-existent plugin fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" enable nonexistent
  [ "$status" -ne 0 ]
}

# =============================================================================
# disable subcommand tests
# =============================================================================

@test "plugin command disable - disables an enabled plugin" {
  # First enable
  "${PROJECT_ROOT}/commands/plugin.sh" enable test-plugin
  # Then disable
  run "${PROJECT_ROOT}/commands/plugin.sh" disable test-plugin
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled: test-plugin"* ]]
  [ ! -e "${TEST_PLUGINS_DIR}/enabled/test-plugin.sh" ]
}

@test "plugin command disable - not-enabled plugin fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" disable test-plugin
  [ "$status" -ne 0 ]
}

@test "plugin command disable - missing id fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" disable
  [ "$status" -ne 0 ]
}

# =============================================================================
# info subcommand tests
# =============================================================================

@test "plugin command info - shows plugin details" {
  run "${PROJECT_ROOT}/commands/plugin.sh" info test-plugin
  [ "$status" -eq 0 ]
  [[ "$output" == *"id: test-plugin"* ]]
  [[ "$output" == *"version: 1.0.0"* ]]
  [[ "$output" == *"desc: A test plugin"* ]]
}

@test "plugin command info - non-existent plugin fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" info nonexistent
  [ "$status" -ne 0 ]
}

@test "plugin command info - missing id fails" {
  run "${PROJECT_ROOT}/commands/plugin.sh" info
  [ "$status" -ne 0 ]
}

# =============================================================================
# Security tests
# =============================================================================

@test "plugin command - rejects path traversal in plugin id" {
  run "${PROJECT_ROOT}/commands/plugin.sh" enable "../../../etc/passwd"
  [ "$status" -ne 0 ]
}

@test "plugin command - rejects invalid characters in plugin id" {
  run "${PROJECT_ROOT}/commands/plugin.sh" info "test;rm -rf /"
  [ "$status" -ne 0 ]
}
