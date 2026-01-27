#!/usr/bin/env bats
# Unit tests for core::json_escape function

load ../test_helper

setup() {
  setup_test_env
}

teardown() {
  cleanup_test_env
}

# Basic functionality tests

@test "core::json_escape - returns empty string for empty input" {
  run core::json_escape ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "core::json_escape - passes through plain text unchanged" {
  run core::json_escape "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "core::json_escape - passes through alphanumeric unchanged" {
  run core::json_escape "abc123XYZ"
  [ "$status" -eq 0 ]
  [ "$output" = "abc123XYZ" ]
}

# Quote escaping tests

@test "core::json_escape - escapes double quotes" {
  run core::json_escape 'hello "world"'
  [ "$status" -eq 0 ]
  [ "$output" = 'hello \"world\"' ]
}

@test "core::json_escape - escapes multiple quotes" {
  run core::json_escape '"a" "b" "c"'
  [ "$status" -eq 0 ]
  [ "$output" = '\"a\" \"b\" \"c\"' ]
}

# Backslash escaping tests

@test "core::json_escape - escapes backslashes" {
  run core::json_escape 'path\to\file'
  [ "$status" -eq 0 ]
  [ "$output" = 'path\\to\\file' ]
}

@test "core::json_escape - escapes multiple backslashes" {
  run core::json_escape 'a\\b\\c'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\\\\b\\\\c' ]
}

# Whitespace character escaping tests

@test "core::json_escape - escapes newlines" {
  input=$'line1\nline2'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'line1\nline2' ]
}

@test "core::json_escape - escapes carriage returns" {
  input=$'line1\rline2'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'line1\rline2' ]
}

@test "core::json_escape - escapes tabs" {
  input=$'col1\tcol2'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'col1\tcol2' ]
}

@test "core::json_escape - escapes CRLF (Windows line endings)" {
  input=$'line1\r\nline2'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'line1\r\nline2' ]
}

# Mixed character tests

@test "core::json_escape - handles mixed special characters" {
  input=$'say "hello"\nworld'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'say \"hello\"\nworld' ]
}

@test "core::json_escape - handles backslash before quote" {
  input='path\"file'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = 'path\\\"file' ]
}

# Control character tests

@test "core::json_escape - escapes null character as unicode" {
  # Create string with null-like control character (using \x01 as \x00 is tricky in bash)
  input=$'\x01'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = '\u0001' ]
}

@test "core::json_escape - escapes bell character as unicode" {
  input=$'\x07'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = '\u0007' ]
}

@test "core::json_escape - escapes form feed as unicode" {
  input=$'\x0c'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = '\u000c' ]
}

# JSON validity tests

@test "core::json_escape - output creates valid JSON string" {
  input='test "quoted" and\backslash'
  escaped=$(core::json_escape "${input}")
  # Construct JSON and verify with jq
  json=$(printf '{"msg":"%s"}' "${escaped}")
  run bash -c "echo '${json}' | jq -e '.msg' > /dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "core::json_escape - multiline input creates valid JSON" {
  input=$'line1\nline2\nline3'
  escaped=$(core::json_escape "${input}")
  json=$(printf '{"msg":"%s"}' "${escaped}")
  run bash -c "echo '${json}' | jq -e '.msg' > /dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "core::json_escape - complex input creates valid JSON" {
  input=$'Command: rm -rf "test"\nPath: /tmp\\test'
  escaped=$(core::json_escape "${input}")
  json=$(printf '{"msg":"%s"}' "${escaped}")
  run bash -c "echo '${json}' | jq -e '.msg' > /dev/null 2>&1"
  [ "$status" -eq 0 ]
}

# Edge case tests

@test "core::json_escape - handles unicode characters" {
  run core::json_escape "Hello 世界"
  [ "$status" -eq 0 ]
  [ "$output" = "Hello 世界" ]
}

@test "core::json_escape - handles very long strings" {
  # Create a 1000 character string
  long_str=$(printf 'a%.0s' {1..1000})
  run core::json_escape "${long_str}"
  [ "$status" -eq 0 ]
  [ ${#output} -eq 1000 ]
}

@test "core::json_escape - handles string with only special chars" {
  input=$'"\\\n\r\t'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = '\"\\\n\r\t' ]
}

# Real-world scenario tests

@test "core::json_escape - handles bash command with pipes" {
  run core::json_escape 'cat file.txt | grep "error"'
  [ "$status" -eq 0 ]
  [ "$output" = 'cat file.txt | grep \"error\"' ]
}

@test "core::json_escape - handles file path with spaces" {
  run core::json_escape '/path/to/my file.txt'
  [ "$status" -eq 0 ]
  [ "$output" = '/path/to/my file.txt' ]
}

@test "core::json_escape - handles JSON-like input" {
  input='{"key":"value"}'
  run core::json_escape "${input}"
  [ "$status" -eq 0 ]
  [ "$output" = '{\"key\":\"value\"}' ]
}
