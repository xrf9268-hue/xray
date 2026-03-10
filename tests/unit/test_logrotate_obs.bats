#!/usr/bin/env bats
# Unit tests for plugins/available/logrotate-obs/plugin.sh
# shellcheck disable=SC2154  # Variables defined in test_helper.bash

load ../test_helper

setup() {
  setup_test_env
  source "${PROJECT_ROOT}/modules/io.sh"
  source "${PROJECT_ROOT}/plugins/available/logrotate-obs/plugin.sh"
}

teardown() {
  cleanup_test_env
  unset XRF_LOG_TARGET XRAY_LOG_LEVEL XRF_LOGROTATE_FREQUENCY
  unset XRF_LOGROTATE_ROTATE XRF_LOGROTATE_SIZE XRF_JOURNAL_TUNE
  unset XRF_JOURNAL_MAX XRF_JOURNAL_RATE_INTERVAL XRF_JOURNAL_RATE_BURST
}

# === _log_dir Tests ===

@test "_log_dir - returns /var/log/xray" {
  run _log_dir
  [ "$status" -eq 0 ]
  [ "$output" = "/var/log/xray" ]
}

# === _logrotate_path Tests ===

@test "_logrotate_path - returns correct path" {
  run _logrotate_path
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/logrotate.d/xray-fusion" ]
}

# === _journal_dropin_dir Tests ===

@test "_journal_dropin_dir - returns correct path" {
  run _journal_dropin_dir
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/systemd/journald.conf.d" ]
}

# === _journal_dropin Tests ===

@test "_journal_dropin - returns file inside dropin dir" {
  run _journal_dropin
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/systemd/journald.conf.d/xray-fusion.conf" ]
}

# === _build_logrotate_body Tests ===

@test "_build_logrotate_body - uses default values" {
  unset XRF_LOGROTATE_FREQUENCY XRF_LOGROTATE_ROTATE XRF_LOGROTATE_SIZE
  run _build_logrotate_body
  [ "$status" -eq 0 ]
  [[ "$output" == *"/var/log/xray/*.log"* ]]
  [[ "$output" == *"weekly"* ]]
  [[ "$output" == *"rotate 8"* ]]
  [[ "$output" == *"compress"* ]]
  [[ "$output" == *"copytruncate"* ]]
  [[ "$output" == *"create 0640 xray xray"* ]]
}

@test "_build_logrotate_body - respects custom frequency" {
  export XRF_LOGROTATE_FREQUENCY="daily"
  run _build_logrotate_body
  [ "$status" -eq 0 ]
  [[ "$output" == *"daily"* ]]
}

@test "_build_logrotate_body - respects custom rotate count" {
  export XRF_LOGROTATE_ROTATE="4"
  run _build_logrotate_body
  [ "$status" -eq 0 ]
  [[ "$output" == *"rotate 4"* ]]
}

@test "_build_logrotate_body - adds size directive when frequency is size" {
  export XRF_LOGROTATE_FREQUENCY="size"
  export XRF_LOGROTATE_SIZE="100M"
  run _build_logrotate_body
  [ "$status" -eq 0 ]
  [[ "$output" == *"size 100M"* ]]
}

@test "_build_logrotate_body - no size directive for weekly frequency" {
  export XRF_LOGROTATE_FREQUENCY="weekly"
  run _build_logrotate_body
  [ "$status" -eq 0 ]
  [[ "$output" != *"size "* ]]
}

# === logrotate_obs::configure_post Tests ===

@test "logrotate_obs::configure_post - journald mode logs info" {
  export XRF_LOG_TARGET="journald"
  run logrotate_obs::configure_post "topology=reality-only" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 0 ]
}

@test "logrotate_obs::configure_post - defaults to journald" {
  unset XRF_LOG_TARGET
  run logrotate_obs::configure_post "topology=reality-only" "release_dir=${TEST_TMPDIR}"
  [ "$status" -eq 0 ]
}

# === logrotate_obs::service_remove Tests ===

@test "logrotate_obs::service_remove - removes existing logrotate config" {
  # Override _logrotate_path to use sandbox directory
  local test_conf="${TEST_TMPDIR}/logrotate.d/xray-fusion"
  mkdir -p "$(dirname "${test_conf}")"
  touch "${test_conf}"
  _logrotate_path() { echo "${TEST_TMPDIR}/logrotate.d/xray-fusion"; }
  logrotate_obs::service_remove
  [ ! -f "${test_conf}" ]
}

@test "logrotate_obs::service_remove - succeeds when config does not exist" {
  _logrotate_path() { echo "/nonexistent/path/$$"; }
  logrotate_obs::service_remove
}

# === logrotate_obs::uninstall_pre Tests ===

@test "logrotate_obs::uninstall_pre - removes journal dropin" {
  local dropin="${TEST_TMPDIR}/test-dropin.conf"
  touch "${dropin}"
  _journal_dropin() { echo "${dropin}"; }
  logrotate_obs::uninstall_pre
  [ ! -f "${dropin}" ]
}

@test "logrotate_obs::uninstall_pre - succeeds when dropin does not exist" {
  _journal_dropin() { echo "/nonexistent/dropin-$$"; }
  logrotate_obs::uninstall_pre
}

# === logrotate_obs::links_render Tests ===

@test "logrotate_obs::links_render - shows journald commands by default" {
  unset XRF_LOG_TARGET
  run logrotate_obs::links_render
  [ "$status" -eq 0 ]
  [[ "$output" == *"Observability"* ]]
  [[ "$output" == *"journalctl"* ]]
}

@test "logrotate_obs::links_render - shows file log paths when target is file" {
  export XRF_LOG_TARGET="file"
  run logrotate_obs::links_render
  [ "$status" -eq 0 ]
  [[ "$output" == *"File logs"* ]]
  [[ "$output" == *"/var/log/xray"* ]]
  [[ "$output" == *"logrotate"* ]]
}

# === Plugin metadata ===

@test "logrotate-obs plugin - has correct metadata" {
  [ "$XRF_PLUGIN_ID" = "logrotate-obs" ]
  [ "$XRF_PLUGIN_VERSION" = "1.0.0" ]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"configure_post"* ]]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"service_setup"* ]]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"service_remove"* ]]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"links_render"* ]]
  [[ "${XRF_PLUGIN_HOOKS[*]}" == *"uninstall_pre"* ]]
}
