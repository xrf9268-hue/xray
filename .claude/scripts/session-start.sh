#!/usr/bin/env bash
##
# SessionStart Hook for xray-fusion
#
# This hook runs automatically when a Claude Code session starts.
# It ensures development tools (shfmt, shellcheck, bats-core) are available.
#
# Trigger: Only on 'startup' events (matcher configured in .claude/settings.json)
# - startup: New session initialization (this hook runs)
# - resume/clear/compact: Other events (this hook does NOT run)
#
# Environment Detection:
# - CLAUDE_CODE_REMOTE=true: Web/iOS environment (auto-install tools)
# - CLAUDE_CODE_REMOTE=false or unset: Desktop environment (skip auto-install)
##

set -euo pipefail

echo "[SessionStart] Initializing environment..." >&2

# Detect if running in Claude Code web/iOS environment
is_remote_environment() {
  [[ "${CLAUDE_CODE_REMOTE:-false}" == "true" ]]
}

# Skip auto-installation in desktop environment
if ! is_remote_environment; then
  echo "[SessionStart] Desktop environment detected, skipping auto-installation" >&2
  echo "[SessionStart] Please install development tools manually:" >&2
  echo "  - shfmt: https://github.com/mvdan/sh" >&2
  echo "  - shellcheck: https://github.com/koalaman/shellcheck" >&2
  echo "  - bats-core: https://github.com/bats-core/bats-core" >&2
  exit 0
fi

echo "[SessionStart] Web/iOS environment detected, auto-installing development tools..." >&2

# Ensure ~/.local/bin and ~/.local/share exist and PATH is set
mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share"
export PATH="${HOME}/.local/bin:${PATH}"

# Helper function to install tool
install_tool() {
  local name="${1}"
  local version="${2}"
  local url="${3}"
  local target="${HOME}/.local/bin/${name}"

  # Skip if already installed
  if command -v "${name}" > /dev/null 2>&1; then
    echo "[SessionStart] ${name} already installed ($(${name} --version 2>&1 | head -1 || echo 'unknown'))" >&2
    return 0
  fi

  echo "[SessionStart] Installing ${name} ${version}..." >&2

  # Download to temp location
  local tmp_file="/tmp/${name}-$$.tmp"
  if curl -fsSL -o "${tmp_file}" "${url}"; then
    chmod +x "${tmp_file}"
    mv "${tmp_file}" "${target}"
    echo "[SessionStart] ${name} ${version} installed successfully" >&2
    return 0
  else
    echo "[SessionStart] Failed to install ${name}" >&2
    rm -f "${tmp_file}"
    return 1
  fi
}

# Install shfmt (shell formatter)
install_tool \
  "shfmt" \
  "v3.8.0" \
  "https://github.com/mvdan/sh/releases/download/v3.8.0/shfmt_v3.8.0_linux_amd64"

# Install shellcheck (shell linter)
install_shellcheck() {
  local target="${HOME}/.local/bin/shellcheck"

  # Skip if already installed
  if command -v shellcheck > /dev/null 2>&1; then
    echo "[SessionStart] shellcheck already installed ($(shellcheck --version 2>&1 | head -1 || echo 'unknown'))" >&2
    return 0
  fi

  echo "[SessionStart] Installing shellcheck v0.10.0..." >&2

  # Download and extract
  local tmp_dir="/tmp/shellcheck-$$"
  mkdir -p "${tmp_dir}"
  cd "${tmp_dir}"

  if curl -fsSL -o shellcheck.tar.xz \
    "https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz"; then
    tar -xf shellcheck.tar.xz
    mv shellcheck-v0.10.0/shellcheck "${target}"
    chmod +x "${target}"
    cd - > /dev/null
    rm -rf "${tmp_dir}"
    echo "[SessionStart] shellcheck v0.10.0 installed successfully" >&2
    return 0
  else
    echo "[SessionStart] Failed to install shellcheck" >&2
    cd - > /dev/null
    rm -rf "${tmp_dir}"
    return 1
  fi
}

install_shellcheck

# Install bats-core (test framework)
install_bats_core() {
  local bats_dir="${HOME}/.local/share/bats-core"
  local bats_bin="${HOME}/.local/bin/bats"

  # Skip if already installed
  if command -v bats > /dev/null 2>&1; then
    echo "[SessionStart] bats-core already installed ($(bats --version 2>&1 || echo 'unknown'))" >&2
    return 0
  fi

  echo "[SessionStart] Installing bats-core v1.11.0..." >&2

  # Download and extract
  local tmp_dir="/tmp/bats-core-$$"
  mkdir -p "${tmp_dir}"
  cd "${tmp_dir}"

  if curl -fsSL -o bats-core.tar.gz \
    "https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz"; then
    tar -xzf bats-core.tar.gz

    # Move to installation directory
    rm -rf "${bats_dir}"
    mv bats-core-1.11.0 "${bats_dir}"

    # Create symlink to bats executable
    ln -sf "${bats_dir}/bin/bats" "${bats_bin}"

    cd - > /dev/null
    rm -rf "${tmp_dir}"
    echo "[SessionStart] bats-core v1.11.0 installed successfully" >&2
    return 0
  else
    echo "[SessionStart] Failed to install bats-core" >&2
    cd - > /dev/null
    rm -rf "${tmp_dir}"
    return 1
  fi
}

install_bats_core

# Verify installations
echo "[SessionStart] Development tools ready:" >&2
command -v shfmt > /dev/null 2>&1 && echo "  ✓ shfmt $(shfmt --version)" >&2
command -v shellcheck > /dev/null 2>&1 && echo "  ✓ shellcheck $(shellcheck --version | head -1)" >&2
command -v bats > /dev/null 2>&1 && echo "  ✓ bats $(bats --version)" >&2

echo "[SessionStart] Environment initialized successfully" >&2
