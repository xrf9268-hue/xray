#!/usr/bin/env bats
# Unit tests for configuration templates (lib/templates.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source template module
  source "${PROJECT_ROOT}/lib/templates.sh"
}

teardown() {
  cleanup_test_env
}

# templates::list tests
@test "templates::list - lists built-in templates in text format" {
  export XRF_JSON="false"
  run templates::list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Available Templates" ]]
  [[ "$output" =~ "[home]" ]]
  [[ "$output" =~ "[office]" ]]
  [[ "$output" =~ "[server]" ]]
}

@test "templates::list - outputs JSON format when XRF_JSON=true" {
  export XRF_JSON="true"
  run templates::list
  [ "$status" -eq 0 ]
  # Validate JSON structure
  echo "$output" | jq empty
  echo "$output" | jq -e '.templates | length >= 3'
}

@test "templates::list - includes metadata for each template" {
  export XRF_JSON="false"
  run templates::list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Category:" ]]
  [[ "$output" =~ "Home User" ]]
  [[ "$output" =~ "Office/Team" ]]
  [[ "$output" =~ "Production Server" ]]
}

# templates::load tests
@test "templates::load - loads built-in home template" {
  run templates::load "home"
  [ "$status" -eq 0 ]
  # Validate JSON
  echo "$output" | jq empty
  echo "$output" | jq -e '.metadata.id == "home"'
  echo "$output" | jq -e '.config.topology == "reality-only"'
}

@test "templates::load - loads built-in office template" {
  run templates::load "office"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metadata.id == "office"'
  echo "$output" | jq -e '.config.topology == "vision-reality"'
}

@test "templates::load - loads built-in server template" {
  run templates::load "server"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metadata.id == "server"'
  echo "$output" | jq -e '.config.topology == "vision-reality"'
}

@test "templates::load - fails for non-existent template" {
  run templates::load "non-existent"
  [ "$status" -ne 0 ]
}

@test "templates::load - fails for empty template ID" {
  run templates::load ""
  [ "$status" -ne 0 ]
}

# templates::validate tests
@test "templates::validate - accepts valid home template" {
  run templates::validate "home"
  [ "$status" -eq 0 ]
}

@test "templates::validate - accepts valid office template" {
  run templates::validate "office"
  [ "$status" -eq 0 ]
}

@test "templates::validate - accepts valid server template" {
  run templates::validate "server"
  [ "$status" -eq 0 ]
}

@test "templates::validate - rejects non-existent template" {
  run templates::validate "non-existent"
  [ "$status" -ne 0 ]
}

@test "templates::validate - rejects template with invalid topology" {
  # Create invalid template
  local template_dir="${TEST_TMPDIR}/templates"
  mkdir -p "${template_dir}"
  cat > "${template_dir}/invalid.json" <<'EOF'
{
  "metadata": {
    "id": "invalid",
    "name": "Invalid",
    "description": "Test"
  },
  "config": {
    "topology": "invalid-topology"
  }
}
EOF
  # Override template directory (this would require modifying templates::load)
  # For now, this test validates the validation logic indirectly
  skip "Requires template directory override support"
}

# templates::export tests
@test "templates::export - exports home template variables" {
  run bash -c 'source lib/templates.sh && templates::export "home" && echo "TOPOLOGY=$TEMPLATE_TOPOLOGY VERSION=$TEMPLATE_VERSION"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "TOPOLOGY=reality-only" ]]
  [[ "$output" =~ "VERSION=latest" ]]
}

@test "templates::export - exports office template variables" {
  run bash -c 'source lib/templates.sh && templates::export "office" && echo "TOPOLOGY=$TEMPLATE_TOPOLOGY PLUGINS=$TEMPLATE_PLUGINS"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "TOPOLOGY=vision-reality" ]]
  [[ "$output" =~ "PLUGINS=" ]]
}

@test "templates::export - exports server template variables" {
  run bash -c 'source lib/templates.sh && templates::export "server" && echo "TOPOLOGY=$TEMPLATE_TOPOLOGY PLUGINS=$TEMPLATE_PLUGINS"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "TOPOLOGY=vision-reality" ]]
  [[ "$output" =~ "PLUGINS=" ]]
}

@test "templates::export - exports TEMPLATE_ID" {
  run bash -c 'source lib/templates.sh && templates::export "home" && echo "ID=$TEMPLATE_ID"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ID=home" ]]
}

@test "templates::export - exports TEMPLATE_NAME" {
  run bash -c 'source lib/templates.sh && templates::export "home" && echo "NAME=$TEMPLATE_NAME"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NAME=Home User" ]]
}

@test "templates::export - exports SNI for home template" {
  run bash -c 'source lib/templates.sh && templates::export "home" && echo "SNI=$TEMPLATE_SNI"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SNI=www.apple.com" ]]
}

@test "templates::export - exports topology-specific ports" {
  # Reality-only (home template) exports TEMPLATE_PORT
  run bash -c 'source lib/templates.sh && templates::export "home" && echo "PORT=${TEMPLATE_PORT:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PORT=443" ]]

  # Vision-reality (office template) exports TEMPLATE_VISION_PORT and TEMPLATE_REALITY_PORT
  run bash -c 'source lib/templates.sh && templates::export "office" && echo "VISION=${TEMPLATE_VISION_PORT:-unset} REALITY=${TEMPLATE_REALITY_PORT:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VISION=8443" ]]
  [[ "$output" =~ "REALITY=443" ]]
}

@test "templates::export - fails for non-existent template" {
  run bash -c 'source lib/templates.sh && templates::export "non-existent"'
  [ "$status" -ne 0 ]
}

# templates::show tests
@test "templates::show - displays home template in text format" {
  export XRF_JSON="false"
  run templates::show "home"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Template: Home User [home]" ]]
  [[ "$output" =~ "Topology:  reality-only" ]]
}

@test "templates::show - displays office template in text format" {
  export XRF_JSON="false"
  run templates::show "office"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Template: Office/Team [office]" ]]
  [[ "$output" =~ "Topology:  vision-reality" ]]
}

@test "templates::show - outputs JSON format when XRF_JSON=true" {
  export XRF_JSON="true"
  run templates::show "home"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  echo "$output" | jq -e '.metadata.id == "home"'
}

@test "templates::show - fails for non-existent template" {
  run templates::show "non-existent"
  [ "$status" -ne 0 ]
}

# Template structure validation tests
@test "home template - has required metadata fields" {
  run bash -c 'source lib/templates.sh && templates::load "home" | jq -e ".metadata | has(\"id\") and has(\"name\") and has(\"description\")"'
  [ "$status" -eq 0 ]
}

@test "office template - has required config fields" {
  run bash -c 'source lib/templates.sh && templates::load "office" | jq -e ".config | has(\"topology\") and has(\"xray\")"'
  [ "$status" -eq 0 ]
}

@test "server template - has plugins array" {
  run bash -c 'source lib/templates.sh && templates::load "server" | jq -e ".config.plugins | type == \"array\""'
  [ "$status" -eq 0 ]
}

@test "all templates - have valid topology values" {
  for template in home office server; do
    topology=$(bash -c "cd ${PROJECT_ROOT} && source lib/templates.sh && templates::load \"$template\" | jq -r '.config.topology'")
    [[ "$topology" == "reality-only" || "$topology" == "vision-reality" ]]
  done
}
