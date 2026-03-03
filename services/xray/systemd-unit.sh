#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/modules/io.sh"
. "${HERE}/modules/user/user.sh"
. "${HERE}/lib/plugins.sh"
. "${HERE}/modules/state.sh"
# shellcheck source=services/xray/common.sh
. "${HERE}/services/xray/common.sh"

systemd::render_xray_unit() {
  local xray_bin confbase active_confdir
  xray_bin="$(xray::bin)"
  confbase="$(xray::confbase)"
  active_confdir="$(xray::active)"

  sed \
    -e "s|/usr/local/bin/xray|${xray_bin}|g" \
    -e "s|/usr/local/etc/xray/active|${active_confdir}|g" \
    -e "s|/usr/local/etc/xray|${confbase}|g" \
    "${HERE}/packaging/systemd/xray.service"
}

unit_path() { systemd_unit_path; }
install_unit() {
  core::init "${@}"
  core::log info "installing systemd unit" "{}"
  core::with_flock "$(state::lock)" install_unit_with_lock
}
systemd_unit_path() {
  local base="${XRF_SYSTEMD_DIR:-/etc/systemd/system}"
  echo "${base%/}/xray.service"
}
install_unit_with_lock() {
  user::ensure_system_user xray xray
  local unit_file
  unit_file="$(systemd_unit_path)"
  core::log info "preparing systemd unit directory" "$(printf '{"dir":"%s"}' "$(dirname "${unit_file}")")"
  io::ensure_dir "$(dirname "${unit_file}")" 0755
  core::log info "writing systemd unit file" "$(printf '{"path":"%s"}' "${unit_file}")"
  if ! systemd::render_xray_unit | io::atomic_write "${unit_file}" 0644; then
    core::log error "failed to write systemd unit" "$(printf '{"path":"%s"}' "${unit_file}")"
    return 1
  fi
  core::log info "reloading systemd manager configuration" '{}'
  if ! systemctl daemon-reload; then
    core::log error "systemctl daemon-reload failed" '{}'
    rm -f "${unit_file}" 2> /dev/null || true
    return 1
  fi
  core::log info "enabling and starting xray service" "$(printf '{"unit":"%s"}' "xray.service")"
  if ! systemctl enable --now xray; then
    core::log error "systemctl enable --now failed" "$(printf '{"unit":"%s"}' "xray.service")"
    rollback_systemd_unit "${unit_file}"
    return 1
  fi
  plugins::ensure_dirs
  plugins::load_enabled
  plugins::emit service_setup "unit=${unit_file}"
  core::log info "systemd unit installed" "$(printf '{"path":"%s"}' "${unit_file}")"
}
rollback_systemd_unit() {
  local unit_file="${1}"
  core::log warn "rolling back systemd unit installation" "$(printf '{"path":"%s"}' "${unit_file}")"
  if ! systemctl disable --now xray; then
    core::log warn "systemctl disable during rollback failed" "$(printf '{"unit":"%s"}' "xray.service")"
  fi
  rm -f "${unit_file}" 2> /dev/null || true
  if ! systemctl daemon-reload; then
    core::log warn "systemctl daemon-reload during rollback failed" '{}'
  fi
  if ! systemctl reset-failed xray.service 2> /dev/null; then
    core::log warn "systemctl reset-failed during rollback failed" '{}'
  fi
}
remove_unit() {
  core::init "${@}"
  local unit_file
  unit_file="$(systemd_unit_path)"
  plugins::ensure_dirs
  plugins::load_enabled
  plugins::emit service_remove "unit=${unit_file}"
  systemctl disable --now xray || true
  rm -f "${unit_file}"
  systemctl daemon-reload || true
  systemctl reset-failed xray.service 2> /dev/null || true
  core::log info "systemd unit removed" "{}"
}
case "${1-}" in install) install_unit "${@}" ;; remove) remove_unit "${@}" ;; *)
  echo "Usage: ${0} {install|remove}"
  exit 2
  ;;
esac
