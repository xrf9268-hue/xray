#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/logs.sh"

usage() {
  cat << 'EOF'
Usage: xrf logs [options]

View, filter, and export Xray service logs.

Options:
  --level <level>       Filter by log level (debug|info|warn|error|all)
  --since <time>        Show logs since time (e.g., "1 hour ago", "2023-01-01")
  --lines <n>           Number of lines to show (default: 50)
  --follow, -f          Follow logs in real-time
  --export <file>       Export logs to file
  --stats               Show log statistics
  --no-color            Disable colored output
  --help, -h            Show this help

Examples:
  # View recent logs
  xrf logs

  # View only errors from last hour
  xrf logs --level error --since "1 hour ago"

  # Follow logs in real-time
  xrf logs --follow

  # Export logs to file
  xrf logs --export /tmp/xray-logs.txt

  # Show log statistics
  xrf logs --stats

  # View more lines without color
  xrf logs --lines 200 --no-color

EOF
}

main() {
  core::init "${@}"

  # Parse options
  local level="all"
  local since=""
  local lines="50"
  local follow=false
  local export_file=""
  local show_stats=false
  local no_color=false

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --level)
        level="${2:-}"
        if [[ ! "${level}" =~ ^(debug|info|warn|warning|error|all)$ ]]; then
          core::log error "invalid log level" "$(printf '{"level":"%s","valid":"debug|info|warn|error|all"}' "${level}")"
          exit 1
        fi
        shift 2
        ;;
      --since)
        since="${2:-}"
        if [[ -z "${since}" ]]; then
          core::log error "missing value for --since" "{}"
          exit 1
        fi
        shift 2
        ;;
      --lines)
        lines="${2:-}"
        if [[ ! "${lines}" =~ ^[0-9]+$ ]]; then
          core::log error "invalid lines value" "$(printf '{"lines":"%s"}' "${lines}")"
          exit 1
        fi
        shift 2
        ;;
      --follow | -f)
        follow=true
        shift
        ;;
      --export)
        export_file="${2:-}"
        if [[ -z "${export_file}" ]]; then
          core::log error "missing file path for --export" "{}"
          exit 1
        fi
        shift 2
        ;;
      --stats)
        show_stats=true
        shift
        ;;
      --no-color)
        no_color=true
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        core::log error "unknown option" "$(printf '{"option":"%s"}' "${1}")"
        usage
        exit 1
        ;;
    esac
  done

  # Export variables for log functions
  export LOG_LEVEL="${level}"
  export LOG_SINCE="${since}"
  export LOG_LINES="${lines}"
  export LOG_NO_COLOR="${no_color}"

  # Execute command
  if [[ "${show_stats}" == "true" ]]; then
    # Show statistics
    local stats
    if ! stats=$(logs::stats); then
      exit 1
    fi

    # Format statistics output
    local total_lines
    local error_count
    local warning_count
    local info_count
    total_lines="$(jq -r '.total_lines' <<< "${stats}")"
    error_count="$(jq -r '.errors' <<< "${stats}")"
    warning_count="$(jq -r '.warnings' <<< "${stats}")"
    info_count="$(jq -r '.info' <<< "${stats}")"
    printf '\n📊 Log Statistics\n\n'
    printf 'Time range:  %s\n' "${since:-24 hours ago}"
    printf 'Total lines: %s\n' "${total_lines}"
    printf 'Errors:      %s\n' "${error_count}"
    printf 'Warnings:    %s\n' "${warning_count}"
    printf 'Info:        %s\n\n' "${info_count}"

  elif [[ -n "${export_file}" ]]; then
    # Export to file
    if ! logs::export "${export_file}"; then
      exit 1
    fi

  elif [[ "${follow}" == "true" ]]; then
    # Follow logs in real-time
    if ! logs::follow; then
      exit 1
    fi

  else
    # View logs
    if ! logs::view; then
      exit 1
    fi
  fi
}

main "${@}"
