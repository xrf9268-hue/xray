#!/usr/bin/env bash
# Dependency checking utilities
# NOTE: This file is sourced. Strict mode is set by the calling script or core::init()

# Source guard: prevent double-sourcing
[[ -n "${_XRF_DEPENDENCIES_LOADED:-}" ]] && return 0
readonly _XRF_DEPENDENCIES_LOADED=1

# Global cache for detected package manager (performance optimization)
# Avoids repeated command -v checks across multiple function calls
_XRF_DETECTED_PM=""

##
# Check critical dependencies before proceeding
#
# This function performs fail-fast validation of required system tools
# before attempting any installation operations. It ensures:
# - At least one download tool is available (git, curl, or wget)
# - systemctl is available (systemd is required for service management)
# - Basic POSIX utilities are present (mktemp, tar, gzip)
#
# The function logs detailed information about found/missing tools to help
# users quickly identify and resolve dependency issues.
#
# Globals:
#   None (uses core::log if available, otherwise logs to stderr)
#
# Returns:
#   0 - All critical dependencies are available
#   1 - One or more critical dependencies are missing
#
# Example:
#   deps::check_critical || error_exit "Missing critical dependencies"
##
deps::check_critical() {
  local missing=()

  # Check downloader availability (need at least one)
  local has_downloader=false
  for tool in git curl wget; do
    if command -v "${tool}" > /dev/null 2>&1; then
      has_downloader=true
      if declare -f core::log > /dev/null 2>&1; then
        core::log debug "found downloader" "$(printf '{"tool":"%s"}' "${tool}")"
      fi
      break
    fi
  done

  if [[ "${has_downloader}" == "false" ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "at least one download tool required: git, curl, or wget" '{}'
    else
      printf '[ERROR] At least one download tool required: git, curl, or wget\n' >&2
    fi
    return 1
  fi

  # Check systemctl (systemd required)
  if ! command -v systemctl > /dev/null 2>&1; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "systemctl not found (systemd required)" '{}'
    else
      printf '[ERROR] systemctl not found (systemd required)\n' >&2
    fi
    missing+=("systemctl")
  fi

  # Check basic utilities
  for tool in mktemp tar gzip; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
      if declare -f core::log > /dev/null 2>&1; then
        core::log warn "missing utility" "$(printf '{"tool":"%s"}' "${tool}")"
      else
        printf '[WARN] missing utility: %s\n' "${tool}" >&2
      fi
      missing+=("${tool}")
    fi
  done

  # Fail if any critical tool is missing
  if [[ ${#missing[@]} -gt 0 ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "missing critical dependencies" "$(printf '{"tools":"%s"}' "${missing[*]}")"
    else
      printf '[ERROR] missing critical dependencies: %s\n' "${missing[*]}" >&2
    fi
    return 1
  fi

  if declare -f core::log > /dev/null 2>&1; then
    core::log debug "all critical dependencies available" '{}'
  fi
  return 0
}

##
# Check optional dependencies
#
# This function checks for optional tools that enhance functionality but
# are not strictly required for basic installation. Missing optional tools
# will generate warnings but will not cause the function to fail.
#
# Optional tools checked:
# - jq: JSON processing (used for config manipulation if available)
# - openssl: TLS certificate operations (enhanced validation)
# - gpg: GPG signature verification (enhanced security)
#
# These tools may be installed automatically by the installer if needed,
# or their functionality may be gracefully degraded.
#
# Globals:
#   None (uses core::log if available, otherwise logs to stderr)
#
# Returns:
#   0 - Always succeeds (logs warnings for missing tools)
#
# Example:
#   deps::check_optional  # Always safe to call
##
deps::check_optional() {
  local optional_tools="jq openssl gpg"
  local missing=()

  for tool in ${optional_tools}; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
      missing+=("${tool}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log warn "missing optional tools (functionality may be limited)" "$(printf '{"tools":"%s"}' "${missing[*]}")"
    else
      printf '[WARN] missing optional tools (functionality may be limited): %s\n' "${missing[*]}" >&2
    fi
  fi

  return 0
}

##
# Print user-friendly error message for missing dependencies
#
# This function generates a helpful error message with installation
# instructions for common Linux distributions when critical dependencies
# are missing.
#
# Arguments:
#   $@ - List of missing tool names
#
# Output:
#   Multi-line error message with installation instructions to stderr
#
# Returns:
#   0 - Always succeeds
#
# Example:
#   deps::print_install_help "curl" "tar" "systemctl"
##
deps::print_install_help() {
  local missing=("$@")

  printf '\n=== Missing Critical Dependencies ===\n' >&2
  printf 'Missing tools: %s\n\n' "${missing[*]}" >&2

  printf 'Install based on your system:\n\n' >&2

  printf '# Debian/Ubuntu\n' >&2
  printf 'sudo apt-get update && sudo apt-get install -y' >&2
  for tool in "${missing[@]}"; do
    case "${tool}" in
      systemctl) printf ' systemd' >&2 ;;
      *) printf ' %s' "${tool}" >&2 ;;
    esac
  done
  printf '\n\n' >&2

  printf '# CentOS/RHEL/Rocky\n' >&2
  printf 'sudo yum install -y' >&2
  for tool in "${missing[@]}"; do
    case "${tool}" in
      systemctl) printf ' systemd' >&2 ;;
      *) printf ' %s' "${tool}" >&2 ;;
    esac
  done
  printf '\n\n' >&2

  printf '# Arch Linux\n' >&2
  printf 'sudo pacman -S' >&2
  for tool in "${missing[@]}"; do
    case "${tool}" in
      systemctl) printf ' systemd' >&2 ;;
      *) printf ' %s' "${tool}" >&2 ;;
    esac
  done
  printf '\n\n' >&2

  return 0
}

