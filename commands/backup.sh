#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${HERE}/lib/core.sh"
. "${HERE}/lib/backup.sh"

usage() {
  cat << 'EOF'
Usage: xrf backup <command> [options]

Manage Xray configuration backups.

Commands:
  create [--name <name>] [--encrypt] [--password <password>|--password-file <path>]
                            Create a new backup (optionally encrypted)
  list                      List available backups
  restore <name> [--password <password>|--password-file <path>]
                            Restore from backup (password needed for encrypted backups)
  delete <name>             Delete a backup
  verify <name>             Verify backup integrity

Options:
  --name <name>             Custom backup name (for create command)
  --encrypt                 Encrypt archive with AES-256-CBC + PBKDF2
  --password <password>     Encryption password (min 32 chars)
  --password-file <path>    Read encryption password from file
  --json                    Output in JSON format (for list command)
  --help, -h                Show this help

Examples:
  # Create backup with auto-generated name
  xrf backup create

  # Create backup with custom name
  xrf backup create --name pre-upgrade

  # Create encrypted backup (auto-generate password)
  xrf backup create --name secure-copy --encrypt

  # Create encrypted backup with explicit password
  xrf backup create --name secure-copy --encrypt --password-file /root/backup.pass

  # List all backups
  xrf backup list

  # List backups in JSON format
  xrf backup list --json

  # Restore from backup
  xrf backup restore backup-20231201-120000

  # Restore encrypted backup
  xrf backup restore secure-copy-20231201-120000 --password-file /root/backup.pass

  # Verify backup integrity
  xrf backup verify backup-20231201-120000

  # Delete old backup
  xrf backup delete backup-20231101-100000

EOF
}

main() {
  core::init "${@}"

  local command="${1:-}"
  shift || true

  case "${command}" in
    create)
      # Parse options
      local backup_name=""
      local encrypt="false"
      local password=""
      local password_file=""
      while [[ $# -gt 0 ]]; do
        case "${1}" in
          --name)
            backup_name="${2:-}"
            if [[ -z "${backup_name}" ]]; then
              core::log error "missing value for --name" "{}"
              exit 1
            fi
            shift 2
            ;;
          --encrypt)
            encrypt="true"
            shift
            ;;
          --password)
            password="${2:-}"
            if [[ -z "${password}" ]]; then
              core::log error "missing value for --password" "{}"
              exit 1
            fi
            shift 2
            ;;
          --password-file)
            password_file="${2:-}"
            if [[ -z "${password_file}" ]]; then
              core::log error "missing value for --password-file" "{}"
              exit 1
            fi
            shift 2
            ;;
          --help | -h)
            usage
            exit 0
            ;;
          *)
            core::log error "unknown option" "$(printf '{"option":"%s"}' "${1}")"
            usage
            exit 1
            ;;
        esac
      done

      if [[ -n "${password}" && -n "${password_file}" ]]; then
        core::log error "use either --password or --password-file, not both" "{}"
        exit 1
      fi
      if [[ "${encrypt}" != "true" && (-n "${password}" || -n "${password_file}") ]]; then
        core::log error "password options require --encrypt" "{}"
        exit 1
      fi
      if [[ -n "${password_file}" ]]; then
        if [[ ! -f "${password_file}" ]]; then
          core::log error "password file not found" "$(printf '{"file":"%s"}' "${password_file}")"
          exit 1
        fi
        password="$(tr -d '\r\n' < "${password_file}")"
      fi

      # Create backup
      if ! backup::create "${backup_name}" "${encrypt}" "${password}"; then
        exit 1
      fi
      if [[ "${encrypt}" == "true" && -n "${BACKUP_LAST_PASSWORD:-}" ]]; then
        printf '\nEncryption password: %s\n' "${BACKUP_LAST_PASSWORD}"
        printf '⚠️ Save this password securely. It cannot be recovered.\n\n'
      fi
      ;;

    list)
      # Parse options
      while [[ $# -gt 0 ]]; do
        case "${1}" in
          --json)
            export XRF_JSON="true"
            shift
            ;;
          --help | -h)
            usage
            exit 0
            ;;
          *)
            core::log error "unknown option" "$(printf '{"option":"%s"}' "${1}")"
            usage
            exit 1
            ;;
        esac
      done

      # List backups
      backup::list
      ;;

    restore)
      local backup_name="${1:-}"
      local password=""
      local password_file=""
      shift || true

      if [[ -z "${backup_name}" ]]; then
        core::log error "backup name required" "{}"
        usage
        exit 1
      fi

      while [[ $# -gt 0 ]]; do
        case "${1}" in
          --password)
            password="${2:-}"
            if [[ -z "${password}" ]]; then
              core::log error "missing value for --password" "{}"
              exit 1
            fi
            shift 2
            ;;
          --password-file)
            password_file="${2:-}"
            if [[ -z "${password_file}" ]]; then
              core::log error "missing value for --password-file" "{}"
              exit 1
            fi
            shift 2
            ;;
          --help | -h)
            usage
            exit 0
            ;;
          *)
            core::log error "unknown option" "$(printf '{"option":"%s"}' "${1}")"
            usage
            exit 1
            ;;
        esac
      done

      if [[ -n "${password}" && -n "${password_file}" ]]; then
        core::log error "use either --password or --password-file, not both" "{}"
        exit 1
      fi
      if [[ -n "${password_file}" ]]; then
        if [[ ! -f "${password_file}" ]]; then
          core::log error "password file not found" "$(printf '{"file":"%s"}' "${password_file}")"
          exit 1
        fi
        password="$(tr -d '\r\n' < "${password_file}")"
      fi

      # Confirmation prompt
      printf '\n⚠️  WARNING: This will replace your current configuration!\n\n'
      printf 'Backup to restore: %s\n' "${backup_name}"
      printf 'Current configuration will be backed up automatically.\n\n'

      # Skip confirmation if --yes flag is set
      if [[ "${XRF_YES:-false}" != "true" ]]; then
        read -rp "Continue with restore? [y/N] " confirm
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
          core::log info "restore cancelled" "{}"
          exit 0
        fi
      fi

      # Restore backup
      if ! backup::restore "${backup_name}" "${password}"; then
        exit 1
      fi
      ;;

    delete)
      local backup_name="${1:-}"

      if [[ -z "${backup_name}" ]]; then
        core::log error "backup name required" "{}"
        usage
        exit 1
      fi

      # Confirmation prompt
      if [[ "${XRF_YES:-false}" != "true" ]]; then
        read -rp "Delete backup '${backup_name}'? [y/N] " confirm
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
          core::log info "deletion cancelled" "{}"
          exit 0
        fi
      fi

      # Delete backup
      if ! backup::delete "${backup_name}"; then
        exit 1
      fi
      ;;

    verify)
      local backup_name="${1:-}"

      if [[ -z "${backup_name}" ]]; then
        core::log error "backup name required" "{}"
        usage
        exit 1
      fi

      # Verify backup
      if backup::verify "${backup_name}"; then
        printf '\n✓ Backup integrity verified: %s\n\n' "${backup_name}"
        exit 0
      else
        printf '\n✗ Backup verification failed: %s\n\n' "${backup_name}"
        exit 1
      fi
      ;;

    --help | -h | "")
      usage
      exit 0
      ;;

    *)
      core::log error "unknown command" "$(printf '{"command":"%s"}' "${command}")"
      usage
      exit 1
      ;;
  esac
}

main "${@}"
