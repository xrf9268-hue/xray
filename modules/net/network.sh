#!/usr/bin/env bash
# Network helpers
# NOTE: This module is sourced; callers are responsible for enabling strict mode (set -euo pipefail) via core::init().

[[ -n "${_XRF_NET_NETWORK_LOADED:-}" ]] && return 0
readonly _XRF_NET_NETWORK_LOADED=1

net::detect_public_ip() {
  local ip=""
  ip="$(timeout 3 dig +short myip.opendns.com @resolver1.opendns.com 2> /dev/null | awk 'NR==1')" || true
  [[ -n "${ip}" ]] || ip="$(timeout 3 dig +short whoami.cloudflare @1.1.1.1 txt 2> /dev/null | tr -d '"' | awk 'NR==1' || true)"
  [[ -n "${ip}" ]] || ip="$(timeout 3 curl -4fsS https://api.ipify.org 2> /dev/null || true)"
  [[ -n "${ip}" ]] || ip="$(timeout 3 curl -4fsS https://ifconfig.co 2> /dev/null || true)"
  [[ -n "${ip}" ]] || ip="$(ip route get 1.1.1.1 2> /dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1 || true)"
  echo "${ip}"
}
