#!/usr/bin/env bats
# Integration test for install flow

load test_helper

setup() {
  setup_integration_env
}

teardown() {
  cleanup_integration_env
}

@test "install flow - reality-only topology completes successfully" {
  skip "Requires xray binary - implement in CI environment"

  run bin/xrf install --topology reality-only
  [ "$status" -eq 0 ]

  # Verify configuration files created
  [ -d "${XRF_ETC}/xray/releases" ]

  # Verify state saved
  [ -f "${XRF_VAR}/state.json" ]

  # Verify systemctl called
  [ -f "${XRF_VAR}/systemctl.log" ]
  grep -q "enable --now xray" "${XRF_VAR}/systemctl.log"
}

@test "install flow - vision-reality requires domain" {
  run bin/xrf install --topology vision-reality
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required parameter"* ]]
  [[ "$output" == *"--domain"* ]]
}

@test "install flow - invalid topology rejected" {
  run bin/xrf install --topology invalid-topo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid topology"* ]]
  [[ "$output" == *"invalid-topo"* ]]
}
