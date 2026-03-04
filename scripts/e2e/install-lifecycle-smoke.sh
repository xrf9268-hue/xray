#!/usr/bin/env bash
set -eEuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER_NAME="xrf-smoke-$(date +%s)"
CURRENT_SCENARIO="setup"
DEFAULT_BASE_IMAGE="${XRF_SMOKE_BASE_IMAGE:-ubuntu:24.04}"
LOCAL_FALLBACK_IMAGE="${XRF_SMOKE_FALLBACK_IMAGE:-docker.950288.xyz/library/ubuntu:24.04}"

log() {
  printf '[smoke] %s\n' "$*"
}

run_in_container() {
  docker exec "${CONTAINER_NAME}" bash -lc "$1"
}

run_in_container_retry() {
  local cmd="$1"
  local attempts="${2:-5}"
  local delay=2
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if run_in_container "${cmd}"; then
      return 0
    fi

    if ((attempt == attempts)); then
      return 1
    fi

    log "command failed (attempt ${attempt}/${attempts}), retrying in ${delay}s"
    sleep "${delay}"
    delay=$((delay * 2))
  done
}

container_exists() {
  docker ps -a --format '{{.Names}}' | rg -Fx -- "${CONTAINER_NAME}" > /dev/null 2>&1
}

dump_failure_logs() {
  local rc="$1"
  log "failed during ${CURRENT_SCENARIO} (exit ${rc})"
  if container_exists; then
    docker exec "${CONTAINER_NAME}" bash -lc '
      shopt -s nullglob
      for f in /tmp/scenario*.log; do
        printf "===== %s =====\n" "${f}"
        tail -n 120 "${f}" || true
      done
    ' || true
  fi
}

on_error() {
  local rc="$?"
  dump_failure_logs "${rc}"
  exit "${rc}"
}

set_apt_mirror() {
  local base_url="$1"
  run_in_container "if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then sed -E -i 's|https?://[^/ ]+|${base_url}|g' /etc/apt/sources.list.d/ubuntu.sources; fi; if [ -f /etc/apt/sources.list ]; then sed -E -i 's|https?://[^/ ]+|${base_url}|g' /etc/apt/sources.list; fi"
}

install_test_dependencies() {
  local mirrors=(
    "http://ports.ubuntu.com"
    # Use HTTP mirrors for bootstrap reliability in minimal containers where
    # CA roots may not be available before ca-certificates is installed.
    "http://mirrors.tuna.tsinghua.edu.cn"
    "http://mirrors.aliyun.com"
    "http://mirrors.ustc.edu.cn"
  )
  local mirror

  for mirror in "${mirrors[@]}"; do
    log "trying apt mirror ${mirror}"
    set_apt_mirror "${mirror}"
    run_in_container "rm -rf /var/lib/apt/lists/*"
    if run_in_container_retry "export DEBIAN_FRONTEND=noninteractive; apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update > /dev/null && apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install -y bash ca-certificates curl unzip jq openssl iproute2 sudo > /dev/null" 3; then
      log "dependency install succeeded via ${mirror}"
      return 0
    fi
  done

  log "failed to install test dependencies from all mirrors"
  return 1
}

install_systemctl_mock() {
  run_in_container "cat > /usr/local/bin/systemctl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case \"\${1:-}\" in
  daemon-reload|enable|disable|start|stop|restart|reset-failed|is-active)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod 0755 /usr/local/bin/systemctl"
}

cleanup() {
  if [[ "${XRF_SMOKE_KEEP_CONTAINER:-0}" == "1" ]]; then
    log "keeping container ${CONTAINER_NAME} (XRF_SMOKE_KEEP_CONTAINER=1)"
    return 0
  fi
  docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
}
trap on_error ERR
trap cleanup EXIT

select_base_image() {
  local selected="${DEFAULT_BASE_IMAGE}"
  SELECTED_BASE_IMAGE=""

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    log "GitHub Actions detected; using official image only: ${selected}"
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  if docker image inspect "${selected}" > /dev/null 2>&1; then
    log "using locally cached base image ${selected}"
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  log "pulling base image ${selected}"
  if docker pull "${selected}" > /dev/null 2>&1; then
    SELECTED_BASE_IMAGE="${selected}"
    return 0
  fi

  if docker image inspect "${LOCAL_FALLBACK_IMAGE}" > /dev/null 2>&1; then
    log "using locally cached fallback image ${LOCAL_FALLBACK_IMAGE}"
    SELECTED_BASE_IMAGE="${LOCAL_FALLBACK_IMAGE}"
    return 0
  fi

  log "official image pull failed, falling back to ${LOCAL_FALLBACK_IMAGE}"
  if docker pull "${LOCAL_FALLBACK_IMAGE}" > /dev/null 2>&1; then
    SELECTED_BASE_IMAGE="${LOCAL_FALLBACK_IMAGE}"
    return 0
  fi

  log "failed to pull both ${selected} and ${LOCAL_FALLBACK_IMAGE}"
  return 1
}

