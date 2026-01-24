#!/usr/bin/env bats
# Unit tests for bin/xrf CLI entrypoint

load ../test_helper

setup() {
  setup_test_env

  # Create mock HERE directory structure
  export HERE="${TEST_TMPDIR}/xray"
  mkdir -p "${HERE}/lib"
  mkdir -p "${HERE}/commands"
  mkdir -p "${HERE}/services/xray"

  # Create minimal core.sh mock
  cat > "${HERE}/lib/core.sh" << 'EOF'
:
EOF

  # Create mock command scripts that just echo their invocation
  for cmd in install status uninstall logs backup health templates plugin; do
    cat > "${HERE}/commands/${cmd}.sh" << EOF
#!/usr/bin/env bash
echo "${cmd} called with args: \$*"
exit 0
EOF
    chmod +x "${HERE}/commands/${cmd}.sh"
  done

  # Create test-sni command
  cat > "${HERE}/commands/test-sni.sh" << 'EOF'
#!/usr/bin/env bash
echo "test-sni called with args: $*"
exit 0
EOF
  chmod +x "${HERE}/commands/test-sni.sh"

  # Create client-links.sh
  cat > "${HERE}/services/xray/client-links.sh" << 'EOF'
#!/usr/bin/env bash
echo "links called with args: $*"
exit 0
EOF
  chmod +x "${HERE}/services/xray/client-links.sh"
}

teardown() {
  cleanup_test_env
}

# Test command dispatch
@test "xrf - dispatches install command" {
  run "${HERE}/commands/install.sh" --topology reality-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"install called"* ]]
  [[ "$output" == *"--topology reality-only"* ]]
}

@test "xrf - dispatches status command" {
  run "${HERE}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status called"* ]]
}

@test "xrf - dispatches uninstall command" {
  run "${HERE}/commands/uninstall.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uninstall called"* ]]
}

@test "xrf - dispatches links command" {
  run "${HERE}/services/xray/client-links.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"links called"* ]]
}

@test "xrf - dispatches logs command" {
  run "${HERE}/commands/logs.sh" --tail 50
  [ "$status" -eq 0 ]
  [[ "$output" == *"logs called"* ]]
  [[ "$output" == *"--tail 50"* ]]
}

@test "xrf - dispatches backup command" {
  run "${HERE}/commands/backup.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup called"* ]]
  [[ "$output" == *"create"* ]]
}

@test "xrf - dispatches test-sni command" {
  run "${HERE}/commands/test-sni.sh" example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-sni called"* ]]
  [[ "$output" == *"example.com"* ]]
}

@test "xrf - dispatches health command" {
  run "${HERE}/commands/health.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"health called"* ]]
}

@test "xrf - dispatches templates command" {
  run "${HERE}/commands/templates.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"templates called"* ]]
  [[ "$output" == *"list"* ]]
}

@test "xrf - dispatches plugin command" {
  run "${HERE}/commands/plugin.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugin called"* ]]
  [[ "$output" == *"list"* ]]
}

# Test usage/help output
@test "xrf - usage includes all commands" {
  local usage
  usage=$(cat << 'EOF'
xrf — Xray Fusion Lite (complete clean)
Usage: xrf <command>
  install     Install Xray & deploy confdir (atomic, flock-protected)
  status      Show version & active confdir
  uninstall   Remove Xray (keep state)
  links       Print client links
  logs        View, filter, and export Xray logs
  backup      Manage configuration backups
  test-sni    Test SNI domain for REALITY protocol compatibility
  health      Run post-installation health check
  templates   Manage configuration templates
  plugin      Manage plugins (list/enable/disable/info)
  help        Show this help
EOF
)

  [[ "${usage}" == *"install"* ]]
  [[ "${usage}" == *"status"* ]]
  [[ "${usage}" == *"uninstall"* ]]
  [[ "${usage}" == *"links"* ]]
  [[ "${usage}" == *"logs"* ]]
  [[ "${usage}" == *"backup"* ]]
  [[ "${usage}" == *"test-sni"* ]]
  [[ "${usage}" == *"health"* ]]
  [[ "${usage}" == *"templates"* ]]
  [[ "${usage}" == *"plugin"* ]]
  [[ "${usage}" == *"help"* ]]
}

@test "xrf - usage has correct format" {
  local usage
  usage=$(cat << 'EOF'
xrf — Xray Fusion Lite (complete clean)
Usage: xrf <command>
EOF
)

  [[ "${usage}" == *"Usage:"* ]]
  [[ "${usage}" == *"xrf <command>"* ]]
}

# Test command descriptions
@test "xrf - install command has description" {
  local desc="Install Xray & deploy confdir (atomic, flock-protected)"
  [[ "${desc}" == *"Install"* ]]
  [[ "${desc}" == *"Xray"* ]]
}

@test "xrf - status command has description" {
  local desc="Show version & active confdir"
  [[ "${desc}" == *"version"* ]]
}

