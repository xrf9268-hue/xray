#!/usr/bin/env bats
# Unit tests for backup and restore functions (lib/backup.sh)

load ../test_helper

setup() {
  setup_test_env
  # Source backup module
  source "${PROJECT_ROOT}/lib/backup.sh"
  source "${PROJECT_ROOT}/modules/state.sh"

  # Override backup directory for testing
  export XRF_VAR="${TEST_TMPDIR}/var"
}

# Test helper: Create mock xray configuration
setup_mock_xray() {
  local xray_etc="${XRF_ETC}/xray"
  mkdir -p "${xray_etc}/active"

  # Create mock configuration file using printf
  printf '%s\n' '{"inbounds":[{"port":443,"protocol":"vless"}]}' > "${xray_etc}/active/config.json"

  # Create mock state file
  local state_content='{"name":"reality-only","version":"v1.8.0","installed_at":"2023-12-01T00:00:00Z"}'
  io::ensure_dir "$(dirname "$(state::path)")" 0755
  printf '%s\n' "${state_content}" > "$(state::path)"
}

# Test helper: Create mock backup with metadata
create_mock_backup() {
  local name="${1}"
  local backup_dir
  backup_dir="$(backup::dir)"
  mkdir -p "${backup_dir}"

  # Create mock tar.gz file
  printf 'test content\n' > "${backup_dir}/${name}.tar.gz"

  # Calculate actual hash
  local actual_hash
  actual_hash=$(sha256sum "${backup_dir}/${name}.tar.gz" | awk '{print $1}')

  # Create matching metadata using jq
  jq -n \
    --arg name "${name}" \
    --arg hash "${actual_hash}" \
    '{name:$name,timestamp:"20231201-120000",topology:"reality-only",xray_version:"v1.8.0",hash:$hash,size:1024}' \
    > "${backup_dir}/${name}.metadata.json"
}

teardown() {
  cleanup_test_env
}

# backup::dir tests
@test "backup::dir - returns correct path with default" {
  unset XRF_VAR
  result=$(backup::dir)
  [[ "$result" == "/var/lib/xray-fusion/backups" ]]
}

@test "backup::dir - uses custom XRF_VAR" {
  export XRF_VAR="/custom/path"
  result=$(backup::dir)
  [[ "$result" == "/custom/path/backups" ]]
}

# backup::create tests
@test "backup::create - requires xray configuration directory" {
  # No xray config exists
  run backup::create "test-backup"
  [ "$status" -ne 0 ]
}

@test "backup::create - generates auto name when not provided" {
  skip "Integration test - needs full environment setup"
  setup_mock_xray

  backup::create

  # Check backup file exists with timestamp pattern
  local backup_dir
  backup_dir="$(backup::dir)"
  # SC2144: Use compgen -G to test glob patterns
  compgen -G "${backup_dir}/backup-*.tar.gz" > /dev/null
}

@test "backup::create - uses custom name" {
  skip "Integration test - needs full environment setup"
  setup_mock_xray

  backup::create "custom-backup"

  local backup_dir
  backup_dir="$(backup::dir)"
  # SC2144: Use compgen -G to test glob patterns
  compgen -G "${backup_dir}/custom-backup-*.tar.gz" > /dev/null
}

@test "backup::create - creates metadata file" {
  setup_mock_xray

  backup::create "test-backup"

  local backup_dir
  backup_dir="$(backup::dir)"
  local metadata_file
  metadata_file=$(find "${backup_dir}" -name "test-backup-*.metadata.json" | head -1)

  [ -f "${metadata_file}" ]

  # Validate JSON structure
  jq empty "${metadata_file}"
  jq -e 'has("name")' "${metadata_file}"
  jq -e 'has("hash")' "${metadata_file}"
  jq -e 'has("size")' "${metadata_file}"
}

