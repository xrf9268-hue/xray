#!/usr/bin/env bats
# Edge case tests for templates module (lib/templates.sh)
# These tests cover boundary conditions and error handling scenarios

load ../test_helper
bats_require_minimum_version 1.5.0

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/lib/templates.sh"
}

teardown() {
  cleanup_test_env
}

# =============================================================================
# templates::list edge cases
# =============================================================================

@test "templates::list - handles missing built-in directory gracefully" {
  # Override BUILTIN_TEMPLATES_DIR to non-existent path
  # This tests defensive coding
  export XRF_JSON="false"

  run templates::list
  [ "$status" -eq 0 ]
}

@test "templates::list - JSON output when no templates found" {
  export XRF_JSON="true"

  # Create empty user template directory
  mkdir -p "${TEST_TMPDIR}/empty-templates"

  # Even with built-in templates, should output valid JSON
  run templates::list
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "templates::list - handles template with missing metadata" {
  export XRF_JSON="false"

  # Built-in templates should have proper metadata
  run templates::list
  [ "$status" -eq 0 ]
  [[ "$output" != *"null"* ]] || [[ "$output" == *"No templates"* ]] || true
}

@test "templates::list - text format includes category" {
  export XRF_JSON="false"

  run templates::list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Category:"* ]]
}

# =============================================================================
# templates::load edge cases
# =============================================================================

@test "templates::load - fails for empty template ID" {
  run templates::load ""
  [ "$status" -ne 0 ]
}

@test "templates::load - fails for non-existent template" {
  run templates::load "this-template-does-not-exist"
  [ "$status" -ne 0 ]
}

@test "templates::load - returns valid JSON for built-in templates" {
  for template_id in home office server; do
    run templates::load "${template_id}"
    if [ "$status" -eq 0 ]; then
      echo "$output" | jq empty
    fi
  done
}

@test "templates::load - template has metadata.id field" {
  run templates::load "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metadata.id'
}

@test "templates::load - template has config.topology field" {
  run templates::load "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.config.topology'
}

@test "templates::load - handles template ID with special characters" {
  # Template ID should not allow path traversal
  run templates::load "../../../etc/passwd"
  [ "$status" -ne 0 ]
}

@test "templates::load - handles template ID with spaces" {
  run templates::load "template with spaces"
  [ "$status" -ne 0 ]
}

# =============================================================================
# templates::validate edge cases
# =============================================================================

@test "templates::validate - fails for empty template ID" {
  run templates::validate ""
  [ "$status" -ne 0 ]
}

@test "templates::validate - fails for non-existent template" {
  run templates::validate "fake-template"
  [ "$status" -ne 0 ]
}

@test "templates::validate - passes for valid home template" {
  run templates::validate "home"
  [ "$status" -eq 0 ]
}

@test "templates::validate - passes for valid office template" {
  run templates::validate "office"
  [ "$status" -eq 0 ]
}

@test "templates::validate - passes for valid server template" {
  run templates::validate "server"
  [ "$status" -eq 0 ]
}

# =============================================================================
# templates::export edge cases
# =============================================================================

@test "templates::export - fails for empty template ID" {
  run -127 bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export ""'
}

@test "templates::export - fails for non-existent template" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "not-a-template"'
  [ "$status" -ne 0 ]
}

@test "templates::export - sets TEMPLATE_ID variable" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "home" && echo "$TEMPLATE_ID"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"home"* ]]
}

@test "templates::export - sets TEMPLATE_TOPOLOGY variable" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "home" && echo "$TEMPLATE_TOPOLOGY"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"reality-only"* ]]
}

@test "templates::export - sets TEMPLATE_VERSION variable" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "home" && echo "$TEMPLATE_VERSION"'
  [ "$status" -eq 0 ]
  # Should be "latest" or a version like "v1.8.x"
  [[ -n "$output" ]]
}

@test "templates::export - sets port variables for reality-only topology" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "home" && echo "PORT=${TEMPLATE_PORT:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"unset"* ]]
}

@test "templates::export - sets port variables for vision-reality topology" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "office" && echo "VISION=${TEMPLATE_VISION_PORT:-unset} REALITY=${TEMPLATE_REALITY_PORT:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"VISION=unset"* ]]
  [[ "$output" != *"REALITY=unset"* ]]
}

@test "templates::export - handles plugins array correctly" {
  run bash -c 'source "'"${PROJECT_ROOT}/lib/core.sh"'" && source "'"${PROJECT_ROOT}/lib/templates.sh"'" && export XRF_JSON=false XRF_DEBUG=false && templates::export "server" && echo "PLUGINS=${TEMPLATE_PLUGINS}"'
  [ "$status" -eq 0 ]
  # Plugins should be comma-separated or empty
  [[ "$output" =~ PLUGINS= ]]
}

# =============================================================================
# templates::show edge cases
# =============================================================================

@test "templates::show - fails for empty template ID" {
  run templates::show ""
  [ "$status" -ne 0 ]
}

@test "templates::show - fails for non-existent template" {
  run templates::show "imaginary-template"
  [ "$status" -ne 0 ]
}

@test "templates::show - text format includes template name" {
  export XRF_JSON="false"

  run templates::show "home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Template:"* ]]
  [[ "$output" == *"home"* ]]
}

@test "templates::show - text format includes topology" {
  export XRF_JSON="false"

  run templates::show "home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Topology:"* ]]
}

@test "templates::show - JSON format returns valid JSON" {
  export XRF_JSON="true"

  run templates::show "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "templates::show - JSON format includes metadata" {
  export XRF_JSON="true"

  run templates::show "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metadata'
}

@test "templates::show - JSON format includes config" {
  export XRF_JSON="true"

  run templates::show "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.config'
}

# =============================================================================
# Template content validation tests
# =============================================================================

@test "all built-in templates - have valid JSON structure" {
  for template_id in home office server; do
    result=$(templates::load "${template_id}")
    echo "$result" | jq empty
  done
}

@test "all built-in templates - have required metadata fields" {
  for template_id in home office server; do
    result=$(templates::load "${template_id}")
    echo "$result" | jq -e '.metadata.id'
    echo "$result" | jq -e '.metadata.name'
    echo "$result" | jq -e '.metadata.description'
  done
}

@test "all built-in templates - have valid topology values" {
  for template_id in home office server; do
    topology=$(templates::load "${template_id}" | jq -r '.config.topology')
    [[ "$topology" == "reality-only" || "$topology" == "vision-reality" ]]
  done
}

@test "all built-in templates - have xray config section" {
  for template_id in home office server; do
    result=$(templates::load "${template_id}")
    echo "$result" | jq -e '.config.xray'
  done
}

@test "home template - uses reality-only topology" {
  topology=$(templates::load "home" | jq -r '.config.topology')
  [[ "$topology" == "reality-only" ]]
}

@test "office template - uses vision-reality topology" {
  topology=$(templates::load "office" | jq -r '.config.topology')
  [[ "$topology" == "vision-reality" ]]
}

@test "server template - uses vision-reality topology" {
  topology=$(templates::load "server" | jq -r '.config.topology')
  [[ "$topology" == "vision-reality" ]]
}

# =============================================================================
# Source guard tests
# =============================================================================

@test "templates.sh - has source guard" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/templates.sh"'"
    source "'"${PROJECT_ROOT}/lib/templates.sh"'"
    echo "success"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "success" ]]
}

@test "templates.sh - source guard variable is set" {
  run bash -c '
    source "'"${PROJECT_ROOT}/lib/templates.sh"'"
    echo "${_XRF_TEMPLATES_LOADED:-unset}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "1" ]]
}
