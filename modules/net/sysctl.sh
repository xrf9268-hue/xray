#!/usr/bin/env bash
# TCP sysctl tuning for Xray proxy servers
# NOTE: This module is sourced; callers are responsible for enabling strict mode (set -euo pipefail) via core::init().

[[ -n "${_XRF_NET_SYSCTL_LOADED:-}" ]] && return 0
readonly _XRF_NET_SYSCTL_LOADED=1

readonly XRF_SYSCTL_CONF="/etc/sysctl.d/99-xray-optimize.conf"

net::_sysctl_content() {
  cat << 'SYSCTL'
# xray-fusion TCP optimization
# https://github.com/XTLS/Xray-core/discussions/1984

# Congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Connection queue
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# Buffer sizes
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 4096 87380 2500000
net.ipv4.tcp_wmem = 4096 65536 2500000

# Source port range
net.ipv4.ip_local_port_range = 1024 65535

# Keep-alive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30

# Connection timeout
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# Performance
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
SYSCTL
}

##
# Apply TCP sysctl tuning for proxy workloads.
#
# Writes optimized parameters to /etc/sysctl.d/99-xray-optimize.conf
# and applies them. Idempotent: skips if file exists with identical content.
#
# Returns:
#   0 - Success (applied or already up-to-date)
#   1 - Failed to write or apply
##
net::apply_sysctl_tuning() {
  local desired
  desired="$(net::_sysctl_content)"

  if [[ -f "${XRF_SYSCTL_CONF}" ]]; then
    local current
    current="$(cat "${XRF_SYSCTL_CONF}" 2> /dev/null || true)"
    if [[ "${current}" == "${desired}" ]]; then
      core::log info "sysctl tuning already up-to-date" "$(printf '{"path":"%s"}' "${XRF_SYSCTL_CONF}")"
      return 0
    fi
  fi

  core::log info "applying TCP sysctl tuning" "$(printf '{"path":"%s"}' "${XRF_SYSCTL_CONF}")"

  printf '%s\n' "${desired}" | io::atomic_write "${XRF_SYSCTL_CONF}" 0644

  if ! sysctl -p "${XRF_SYSCTL_CONF}" > /dev/null 2>&1; then
    core::log warn "sysctl -p failed" "$(printf '{"path":"%s","suggestion":"verify kernel support"}' "${XRF_SYSCTL_CONF}")"
    return 1
  fi

  core::log info "TCP sysctl tuning applied" "{}"
}