##
# Detect available package manager
#
# Detects the system's package manager by checking for common package
# management tools. Returns the name of the first available package manager.
# Results are cached in _XRF_DETECTED_PM to avoid repeated command -v checks.
#
# Supported package managers:
# - apt-get (Debian/Ubuntu)
# - yum (CentOS/RHEL)
# - dnf (Fedora/RHEL 8+)
# - apk (Alpine)
# - zypper (openSUSE)
# - pacman (Arch Linux)
#
# Globals:
#   _XRF_DETECTED_PM - Cache variable for detected package manager
#
# Output:
#   Package manager name (apt-get, yum, dnf, apk, zypper, or pacman) to stdout
#
# Returns:
#   0 - Package manager detected
#   1 - No supported package manager found
#
# Example:
#   pm=$(deps::detect_package_manager) && echo "Using: ${pm}"
##
deps::detect_package_manager() {
  # Return cached result if available
  if [[ -n "${_XRF_DETECTED_PM}" ]]; then
    echo "${_XRF_DETECTED_PM}"
    return 0
  fi

  local managers=("apt-get" "dnf" "yum" "apk" "zypper" "pacman")

  for pm in "${managers[@]}"; do
    if command -v "${pm}" > /dev/null 2>&1; then
      _XRF_DETECTED_PM="${pm}" # Cache the result
      echo "${pm}"
      return 0
    fi
  done

  return 1
}

