#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <apt-package> [<apt-package> ...]" >&2
  exit 2
fi

log() {
  printf '[apt-resilient] %s\n' "$*" >&2
}

APT_RETRIES="${APT_RETRIES:-5}"
APT_HTTP_TIMEOUT="${APT_HTTP_TIMEOUT:-30}"
APT_HTTPS_TIMEOUT="${APT_HTTPS_TIMEOUT:-30}"
APT_FALLBACK_MIRRORS="${APT_FALLBACK_MIRRORS:-mirror://mirrors.ubuntu.com/mirrors.txt,http://mirrors.edge.kernel.org/ubuntu/,http://mirrors.aliyun.com/ubuntu/,http://mirrors.tuna.tsinghua.edu.cn/ubuntu/}"

packages=("$@")
tmp_lists=()

maybe_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

apt_opts=(
  -o "Acquire::Retries=${APT_RETRIES}"
  -o "Acquire::http::Timeout=${APT_HTTP_TIMEOUT}"
  -o "Acquire::https::Timeout=${APT_HTTPS_TIMEOUT}"
)

if [[ -n "${APT_CACHE_DIR:-}" ]]; then
  mkdir -p "${APT_CACHE_DIR}/partial"
  apt_opts+=(-o "Dir::Cache::archives=${APT_CACHE_DIR}")
fi

cleanup_tmp_lists() {
  local f
  for f in "${tmp_lists[@]}"; do
    rm -f "${f}" 2>/dev/null || true
  done
}

trim_spaces() {
  local value="${1}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

write_ubuntu_sources() {
  local dst="${1}"
  local base="${2}"
  cat > "${dst}" <<EOF
deb ${base} ${codename} main restricted universe multiverse
deb ${base} ${codename}-updates main restricted universe multiverse
deb ${base} ${codename}-backports main restricted universe multiverse
deb ${base} ${codename}-security main restricted universe multiverse
EOF
}

apt_install_with_source() {
  local label="${1}"
  local source_list="${2:-}"
  local -a opts=("${apt_opts[@]}")

  if [[ -n "${source_list}" ]]; then
    opts+=(
      -o "Dir::Etc::sourcelist=${source_list}"
      -o "Dir::Etc::sourceparts=-"
      -o "APT::Get::List-Cleanup=0"
    )
  fi

  log "apt-get update via ${label}"
  if ! maybe_sudo apt-get "${opts[@]}" update; then
    log "apt-get update failed via ${label}"
    return 1
  fi

  log "apt-get install via ${label}: ${packages[*]}"
  if ! maybe_sudo apt-get "${opts[@]}" install -y "${packages[@]}"; then
    log "apt-get install failed via ${label}"
    return 1
  fi

  return 0
}

if apt_install_with_source "default sources"; then
  cleanup_tmp_lists
  exit 0
fi

# Fallback to the mirror list if the default repository endpoint is flaky.
if [[ ! -r /etc/os-release ]]; then
  echo "apt update failed and /etc/os-release is unavailable for mirror fallback" >&2
  exit 1
fi

# shellcheck source=/etc/os-release
. /etc/os-release
codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [[ "${ID:-}" != "ubuntu" || -z "${codename}" ]]; then
  echo "apt update failed and fallback mirror is only configured for Ubuntu runners" >&2
  exit 1
fi

IFS=',' read -r -a fallback_mirrors <<< "${APT_FALLBACK_MIRRORS}"

for mirror in "${fallback_mirrors[@]}"; do
  mirror="$(trim_spaces "${mirror}")"
  [[ -n "${mirror}" ]] || continue

  fallback_list="$(mktemp)"
  tmp_lists+=("${fallback_list}")
  write_ubuntu_sources "${fallback_list}" "${mirror}"

  if apt_install_with_source "fallback mirror ${mirror}" "${fallback_list}"; then
    cleanup_tmp_lists
    exit 0
  fi
done

cleanup_tmp_lists
echo "apt install failed after all fallback mirrors were attempted" >&2
exit 1
