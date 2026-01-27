#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/plugins.sh"
. "${HERE}/services/xray/common.sh"

_rm() {
  local p="${1}"
  [[ -e "${p}" || -L "${p}" ]] && {
    core::log debug "removing" "$(printf '{"path":"%s"}' "$(core::json_escape "${p}")")"
    rm -rf "${p}" || true
  }
}

uninstall_caddy() {
  core::log info "uninstalling Caddy" "{}"

  # List of all Caddy-related systemd units (current + deprecated)
  local units=(
    "caddy"
    "cert-reload.timer"
    "cert-reload.service"
    "cert-reload.path"        # Deprecated
    "caddy-cert-sync.timer"   # Deprecated
    "caddy-cert-sync.service" # Deprecated
  )

  # Batch stop and disable all units (performance optimization: 12→2 systemctl calls)
  for unit in "${units[@]}"; do
    systemctl stop "${unit}" 2> /dev/null || true
  done
  for unit in "${units[@]}"; do
    systemctl disable "${unit}" 2> /dev/null || true
  done

  # Remove systemd unit files
  _rm "/etc/systemd/system/caddy.service"
  _rm "/etc/systemd/system/cert-reload.timer"
  _rm "/etc/systemd/system/cert-reload.service"
  _rm "/etc/systemd/system/cert-reload.path"        # Deprecated
  _rm "/etc/systemd/system/cert-reload.target"      # Deprecated
  _rm "/etc/systemd/system/caddy-cert-sync.service" # Deprecated
  _rm "/etc/systemd/system/caddy-cert-sync.timer"   # Deprecated

  # Reload systemd daemon and batch reset failed states
  systemctl daemon-reload || true
  for unit in "${units[@]}"; do
    systemctl reset-failed "${unit}" 2> /dev/null || true
  done

  # Remove Caddy binary and config
  _rm "/usr/local/bin/caddy"
  _rm "/usr/local/bin/caddy-cert-sync"
  _rm "/usr/local/etc/caddy"

  # Remove Caddy data directories (optional, commented out to preserve certificates)
  # _rm "/root/.local/share/caddy"
  # _rm "/root/.config/caddy"

  core::log info "Caddy uninstalled" "{}"
}

disable_all_plugins() {
  local enabled_dir="${HERE}/plugins/enabled"

  if [[ ! -d "${enabled_dir}" ]]; then
    return 0
  fi

  core::log info "disabling all plugins" "{}"

  # Find all enabled plugins and disable them
  for plugin_link in "${enabled_dir}"/*.sh; do
    if [[ -L "${plugin_link}" ]]; then
      local plugin_name
      plugin_name="$(basename "${plugin_link}" .sh)"
      core::log info "disabling plugin" "$(printf '{"plugin":"%s"}' "${plugin_name}")"
      rm -f "${plugin_link}" || true
    fi
  done

  core::log info "all plugins disabled" "{}"
}

main() {
  core::init "${@}"
  plugins::ensure_dirs
  plugins::load_enabled
  plugins::emit uninstall_pre

  # Uninstall Xray
  "${HERE}/services/xray/systemd-unit.sh" remove 2> /dev/null || true
  _rm "$(xray::prefix)/bin/xray"
  _rm "$(xray::confbase)"

  # Uninstall Caddy if it was installed by cert-auto plugin
  if [[ -f "/usr/local/bin/caddy" ]]; then
    uninstall_caddy
  fi

  plugins::emit uninstall_post

  # Disable all enabled plugins after uninstallation
  disable_all_plugins

  core::log info "uninstallation complete" "{}"
}
main "${@}"