if ! command -v docker > /dev/null 2>&1; then
  log "docker is required"
  exit 1
fi

log "starting container ${CONTAINER_NAME}"
select_base_image
BASE_IMAGE="${SELECTED_BASE_IMAGE}"
log "starting container ${CONTAINER_NAME} with image ${BASE_IMAGE}"
docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE}" sleep infinity > /dev/null

log "installing test dependencies"
CURRENT_SCENARIO="dependency install"
install_test_dependencies

log "copying workspace"
CURRENT_SCENARIO="copy workspace"
run_in_container "mkdir -p /workspace"
docker cp "${ROOT_DIR}/." "${CONTAINER_NAME}:/workspace/xray"

log "installing systemctl mock for containerized test"
CURRENT_SCENARIO="install systemctl mock"
install_systemctl_mock

log "scenario 1: fresh install (default paths)"
CURRENT_SCENARIO="scenario 1 fresh install"
run_in_container "cd /workspace/xray && ./bin/xrf install --topology reality-only --yes > /tmp/scenario1.log 2>&1"
run_in_container "test -x /usr/local/bin/xray"
run_in_container "test -L /usr/local/etc/xray/active"
run_in_container "jq -e '.name == \"reality-only\"' /var/lib/xray-fusion/state.json > /dev/null"

log "scenario 2: in-place reinstall creates backup"
CURRENT_SCENARIO="scenario 2 in-place reinstall"
run_in_container "cd /workspace/xray && ./bin/xrf install --topology reality-only --yes > /tmp/scenario2.log 2>&1"
run_in_container "ls /var/lib/xray-fusion/backups/*.metadata.json > /dev/null"

log "scenario 3: uninstall is idempotent and reinstall works"
CURRENT_SCENARIO="scenario 3 uninstall/reinstall"
run_in_container "cd /workspace/xray && ./bin/xrf uninstall > /tmp/scenario3-uninstall1.log 2>&1"
run_in_container "cd /workspace/xray && ./bin/xrf uninstall > /tmp/scenario3-uninstall2.log 2>&1"
run_in_container "cd /workspace/xray && ./bin/xrf install --topology reality-only --yes > /tmp/scenario3-reinstall.log 2>&1"
run_in_container "jq -e '.name == \"reality-only\"' /var/lib/xray-fusion/state.json > /dev/null"

log "scenario 4: topology switch to vision-reality with custom cert dir"
CURRENT_SCENARIO="scenario 4 topology switch"
run_in_container "mkdir -p /tmp/certs && openssl req -x509 -nodes -newkey rsa:2048 -keyout /tmp/certs/privkey.pem -out /tmp/certs/fullchain.pem -days 1 -subj '/CN=example.com' > /dev/null 2>&1 && chmod 644 /tmp/certs/fullchain.pem && chmod 640 /tmp/certs/privkey.pem"
run_in_container "cd /workspace/xray && XRAY_CERT_DIR=/tmp/certs ./bin/xrf install --topology vision-reality --domain example.com --yes > /tmp/scenario4.log 2>&1"
run_in_container "jq -e '.name == \"vision-reality\" and .xray.cert_dir == \"/tmp/certs\"' /var/lib/xray-fusion/state.json > /dev/null"
run_in_container "conf=\$(readlink -f /usr/local/etc/xray/active)/05_inbounds.json; jq -e '.inbounds | length == 2' \"\${conf}\" > /dev/null"

log "scenario 5: custom prefix/etc renders dynamic systemd unit paths"
CURRENT_SCENARIO="scenario 5 custom paths"
run_in_container "cd /workspace/xray && XRF_PREFIX=/tmp/xrf/prefix XRF_ETC=/tmp/xrf/etc XRF_VAR=/tmp/xrf/var ./bin/xrf install --topology reality-only --yes > /tmp/scenario5.log 2>&1"
run_in_container "grep -q 'ExecStart=/tmp/xrf/prefix/bin/xray run -confdir /tmp/xrf/etc/xray/active -format json' /etc/systemd/system/xray.service"
run_in_container "grep -q 'ReadWritePaths=/tmp/xrf/etc/xray' /etc/systemd/system/xray.service"

log "all lifecycle smoke scenarios passed"