##
# Install packages using system package manager
#
# Automatically detects the system package manager and installs the specified
# packages. Handles privilege escalation (sudo) when needed. Runs non-interactively
# to avoid prompts.
#
# Arguments:
#   $@ - List of package names to install
#
# Globals:
#   Uses core::log if available for structured logging
#
# Returns:
#   0 - All packages installed successfully
#   1 - Package manager not detected or installation failed
#
# Example:
#   deps::install_packages qrencode curl
##
deps::install_packages() {
  local packages=("$@")

  if [[ ${#packages[@]} -eq 0 ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log warn "no packages specified for installation" '{}'
    fi
    return 0
  fi

  # Detect package manager
  local pm
  if ! pm=$(deps::detect_package_manager); then
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "no supported package manager found" '{}'
    else
      printf '[ERROR] No supported package manager found\n' >&2
    fi
    return 1
  fi

  if declare -f core::log > /dev/null 2>&1; then
    core::log info "installing packages" "$(printf '{"packages":"%s","manager":"%s"}' "${packages[*]}" "${pm}")"
  else
    printf '[INFO] Installing packages: %s (using %s)\n' "${packages[*]}" "${pm}" >&2
  fi

  # Prepare installation command
  local cmd=()
  local need_sudo=false

  # Check if we need sudo
  if [[ "${EUID}" -ne 0 ]] && command -v sudo > /dev/null 2>&1; then
    need_sudo=true
  fi

  # Build command based on package manager
  case "${pm}" in
    apt-get)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(apt-get install -y "${packages[@]}")
      ;;
    yum)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(yum install -y "${packages[@]}")
      ;;
    dnf)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(dnf install -y "${packages[@]}")
      ;;
    apk)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(apk add --no-cache "${packages[@]}")
      ;;
    zypper)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(zypper install -y "${packages[@]}")
      ;;
    pacman)
      [[ "${need_sudo}" == "true" ]] && cmd+=(sudo)
      cmd+=(pacman -S --noconfirm "${packages[@]}")
      ;;
    *)
      if declare -f core::log > /dev/null 2>&1; then
        core::log error "unsupported package manager" "$(printf '{"manager":"%s"}' "${pm}")"
      fi
      return 1
      ;;
  esac

  # Execute installation
  # Keep stderr visible for sudo password prompts and error messages
  # Only redirect stdout to hide verbose package manager output
  if "${cmd[@]}" > /dev/null; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log info "packages installed successfully" "$(printf '{"packages":"%s"}' "${packages[*]}")"
    else
      printf '[INFO] Packages installed successfully: %s\n' "${packages[*]}" >&2
    fi
    return 0
  else
    if declare -f core::log > /dev/null 2>&1; then
      core::log error "package installation failed" "$(printf '{"packages":"%s","rc":"%s"}' "${packages[*]}" "$?")"
    else
      printf '[ERROR] Package installation failed: %s\n' "${packages[*]}" >&2
    fi
    return 1
  fi
}

##
# Check and install plugin dependencies
#
# Checks if plugin dependencies are installed. If any are missing, prompts
# user and installs them automatically.
#
# Arguments:
#   $1 - Plugin ID (for logging)
#   $@ - List of command names to check (e.g., qrencode, curl)
#
# Returns:
#   0 - All dependencies satisfied (already installed or successfully installed)
#   1 - Dependencies missing and installation failed/declined
#
# Example:
#   deps::check_and_install_plugin_deps "links-qr" qrencode
##
deps::check_and_install_plugin_deps() {
  local plugin_id="${1}"
  shift
  local deps=("$@")

  if [[ ${#deps[@]} -eq 0 ]]; then
    return 0
  fi

  # Check which dependencies are missing
  local missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" > /dev/null 2>&1; then
      missing+=("${dep}")
    fi
  done

  # All dependencies satisfied
  if [[ ${#missing[@]} -eq 0 ]]; then
    if declare -f core::log > /dev/null 2>&1; then
      core::log debug "all plugin dependencies satisfied" "$(printf '{"plugin":"%s","deps":"%s"}' "${plugin_id}" "${deps[*]}")"
    fi
    return 0
  fi

  # Dependencies missing - prompt user for installation
  if declare -f core::log > /dev/null 2>&1; then
    core::log info "plugin has missing dependencies" "$(printf '{"plugin":"%s","missing":"%s"}' "${plugin_id}" "${missing[*]}")"
  else
    printf '[INFO] Plugin %s requires: %s\n' "${plugin_id}" "${missing[*]}" >&2
  fi

  # Auto-install in non-interactive mode or when XRF_AUTO_INSTALL_DEPS=true
  local auto_install=false
  if [[ "${XRF_AUTO_INSTALL_DEPS:-false}" == "true" ]] || [[ ! -t 0 ]]; then
    auto_install=true
  else
    # Interactive prompt
    printf 'Install missing dependencies? [Y/n] ' >&2
    read -r response
    if [[ "${response}" =~ ^([Yy]|)$ ]]; then
      auto_install=true
    fi
  fi

  if [[ "${auto_install}" == "true" ]]; then
    deps::install_packages "${missing[@]}"
    return $?
  else
    if declare -f core::log > /dev/null 2>&1; then
      core::log warn "plugin dependencies not installed" "$(printf '{"plugin":"%s","missing":"%s"}' "${plugin_id}" "${missing[*]}")"
    else
      printf '[WARN] Plugin dependencies not installed: %s\n' "${missing[*]}" >&2
    fi
    return 1
  fi
}