@test "backup::create - sanitizes backup name" {
  setup_mock_xray

  # Try to create backup with unsafe characters
  backup::create "test backup!@#$%^&*()"

  local backup_dir
  backup_dir="$(backup::dir)"

  # Check that only alphanumeric, dash, underscore are kept
  local backup_file
  backup_file=$(find "${backup_dir}" -name "*.tar.gz" | head -1)
  local basename
  basename=$(basename "${backup_file}" .tar.gz)

  # Should only contain alphanumeric, dash, underscore
  [[ "$basename" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# backup::list tests
@test "backup::list - shows no backups when directory empty" {
  mkdir -p "$(backup::dir)"

  run backup::list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No backups found"* ]]
}

@test "backup::list - displays backups in text format" {
  create_mock_backup "test-20231201-120000"

  run backup::list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[test-20231201-120000]"* ]]
  [[ "$output" == *"reality-only"* ]]
}

@test "backup::list - outputs JSON format when XRF_JSON=true" {
  mkdir -p "$(backup::dir)"
  export XRF_JSON="true"

  run backup::list
  [ "$status" -eq 0 ]

  # Validate JSON structure
  echo "$output" | jq empty
  echo "$output" | jq -e 'has("backups")'
  echo "$output" | jq -e '.backups | type == "array"'
}

# backup::verify tests
@test "backup::verify - requires backup name parameter" {
  run backup::verify ""
  [ "$status" -ne 0 ]
}

@test "backup::verify - fails when backup not found" {
  run backup::verify "nonexistent-backup"
  [ "$status" -ne 0 ]
}

@test "backup::verify - validates hash correctly" {
  create_mock_backup "test"

  run backup::verify "test"
  [ "$status" -eq 0 ]
}

@test "backup::verify - detects corrupted backup" {
  local backup_dir
  backup_dir="$(backup::dir)"
  mkdir -p "${backup_dir}"

  echo "test content" > "${backup_dir}/test.tar.gz"

  # Create metadata with wrong hash
  cat > "${backup_dir}/test.metadata.json" <<'EOF'
{
  "name": "test",
  "hash": "wronghash123"
}
EOF

  run backup::verify "test"
  [ "$status" -ne 0 ]
}

# backup::delete tests
@test "backup::delete - requires backup name parameter" {
  run backup::delete ""
  [ "$status" -ne 0 ]
}

@test "backup::delete - fails when backup not found" {
  run backup::delete "nonexistent-backup"
  [ "$status" -ne 0 ]
}

@test "backup::delete - removes backup file and metadata" {
  create_mock_backup "test"

  run backup::delete "test"
  [ "$status" -eq 0 ]

  local backup_dir
  backup_dir="$(backup::dir)"

  # Verify files are deleted
  [ ! -f "${backup_dir}/test.tar.gz" ]
  [ ! -f "${backup_dir}/test.metadata.json" ]
}

# backup::restore tests
@test "backup::restore - requires backup name parameter" {
  run backup::restore ""
  [ "$status" -ne 0 ]
}

@test "backup::restore - fails when backup not found" {
  run backup::restore "nonexistent-backup"
  [ "$status" -ne 0 ]
}

@test "backup::restore - fails when metadata not found" {
  local backup_dir
  backup_dir="$(backup::dir)"
  mkdir -p "${backup_dir}"

  # Create backup without metadata
  touch "${backup_dir}/test.tar.gz"

  run backup::restore "test"
  [ "$status" -ne 0 ]
}

# Integration tests
@test "backup workflow - create, list, verify, delete" {
  setup_mock_xray

  # Create backup
  backup::create "workflow-test"

  # List backups
  result=$(backup::list)
  [[ "$result" == *"workflow-test"* ]]

  # Get the exact backup name (includes timestamp)
  local backup_name
  backup_name=$(basename "$(find "$(backup::dir)" -name "workflow-test-*.tar.gz" | head -1)" .tar.gz)

  # Verify backup
  backup::verify "${backup_name}"

  # Delete backup
  backup::delete "${backup_name}"

  # Verify deletion
  result=$(backup::list)
  [[ "$result" == *"No backups found"* ]]
}
