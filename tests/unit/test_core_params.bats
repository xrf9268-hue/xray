#!/usr/bin/env bats
# Unit tests for core::require_param and core::require_params functions

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# core::require_param tests

@test "core::require_param - returns 0 for non-empty value" {
  run core::require_param "value" "test_param"
  [ "$status" -eq 0 ]
}

@test "core::require_param - returns 1 for empty value" {
  run core::require_param "" "test_param"
  [ "$status" -eq 1 ]
}

@test "core::require_param - returns 1 for unset value" {
  unset my_var
  run core::require_param "${my_var:-}" "test_param"
  [ "$status" -eq 1 ]
}

@test "core::require_param - logs error with parameter name" {
  run core::require_param "" "my_domain"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required parameter"* ]]
  [[ "$output" == *"my_domain"* ]]
}

@test "core::require_param - logs error with context when provided" {
  run core::require_param "" "port" "install"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
  [[ "$output" == *"install"* ]]
}

@test "core::require_param - no output on success" {
  run core::require_param "valid" "test"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "core::require_param - handles whitespace-only value as non-empty" {
  # Whitespace is technically not empty
  run core::require_param " " "test"
  [ "$status" -eq 0 ]
}

@test "core::require_param - handles special characters in value" {
  run core::require_param 'value with "quotes"' "test"
  [ "$status" -eq 0 ]
}

@test "core::require_param - JSON escapes parameter name in error" {
  XRF_JSON=true
  run core::require_param "" 'param"with"quotes'
  [ "$status" -eq 1 ]
  # Should be valid JSON
  [[ "$output" == *'"param":'* ]]
}

# core::require_params tests

@test "core::require_params - returns 0 when all params valid" {
  run core::require_params "domain=example.com" "port=443"
  [ "$status" -eq 0 ]
}

@test "core::require_params - returns 1 when first param empty" {
  run core::require_params "domain=" "port=443"
  [ "$status" -eq 1 ]
  [[ "$output" == *"domain"* ]]
}

@test "core::require_params - returns 1 when second param empty" {
  run core::require_params "domain=example.com" "port="
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}

@test "core::require_params - returns 1 when middle param empty" {
  run core::require_params "a=1" "b=" "c=3"
  [ "$status" -eq 1 ]
  [[ "$output" == *"b"* ]]
}

@test "core::require_params - handles single param" {
  run core::require_params "domain=example.com"
  [ "$status" -eq 0 ]
}

@test "core::require_params - handles value with equals sign" {
  run core::require_params "equation=a=b"
  [ "$status" -eq 0 ]
}

@test "core::require_params - fails on value with only equals" {
  run core::require_params "empty="
  [ "$status" -eq 1 ]
}

@test "core::require_params - no output on success" {
  run core::require_params "a=1" "b=2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Integration pattern tests

@test "require_param pattern - typical function validation" {
  my_function() {
    local domain="${1:-}"
    local port="${2:-}"

    core::require_param "${domain}" "domain" "my_function" || return 1
    core::require_param "${port}" "port" "my_function" || return 1

    echo "success"
  }

  run my_function "example.com" "443"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]
}

@test "require_param pattern - fails early on missing first param" {
  my_function() {
    local domain="${1:-}"
    local port="${2:-}"

    core::require_param "${domain}" "domain" "my_function" || return 1
    core::require_param "${port}" "port" "my_function" || return 1

    echo "success"
  }

  run my_function "" "443"
  [ "$status" -eq 1 ]
  [[ "$output" == *"domain"* ]]
  [[ "$output" != *"success"* ]]
}

@test "require_params pattern - bulk validation" {
  my_function() {
    local domain="${1:-}"
    local port="${2:-}"
    local user="${3:-}"

    core::require_params \
      "domain=${domain}" \
      "port=${port}" \
      "user=${user}" || return 1

    echo "success"
  }

  run my_function "example.com" "443" "admin"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]
}

@test "require_params pattern - fails on any missing" {
  my_function() {
    local domain="${1:-}"
    local port="${2:-}"
    local user="${3:-}"

    core::require_params \
      "domain=${domain}" \
      "port=${port}" \
      "user=${user}" || return 1

    echo "success"
  }

  run my_function "example.com" "" "admin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}