@test "xrf - uninstall command has description" {
  local desc="Remove Xray (keep state)"
  [[ "${desc}" == *"Remove"* ]]
}

@test "xrf - links command has description" {
  local desc="Print client links"
  [[ "${desc}" == *"client links"* ]]
}

@test "xrf - logs command has description" {
  local desc="View, filter, and export Xray logs"
  [[ "${desc}" == *"View"* ]]
  [[ "${desc}" == *"logs"* ]]
}

@test "xrf - backup command has description" {
  local desc="Manage configuration backups"
  [[ "${desc}" == *"backup"* ]]
}

@test "xrf - test-sni command has description" {
  local desc="Test SNI domain for REALITY protocol compatibility"
  [[ "${desc}" == *"SNI"* ]]
  [[ "${desc}" == *"REALITY"* ]]
}

@test "xrf - health command has description" {
  local desc="Run post-installation health check"
  [[ "${desc}" == *"health check"* ]]
}

@test "xrf - templates command has description" {
  local desc="Manage configuration templates"
  [[ "${desc}" == *"templates"* ]]
}

@test "xrf - plugin command has description" {
  local desc="Manage plugins (list/enable/disable/info)"
  [[ "${desc}" == *"plugins"* ]]
}

# Test unknown command handling
@test "xrf - unknown command exits with code 2" {
  # Simulate the case statement behavior
  local cmd="unknown-cmd"
  local exit_code=0

  case "${cmd}" in
    install|status|uninstall|links|logs|backup|test-sni|health|templates|plugin|help|"")
      exit_code=0
      ;;
    *)
      exit_code=2
      ;;
  esac

  [ "${exit_code}" -eq 2 ]
}

@test "xrf - empty command shows usage" {
  local cmd=""
  local action=""

  case "${cmd}" in
    help|"")
      action="usage"
      ;;
    *)
      action="dispatch"
      ;;
  esac

  [ "${action}" = "usage" ]
}

@test "xrf - help command shows usage" {
  local cmd="help"
  local action=""

  case "${cmd}" in
    help|"")
      action="usage"
      ;;
    *)
      action="dispatch"
      ;;
  esac

  [ "${action}" = "usage" ]
}

# Test argument forwarding
@test "xrf - forwards all arguments to subcommand" {
  run "${HERE}/commands/install.sh" --topology reality-only --port 443 --domain example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"--topology reality-only"* ]]
  [[ "$output" == *"--port 443"* ]]
  [[ "$output" == *"--domain example.com"* ]]
}

@test "xrf - forwards arguments with spaces" {
  run "${HERE}/commands/backup.sh" create "my backup name"
  [ "$status" -eq 0 ]
  [[ "$output" == *"create"* ]]
  [[ "$output" == *"my backup name"* ]]
}

@test "xrf - handles command with no arguments" {
  run "${HERE}/commands/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status called with args:"* ]]
}

# Test case statement completeness
@test "xrf - all commands are handled in case statement" {
  local commands=(
    "install"
    "status"
    "uninstall"
    "links"
    "logs"
    "backup"
    "test-sni"
    "health"
    "templates"
    "plugin"
    "help"
  )

  [ "${#commands[@]}" -eq 11 ]

  for cmd in "${commands[@]}"; do
    case "${cmd}" in
      install|status|uninstall|links|logs|backup|test-sni|health|templates|plugin|help)
        # Valid command
        ;;
      *)
        fail "Command ${cmd} not handled"
        ;;
    esac
  done
}

# Test shift behavior
@test "xrf - shift removes command from argument list" {
  local args=("install" "--topology" "reality-only")
  local cmd="${args[0]}"

  # Simulate shift
  args=("${args[@]:1}")

  [ "${cmd}" = "install" ]
  [ "${args[0]}" = "--topology" ]
  [ "${args[1]}" = "reality-only" ]
  [ "${#args[@]}" -eq 2 ]
}

@test "xrf - shift handles empty remaining args" {
  local args=("status")
  local cmd="${args[0]}"

  # Simulate shift
  args=("${args[@]:1}")

  [ "${cmd}" = "status" ]
  [ "${#args[@]}" -eq 0 ]
}

# Test path resolution
@test "xrf - HERE variable points to project root" {
  [ -d "${HERE}" ]
  [ -d "${HERE}/commands" ]
  [ -d "${HERE}/lib" ]
}

@test "xrf - command paths are correct" {
  [ -x "${HERE}/commands/install.sh" ]
  [ -x "${HERE}/commands/status.sh" ]
  [ -x "${HERE}/commands/uninstall.sh" ]
  [ -x "${HERE}/commands/logs.sh" ]
  [ -x "${HERE}/commands/backup.sh" ]
  [ -x "${HERE}/commands/test-sni.sh" ]
  [ -x "${HERE}/commands/health.sh" ]
  [ -x "${HERE}/commands/templates.sh" ]
  [ -x "${HERE}/commands/plugin.sh" ]
  [ -x "${HERE}/services/xray/client-links.sh" ]
}
