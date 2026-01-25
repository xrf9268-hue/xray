#!/usr/bin/env bash
# Caddy automatic TLS management module
# Reference implementation: 233boy/Xray
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_CADDY_LOADED:-}" ]] && return 0
readonly _XRF_CADDY_LOADED=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/core.sh
. "${HERE}/lib/core.sh"
# shellcheck source=lib/validators.sh
. "${HERE}/lib/validators.sh"

caddy::bin() { echo "/usr/local/bin/caddy"; }
caddy::config_dir() { echo "/usr/local/etc/caddy"; }
caddy::config_file() { echo "$(caddy::config_dir)/Caddyfile"; }
caddy::cert_dir() { echo "/usr/local/etc/xray/certs"; }
caddy::systemd_file() { echo "/etc/systemd/system/caddy.service"; }

caddy::detect_arch() {
  local arch_u
  arch_u="$(uname -m)"
  case "${arch_u}" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *)
      core::log error "unsupported arch" "$(printf '{"arch":"%s"}' "${arch_u}")"
      exit 2
      ;;
  esac
}

caddy::get_latest_version() {
  curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest \
    | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
    | cut -d'"' -f4
}

caddy::install() {
  if [[ -x "$(caddy::bin)" ]]; then
    core::log info "caddy already installed" "$(printf '{"version":"%s"}' "$("$(caddy::bin)" version 2> /dev/null | head -n1 | cut -d' ' -f1)")"
    return 0
  fi

  local version arch tmpdir tmpfile
  version="$(caddy::get_latest_version)"
  arch="$(caddy::detect_arch)"
  tmpdir="$(mktemp -d)"
  tmpfile="${tmpdir}/caddy.tar.gz"

  # Explicit cleanup function (no EXIT trap in utility functions - see AGENTS.md)
  _caddy_cleanup() {
    rm -rf "${tmpdir}" 2> /dev/null || true
  }

  local url="https://github.com/caddyserver/caddy/releases/download/${version}/caddy_${version:1}_linux_${arch}.tar.gz"

  core::log info "downloading caddy" "$(printf '{"version":"%s","arch":"%s"}' "${version}" "${arch}")"
  if ! curl -fsSL "${url}" -o "${tmpfile}"; then
    core::log error "download failed" "$(printf '{"url":"%s"}' "${url}")"
    _caddy_cleanup
    return 1
  fi

  if ! tar -xzf "${tmpfile}" -C "${tmpdir}" caddy; then
    core::log error "extract failed" "{}"
    _caddy_cleanup
    return 1
  fi

  if ! io::install_file "${tmpdir}/caddy" "$(caddy::bin)" 0755; then
    core::log error "install failed" "$(printf '{"bin":"%s"}' "$(caddy::bin)")"
    _caddy_cleanup
    return 1
  fi

  # Success - clean up temp directory
  _caddy_cleanup
  core::log info "caddy installed" "$(printf '{"bin":"%s","version":"%s"}' "$(caddy::bin)" "${version}")"
}

caddy::create_systemd_service() {
  cat > "$(caddy::systemd_file)" << 'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/local/bin/caddy run --environ --config /usr/local/etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /usr/local/etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable caddy
  core::log info "caddy service created" "$(printf '{"service":"%s"}' "$(caddy::systemd_file)")"
}

caddy::setup_auto_tls() {
  local domain="${1}" xray_port="${2:-8443}"

  # Configurable Caddy ports (defaults: 80 for HTTP, 8444 for HTTPS to avoid conflict with Xray Vision)
  local caddy_http_port="${CADDY_HTTP_PORT:-80}"
  local caddy_https_port="${CADDY_HTTPS_PORT:-8444}"
  local caddy_fallback_port="${CADDY_FALLBACK_PORT:-8080}"

  # Validate port numbers (1-65535)
  for port_info in "${caddy_http_port}:CADDY_HTTP_PORT" "${caddy_https_port}:CADDY_HTTPS_PORT" "${caddy_fallback_port}:CADDY_FALLBACK_PORT"; do
    local port="${port_info%%:*}" name="${port_info#*:}"
    if ! validators::port "${port}"; then
      core::log error "invalid port number" "$(printf '{"port":"%s","name":"%s","valid_range":"1-65535"}' "${port}" "${name}")"
      return 1
    fi
  done

  # Check for port conflicts with Xray Vision
  if [[ "${caddy_https_port}" == "${xray_port}" ]]; then
    core::log error "port conflict detected" "$(printf '{"caddy_https_port":"%s","xray_vision_port":"%s"}' "${caddy_https_port}" "${xray_port}")"
    return 1
  fi

  io::ensure_dir "$(caddy::config_dir)" 0755
  io::ensure_dir "$(caddy::cert_dir)" 0755

  core::log debug "configuring caddy" "$(printf '{"http_port":"%s","https_port":"%s","fallback_port":"%s"}' "${caddy_http_port}" "${caddy_https_port}" "${caddy_fallback_port}")"

  # Create Caddyfile configuration - Caddy as fallback service, does not occupy 443
  cat > "$(caddy::config_file)" << EOF
{
  admin off
  http_port ${caddy_http_port}
  https_port ${caddy_https_port}
}

:${caddy_fallback_port} {
  respond "404 - Page Not Found" 404
}

${domain}:${caddy_https_port} {
  reverse_proxy 127.0.0.1:${xray_port}
}
EOF

  # Create systemd service
  caddy::create_systemd_service

  # Start Caddy
  systemctl start caddy || {
    core::log error "failed to start caddy" "{}"
    return 1
  }

  core::log info "caddy configured for auto TLS" "$(printf '{"domain":"%s","config":"%s","http_port":"%s","https_port":"%s"}' "${domain}" "$(caddy::config_file)" "${caddy_http_port}" "${caddy_https_port}")"
}

