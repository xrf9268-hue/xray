#!/usr/bin/env bash
# Log viewer and export functions for Xray logs
# Provides filtering, formatting, and export capabilities

# Source guard: prevent double-sourcing
[[ -n "${_XRF_LOGS_LOADED:-}" ]] && return 0
readonly _XRF_LOGS_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"

# ANSI color codes for log formatting
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_GRAY='\033[0;90m'

##
# Internal function: stream command output through the log formatter
#
# Preserves the producer command's exit status instead of losing it to a
# formatter pipeline, while still allowing streaming output for follow mode.
#
# Arguments:
#   $1 - Log level filter
#   $2 - Disable colors (true|false)
#   $@ - Command and arguments to execute
#
# Returns:
#   0 - Command succeeded and output was formatted
#   1 - Command execution failed or FIFO setup failed
##
logs::_run_formatted_command() {
  local level="${1:-all}"
  local no_color="${2:-false}"
  shift 2

  local fifo=""
  fifo="$(mktemp "${TMPDIR:-/tmp}/xray-logs.XXXXXX")" || return 1
  rm -f "${fifo}" 2> /dev/null || return 1

  if ! mkfifo "${fifo}"; then
    rm -f "${fifo}" 2> /dev/null || true
    return 1
  fi

  "$@" > "${fifo}" 2> /dev/null &
  local cmd_pid=$!

  logs::_format "${level}" "${no_color}" < "${fifo}"
  local format_rc=$?

  wait "${cmd_pid}"
  local cmd_rc=$?

  rm -f "${fifo}" 2> /dev/null || true

  if [[ "${cmd_rc}" -ne 0 ]]; then
    return 1
  fi

  return "${format_rc}"
}

##
# View Xray logs with filtering options
#
# Displays Xray service logs from journald with optional filtering
# by log level, time range, and line count.
#
# Arguments:
#   None (uses environment variables for configuration)
#
# Globals:
#   LOG_LEVEL - Filter by log level (debug|info|warn|error|all, default: all)
#   LOG_SINCE - Time range filter (e.g., "1 hour ago", "2023-01-01", default: none)
#   LOG_LINES - Number of lines to show (default: 50)
#   LOG_NO_COLOR - Disable colored output (default: false)
#
# Output:
#   Formatted and optionally colored log lines to stdout
#
# Returns:
#   0 - Success
#   1 - journalctl command failed
#   2 - xray service not found
#
# Example:
#   LOG_LEVEL=error LOG_SINCE="1 hour ago" logs::view
#   LOG_LINES=100 logs::view
##
logs::view() {
  local level="${LOG_LEVEL:-all}"
  local since="${LOG_SINCE:-}"
  local lines="${LOG_LINES:-50}"
  local no_color="${LOG_NO_COLOR:-false}"

  # Build journalctl command
  local cmd=(journalctl -u xray.service)

  # Add line limit
  cmd+=(-n "${lines}")

  # Add time filter if specified
  if [[ -n "${since}" ]]; then
    cmd+=(--since "${since}")
  fi

  # Add output format
  cmd+=(--output=short-iso --no-pager)

  core::log debug "viewing logs" "$(printf '{"level":"%s","since":"%s","lines":%d}' "${level}" "${since}" "${lines}")"

  # Execute journalctl and filter/format output
  if ! logs::_run_formatted_command "${level}" "${no_color}" "${cmd[@]}"; then
    core::log error "failed to retrieve logs" '{"suggestion":"ensure xray service is running"}'
    return 1
  fi
}

##
# Follow Xray logs in real-time
#
# Streams Xray service logs in real-time using journalctl -f.
# Supports optional log level filtering.
#
# Arguments:
#   None (uses environment variables for configuration)
#
# Globals:
#   LOG_LEVEL - Filter by log level (debug|info|warn|error|all, default: all)
#   LOG_NO_COLOR - Disable colored output (default: false)
#
# Output:
#   Real-time log stream to stdout
#
# Returns:
#   0 - Success (interrupted by user)
#   1 - journalctl command failed
#
# Example:
#   LOG_LEVEL=error logs::follow
#   logs::follow
##
logs::follow() {
  local level="${LOG_LEVEL:-all}"
  local no_color="${LOG_NO_COLOR:-false}"

  core::log info "following logs in real-time" "$(printf '{"level":"%s"}' "${level}")"
  printf '%s[Ctrl+C to stop]%s\n\n' "${COLOR_GRAY}" "${COLOR_RESET}"

  # Build journalctl command with follow flag
  local cmd=(journalctl -u xray.service -f --output=short-iso --no-pager)

  # Execute and format
  if ! logs::_run_formatted_command "${level}" "${no_color}" "${cmd[@]}"; then
    core::log error "failed to follow logs" '{"suggestion":"ensure xray service is running"}'
    return 1
  fi
}

