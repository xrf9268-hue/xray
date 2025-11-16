#!/usr/bin/env bash
# Structured error codes for xray-fusion
# Provides user-friendly error messages with recovery guidance
# NOTE: This file is sourced. Strict mode is set by the calling script

# Source guard - prevent multiple sourcing (readonly variable issue)
[[ -n "${_XRF_ERROR_CODES_LOADED:-}" ]] && return 0
readonly _XRF_ERROR_CODES_LOADED=1

##
# Error code format: XRF-CATEGORY-NUMBER
#
# Categories:
#   CONFIG  - Configuration and parameter errors
#   NETWORK - Network connectivity errors
#   CERT    - Certificate-related errors
#   XRAY    - Xray binary and configuration errors
#   SYSTEM  - System requirements and permissions
#   PLUGIN  - Plugin-related errors
##

# Documentation base URL (can be overridden)
readonly XRF_DOCS_BASE="${XRF_DOCS_BASE:-https://github.com/xrf9268-hue/xray}"

##
# Display an enhanced error message with recovery guidance
#
# Provides structured error output with error code, reason, resolution
# steps, examples, and documentation links. Supports both text and JSON
# output formats.
#
# Arguments:
#   $1 - Error code (string, required, format: XRF-CATEGORY-NUMBER)
#   $2 - Error title (string, required)
#   $3 - Reason (string, required, why the error occurred)
#   $4 - Resolution (string, required, how to fix it)
#   $5 - Examples (string, optional, usage examples)
#
# Globals:
#   XRF_JSON - If "true", output JSON format (set by core::init)
#   XRF_DOCS_BASE - Base URL for documentation links
#
# Output:
#   Formatted error message to stderr
#
# Returns:
#   1 - Always returns 1 (error status)
#
# Example:
#   error_codes::show "XRF-CONFIG-001" \
#     "Invalid domain" \
#     "Domain '192.168.1.1' is a private IP address (RFC 1918)" \
#     "Use a public domain name for vision-reality topology, or switch to reality-only topology which supports IP addresses." \
#     "xrf install --topology vision-reality --domain vpn.example.com"
##
error_codes::show() {
  local code="${1:?error code required}"
  local title="${2:?error title required}"
  local reason="${3:?reason required}"
  local resolution="${4:?resolution required}"
  local examples="${5:-}"

  # Build documentation URL
  local docs_url="${XRF_DOCS_BASE}#error-codes"

  # shellcheck disable=SC2154  # XRF_JSON is set by core::init
  if [[ "${XRF_JSON}" == "true" ]]; then
    # JSON output format
    local json_output
    json_output=$(
      cat << EOF
{
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "level": "error",
  "error_code": "${code}",
  "title": "${title}",
  "reason": "${reason}",
  "resolution": "${resolution}",
  "examples": "${examples}",
  "docs": "${docs_url}"
}
EOF
    )
    printf '%s\n' "${json_output}" >&2
  else
    # Text output format
    printf '\n[ERROR] %s: %s\n\n' "${code}" "${title}" >&2
    printf 'Reason:\n  %s\n\n' "${reason}" >&2
    printf 'Resolution:\n  %s\n' "${resolution}" >&2

    if [[ -n "${examples}" ]]; then
      printf '\nExamples:\n  %s\n' "${examples}" >&2
    fi

    printf '\nLearn more: %s\n\n' "${docs_url}" >&2
  fi

  return 1
}

##
# Common error: Invalid domain
#
# Arguments:
#   $1 - Domain value that failed validation
#   $2 - Specific reason (optional, defaults to generic message)
##
error_codes::invalid_domain() {
  local domain="${1}"
  local specific_reason="${2:-}"

  local reason="Domain '${domain}' is invalid"
  [[ -n "${specific_reason}" ]] && reason="${reason}: ${specific_reason}"

  local resolution="Use a public domain name for vision-reality topology, or switch to reality-only topology which doesn't require a domain."

  local examples="xrf install --topology vision-reality --domain vpn.example.com
xrf install --topology reality-only  # No domain needed"

  error_codes::show "XRF-CONFIG-001" \
    "Invalid domain" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Invalid topology
#
# Arguments:
#   $1 - Topology value that failed validation
##
error_codes::invalid_topology() {
  local topology="${1}"

  local reason="Topology '${topology}' is not supported"

  local resolution="Choose one of the supported topologies: reality-only or vision-reality"

  local examples="xrf install --topology reality-only
xrf install --topology vision-reality --domain example.com"

  error_codes::show "XRF-CONFIG-002" \
    "Invalid topology" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Missing required parameter
#
# Arguments:
#   $1 - Parameter name (e.g., "domain")
#   $2 - Context (e.g., "vision-reality topology")
##
error_codes::missing_parameter() {
  local param="${1}"
  local context="${2:-}"

  local reason="Required parameter '--${param}' is missing"
  [[ -n "${context}" ]] && reason="${reason} for ${context}"

  local resolution="Provide the --${param} parameter or choose a different configuration"

  local examples=""
  case "${param}" in
    domain)
      examples="xrf install --topology vision-reality --domain example.com"
      ;;
    topology)
      examples="xrf install --topology reality-only"
      ;;
    *)
      examples="xrf install --${param} <value>"
      ;;
  esac

  error_codes::show "XRF-CONFIG-003" \
    "Missing required parameter" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Port conflict
