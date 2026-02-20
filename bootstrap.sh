#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/dotfiles"
TOOLS_DIR="${SCRIPT_DIR}/tools"
BIN_DIR="${HOME}/.local/bin"
BACKUP_DIR="${HOME}/.bootstrap-backups/$(date +%Y%m%d-%H%M%S)"
MADE_BACKUP=0
DRY_RUN=0
FORCE=0

log() {
    printf '%s\n' "$*"
}

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [OPTIONS]

Install dotfiles and tools into the current user's home directory.

Options:
  -n, --dry-run   Show planned actions without changing files
  -f, --force     Reinstall files even when contents are unchanged
  -h, --help      Show this help
EOF
}

run_cmd() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] $*"
        return 0
    fi
    "$@"
}

ensure_backup_dir() {
    if [[ "${MADE_BACKUP}" -eq 0 ]]; then
        run_cmd mkdir -p "${BACKUP_DIR}"
        MADE_BACKUP=1
        log "Backup directory: ${BACKUP_DIR}"
    fi
}

backup_and_install_file() {
    local src="$1"
    local dest="$2"
    local mode="$3"

    if [[ ! -f "${src}" ]]; then
        log "Skipping missing file: ${src}"
        return 0
    fi

    if [[ "${FORCE}" -eq 0 ]] && [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
        log "Unchanged: ${dest}"
        return 0
    fi

    if [[ -e "${dest}" ]]; then
        ensure_backup_dir
        run_cmd cp -a "${dest}" "${BACKUP_DIR}/$(basename "${dest}")"
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            log "Would back up: ${dest}"
        else
            log "Backed up: ${dest}"
        fi
    fi

    run_cmd install -m "${mode}" "${src}" "${dest}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "Would install: ${dest}"
    else
        log "Installed: ${dest}"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -f|--force)
                FORCE=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    log "Setting up environment..."
    run_cmd mkdir -p "${BIN_DIR}"

    backup_and_install_file "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc" 0644
    backup_and_install_file "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile" 0644
    backup_and_install_file "${DOTFILES_DIR}/.vimrc" "${HOME}/.vimrc" 0644

    if [[ -f "${DOTFILES_DIR}/.gitconfig" ]]; then
        backup_and_install_file "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig" 0644
    elif [[ -f "${DOTFILES_DIR}/gitconfig" ]]; then
        backup_and_install_file "${DOTFILES_DIR}/gitconfig" "${HOME}/.gitconfig" 0644
    else
        log "Skipping gitconfig: no dotfiles/.gitconfig or dotfiles/gitconfig found"
    fi

    shopt -s nullglob
    local tool
    for tool in "${TOOLS_DIR}"/*; do
        [[ -f "${tool}" ]] || continue
        backup_and_install_file "${tool}" "${BIN_DIR}/$(basename "${tool}")" 0755
    done
    shopt -u nullglob

    log "Done. Start a new shell or run: source ~/.bashrc"
}

main "$@"