##
# Export Xray logs to a file
#
# Exports Xray service logs to a specified file with optional filtering.
# Creates the output file and writes logs in plain text format.
#
# Arguments:
#   $1 - Output file path (required)
#
# Globals:
#   LOG_LEVEL - Filter by log level (debug|info|warn|error|all, default: all)
#   LOG_SINCE - Time range filter (default: none)
#   LOG_LINES - Number of lines to export (default: 1000)
#
# Output:
#   Export confirmation to stderr (via core::log)
#   Log content to specified file
#
# Returns:
#   0 - Success
#   1 - Export failed (invalid file path, permission error, etc.)
#
# Example:
#   logs::export "/tmp/xray-logs.txt"
#   LOG_SINCE="1 day ago" logs::export "/var/log/xray-export.log"
##
logs::export() {
  local output_file="${1:?output file required}"
  local level="${LOG_LEVEL:-all}"
  local since="${LOG_SINCE:-}"
  local lines="${LOG_LINES:-1000}"

  core::log info "exporting logs" "$(printf '{"file":"%s","level":"%s","lines":%d}' "${output_file}" "${level}" "${lines}")"

  # Build journalctl command
  local cmd=(journalctl -u xray.service)
  cmd+=(-n "${lines}")
  [[ -n "${since}" ]] && cmd+=(--since "${since}")
  cmd+=(--output=short-iso --no-pager)

  # Export to file (no formatting, no color)
  if ! logs::_run_formatted_command "${level}" "true" "${cmd[@]}" > "${output_file}"; then
    core::log error "failed to export logs" "$(printf '{"file":"%s"}' "${output_file}")"
    return 1
  fi

  local exported_lines
  exported_lines=$(wc -l < "${output_file}" 2> /dev/null || echo "unknown")
  core::log info "logs exported successfully" "$(printf '{"file":"%s","lines":"%s"}' "${output_file}" "${exported_lines}")"
  return 0
}

##
# Get log statistics
#
# Analyzes recent Xray logs and returns statistics:
# - Total lines
# - Error count
# - Warning count
# - Info count
#
# Arguments:
#   None (uses environment variables for configuration)
#
# Globals:
#   LOG_SINCE - Time range for analysis (default: "24 hours ago")
#
# Output:
#   JSON object with statistics to stdout
#
# Returns:
#   0 - Success
#   1 - Failed to retrieve logs
#
# Example:
#   logs::stats
#   LOG_SINCE="1 week ago" logs::stats
##
logs::stats() {
  local since="${LOG_SINCE:-24 hours ago}"

  core::log debug "calculating log statistics" "$(printf '{"since":"%s"}' "${since}")"

  # Get logs
  local logs
  if ! logs=$(journalctl -u xray.service --since "${since}" --output=cat --no-pager 2> /dev/null); then
    core::log error "failed to retrieve logs for statistics" "{}"
    return 1
  fi

  # Count by level (case-insensitive grep)
  local total_lines error_count warning_count info_count
  total_lines=$(echo "${logs}" | wc -l)
  error_count=$(echo "${logs}" | grep -ic "error" || echo "0")
  warning_count=$(echo "${logs}" | grep -ic "warning\|warn" || echo "0")
  info_count=$(echo "${logs}" | grep -ic "info" || echo "0")

  # Output JSON
  printf '{"total_lines":%d,"errors":%d,"warnings":%d,"info":%d,"since":"%s"}\n' \
    "${total_lines}" "${error_count}" "${warning_count}" "${info_count}" "${since}"
}

##
# Internal function: Format and optionally color log lines
#
# Filters log lines by level and applies ANSI color codes for readability.
#
# Arguments:
#   $1 - Log level filter (debug|info|warn|error|all)
#   $2 - Disable colors (true|false)
#
# Input:
#   Log lines from stdin
#
# Output:
#   Formatted and colored log lines to stdout
#
# Returns:
#   0 - Always succeeds
##
logs::_format() {
  local level="${1:-all}"
  local no_color="${2:-false}"

  # Read from stdin and process
  while IFS= read -r line; do
    # Apply level filter
    if [[ "${level}" != "all" ]]; then
      case "${level}" in
        error)
          [[ "${line}" =~ [Ee]rror ]] || continue
          ;;
        warn | warning)
          [[ "${line}" =~ [Ww]arn ]] || continue
          ;;
        info)
          [[ "${line}" =~ [Ii]nfo ]] || continue
          ;;
        debug)
          [[ "${line}" =~ [Dd]ebug ]] || continue
          ;;
      esac
    fi

    # Apply coloring
    local color=""
    if [[ "${line}" =~ [Ee]rror ]]; then
      color="${COLOR_RED}"
    elif [[ "${line}" =~ [Ww]arn ]]; then
      color="${COLOR_YELLOW}"
    elif [[ "${line}" =~ [Ii]nfo ]]; then
      color="${COLOR_GREEN}"
    elif [[ "${line}" =~ [Dd]ebug ]]; then
      color="${COLOR_GRAY}"
    fi

    if [[ "${no_color}" != "true" && -n "${color}" ]]; then
      printf '%b%s%b\n' "${color}" "${line}" "${COLOR_RESET}"
    else
      printf '%s\n' "${line}"
    fi
  done
}