#
# Arguments:
#   $1 - Port number
#   $2 - Process/service using the port (optional)
##
error_codes::port_conflict() {
  local port="${1}"
  local process="${2:-unknown}"

  local reason="Port ${port} is already in use"
  [[ "${process}" != "unknown" ]] && reason="${reason} by ${process}"

  local resolution="Stop the conflicting service or use a different port"

  local examples="# Check what's using the port:
sudo lsof -i :${port}
sudo netstat -tulpn | grep ${port}

# Stop conflicting service (example):
sudo systemctl stop nginx

# Or use alternative port:
XRAY_PORT=8443 xrf install --topology reality-only"

  error_codes::show "XRF-NETWORK-001" \
    "Port conflict detected" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Certificate not found
#
# Arguments:
#   $1 - Certificate file path
##
error_codes::cert_not_found() {
  local cert_path="${1}"

  local reason="Required certificate file not found: ${cert_path}"

  local resolution="Enable the cert-auto plugin for automatic certificate management, or manually place certificates in the correct location"

  local examples="# Option 1: Use automatic certificates
xrf install --topology vision-reality --domain example.com --plugins cert-auto

# Option 2: Manual certificate placement
sudo cp fullchain.pem ${cert_path}
sudo cp privkey.pem ${cert_path%/*}/privkey.pem"

  error_codes::show "XRF-CERT-001" \
    "Certificate not found" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Invalid UUID format
#
# Arguments:
#   $1 - UUID value that failed validation
##
error_codes::invalid_uuid() {
  local uuid="${1}"

  local reason="UUID '${uuid}' does not match RFC 4122 format"

  local resolution="Provide a valid UUID in the format: 8-4-4-4-12 hexadecimal digits, or let xray-fusion generate one automatically"

  local examples="# Auto-generate (recommended):
xrf install --topology reality-only

# Use custom UUID:
xrf install --topology reality-only --uuid 6ba85179-d64e-4cb8-901f-bfb8e9e7d5f1

# Generate from string (memorable):
xrf install --topology reality-only --uuid-from-string alice"

  error_codes::show "XRF-CONFIG-004" \
    "Invalid UUID format" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Xray configuration test failed
#
# Arguments:
#   $1 - Test output/error message (currently unused, reserved for future enhancement)
##
error_codes::xray_config_invalid() {
  # shellcheck disable=SC2034  # Reserved for future use
  local test_output="${1}"

  local reason="Xray configuration validation failed"

  local resolution="Review the configuration files for syntax errors. The xray -test command provides detailed error information."

  local examples="# Manually test configuration:
sudo /usr/local/bin/xray -test -confdir /usr/local/etc/xray/active

# Check recent changes:
ls -lt /usr/local/etc/xray/active/

# View Xray logs:
sudo journalctl -u xray -n 50"

  error_codes::show "XRF-XRAY-001" \
    "Xray configuration test failed" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Missing system dependency
#
# Arguments:
#   $1 - Command/package name
#   $2 - Purpose/reason why it's needed (optional)
##
error_codes::missing_dependency() {
  local cmd="${1}"
  local purpose="${2:-}"

  local reason="Required command '${cmd}' not found"
  [[ -n "${purpose}" ]] && reason="${reason} (needed for: ${purpose})"

  local resolution="Install the missing package using your system's package manager"

  local examples="# Debian/Ubuntu:
sudo apt-get update && sudo apt-get install ${cmd}

# CentOS/RHEL:
sudo yum install ${cmd}

# Alpine:
sudo apk add ${cmd}"

  error_codes::show "XRF-SYSTEM-001" \
    "Missing system dependency" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}

##
# Common error: Plugin not found
#
# Arguments:
#   $1 - Plugin ID
##
error_codes::plugin_not_found() {
  local plugin_id="${1}"

  local reason="Plugin '${plugin_id}' does not exist"

  local resolution="Check available plugins and verify the plugin ID is correct"

  local examples="# List available plugins:
xrf plugin list

# Install with correct plugin name:
xrf install --plugins cert-auto,firewall"

  error_codes::show "XRF-PLUGIN-001" \
    "Plugin not found" \
    "${reason}" \
    "${resolution}" \
    "${examples}"
}