caddy::wait_for_cert() {
  local domain="${1}" max_wait=120 waited=0
  local cert_dir
  cert_dir="$(caddy::cert_dir)"

  core::log info "waiting for certificate" "$(printf '{"domain":"%s"}' "${domain}")"

  # Wait for Caddy to start and obtain certificate
  while [[ $waited -lt $max_wait ]]; do
    # Check if Caddy is running
    if systemctl is-active --quiet caddy; then
      core::log debug "caddy service is active" "$(printf '{"waited":"%ds"}' "${waited}")"

      # First check if Caddy has obtained certificate (check Caddy's own cert directory)
      # Use nullglob to avoid unnecessary ls calls
      shopt -s nullglob
      local caddy_certs=(/root/.local/share/caddy/certificates/*/"${domain}.crt")
      shopt -u nullglob

      if [[ ${#caddy_certs[@]} -gt 0 ]]; then
        core::log debug "caddy certificate found in cert directory" "$(printf '{"domain":"%s"}' "${domain}")"

        # Try to sync certificate
        if /usr/local/bin/caddy-cert-sync "${domain}" > /dev/null 2>&1; then
          core::log debug "certificate sync succeeded" "{}"
        else
          core::log debug "certificate sync failed, will retry" "{}"
        fi
      else
        core::log debug "caddy certificate not ready yet" "$(printf '{"waited":"%ds"}' "${waited}")"
      fi

      # Check if certificate has been synced to Xray directory
      if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
        core::log info "certificate ready" "$(printf '{"domain":"%s","waited":"%ds"}' "${domain}" "${waited}")"
        return 0
      fi
    else
      core::log debug "waiting for caddy service to start" "$(printf '{"waited":"%ds"}' "${waited}")"
    fi

    sleep 5
    ((waited += 5))
  done

  core::log error "certificate timeout" "$(printf '{"domain":"%s","waited":"%ds"}' "${domain}" "${waited}")"
  return 1
}

caddy::setup_cert_sync() {
  local domain="${1}"
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # Install certificate sync script (from scripts/ directory)
  local script_src="${here}/scripts/caddy-cert-sync.sh"
  local script_dst="/usr/local/bin/caddy-cert-sync"

  if [[ ! -f "${script_src}" ]]; then
    core::log error "cert sync script not found" "$(printf '{"source":"%s"}' "${script_src}")"
    return 1
  fi

  io::install_file "${script_src}" "${script_dst}" 0755
  core::log info "cert sync script installed" "$(printf '{"path":"%s"}' "${script_dst}")"

  # Create systemd service for certificate synchronization
  cat > /etc/systemd/system/cert-reload.service << EOF
[Unit]
Description=Sync Caddy certificates to Xray for ${domain}
After=caddy.service
PartOf=caddy.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/caddy-cert-sync ${domain}

# Environment variables (compatible with project logging system)
Environment="XRF_DEBUG=\${XRF_DEBUG:-false}"
Environment="XRF_JSON=\${XRF_JSON:-false}"

# Security hardening
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/usr/local/etc/xray/certs
NoNewPrivileges=true

# Resource limits
MemoryMax=50M
TasksMax=10
EOF

  # Create systemd timer for periodic certificate checks (more reliable than path units)
  # Reference: systemd Path units are unreliable on some filesystems and nested directory scenarios
  cat > /etc/systemd/system/cert-reload.timer << EOF
[Unit]
Description=Periodic certificate sync check for ${domain}
PartOf=caddy.service

[Timer]
# First run 2 minutes after boot
OnBootSec=2min
# Check every 10 minutes (certificate changes are infrequent, 10 minutes is sufficient)
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable cert-reload.timer
  systemctl start cert-reload.timer

  core::log info "certificate sync configured (timer-based)" "$(printf '{"domain":"%s","interval":"10min"}' "${domain}")"
}
