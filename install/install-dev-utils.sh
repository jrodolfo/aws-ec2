#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
SKIP_UPDATE=0

usage() {
    cat <<'EOF'
Usage: ./install/install-dev-utils.sh [OPTIONS]

Install minimal developer utilities for EC2 hosts:
- ripgrep (rg)
- pipx

Options:
  --no-update     Skip system package update
  -n, --dry-run   Print actions without making changes
  -h, --help      Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-update)
                SKIP_UPDATE=1
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

target_user_name() {
    printf '%s\n' "${SUDO_USER:-${USER}}"
}

target_user_home() {
    local user_name home_dir
    user_name="$(target_user_name)"
    home_dir=""
    if command -v getent >/dev/null 2>&1; then
        home_dir="$(getent passwd "${user_name}" 2>/dev/null | awk -F: '{print $6}')"
    fi
    if [[ -z "${home_dir}" ]]; then
        home_dir="${HOME}"
    fi
    printf '%s\n' "${home_dir}"
}

run_as_login_user() {
    if [[ "${EUID}" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "${SUDO_USER}" -H "$@"
    else
        "$@"
    fi
}

add_path_now() {
    local path_dir="$1"
    if [[ ":${PATH}:" != *":${path_dir}:"* ]]; then
        export PATH="${path_dir}:${PATH}"
    fi
}

ensure_export_in_bashrc() {
    local user_home="$1"
    local export_line="$2"
    local bashrc_path="${user_home}/.bashrc"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        if [[ -f "${bashrc_path}" ]] && grep -Fq "${export_line}" "${bashrc_path}"; then
            log "Already present in ${bashrc_path}: ${export_line}"
        else
            log "[dry-run] Would add to ${bashrc_path}: ${export_line}"
        fi
        return 0
    fi

    if [[ ! -f "${bashrc_path}" ]]; then
        touch "${bashrc_path}"
    fi

    if ! grep -Fq "${export_line}" "${bashrc_path}"; then
        printf '\n%s\n' "${export_line}" >> "${bashrc_path}"
        log "Added to ${bashrc_path}: ${export_line}"
    else
        log "Already present in ${bashrc_path}: ${export_line}"
    fi
}

ensure_cargo_path() {
    local user_home cargo_bin
    user_home="$(target_user_home)"
    cargo_bin="${user_home}/.cargo/bin"
    # shellcheck disable=SC2016
    ensure_export_in_bashrc "${user_home}" 'export PATH="$HOME/.cargo/bin:$PATH"'
    add_path_now "${cargo_bin}"
}

ensure_local_bin_path() {
    local user_home local_bin
    user_home="$(target_user_home)"
    local_bin="${user_home}/.local/bin"
    # shellcheck disable=SC2016
    ensure_export_in_bashrc "${user_home}" 'export PATH="$HOME/.local/bin:$PATH"'
    add_path_now "${local_bin}"
}

try_install_pkg() {
    local pkg="$1"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        run_root dnf install -y "${pkg}"
        return 0
    fi

    if is_pkg_installed_rpm "${pkg}"; then
        log "Already installed: ${pkg}"
        return 0
    fi

    run_root dnf install -y "${pkg}" >/dev/null 2>&1
}

install_ripgrep() {
    if command -v rg >/dev/null 2>&1; then
        log "Already installed: ripgrep"
        return 0
    fi

    if try_install_pkg ripgrep && command -v rg >/dev/null 2>&1; then
        log "ripgrep installed from package repository"
        return 0
    fi

    warn "ripgrep package unavailable; trying cargo fallback."
    if ! try_install_pkg cargo; then
        err "Could not install cargo for ripgrep fallback."
        return 1
    fi

    ensure_cargo_path
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would run cargo install ripgrep"
        return 0
    fi

    run_as_login_user cargo install ripgrep >/dev/null 2>&1 || {
        err "cargo install ripgrep failed."
        return 1
    }

    ensure_cargo_path
    if command -v rg >/dev/null 2>&1; then
        warn "If this shell still cannot find rg, run: source ~/.bashrc"
        return 0
    fi

    err "ripgrep install completed, but rg is still not available."
    return 1
}

install_pipx() {
    if command -v pipx >/dev/null 2>&1; then
        log "Already installed: pipx"
        ensure_local_bin_path
        return 0
    fi

    if try_install_pkg pipx && command -v pipx >/dev/null 2>&1; then
        log "pipx installed from package repository"
        ensure_local_bin_path
        return 0
    fi

    warn "pipx package unavailable; trying python user install."
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would run python3 -m pip install --user pipx"
        ensure_local_bin_path
        return 0
    fi

    require_cmd python3
    run_as_login_user python3 -m pip install --user pipx >/dev/null 2>&1 || {
        err "python3 -m pip install --user pipx failed."
        return 1
    }
    ensure_local_bin_path
    command -v pipx >/dev/null 2>&1 || [[ -x "$(target_user_home)/.local/bin/pipx" ]]
}

print_version_if_available() {
    local label="$1"
    local bin="$2"
    local arg="$3"
    if command -v "${bin}" >/dev/null 2>&1; then
        printf '%-16s %s\n' "${label}:" "$("${bin}" "${arg}" 2>/dev/null | head -n1)"
    else
        printf '%-16s %s\n' "${label}:" "not found"
    fi
}

verify_installation() {
    log ""
    log "Installed minimal dev utility versions:"
    print_version_if_available "ripgrep" rg --version
    print_version_if_available "pipx" pipx --version
}

main() {
    parse_args "$@"
    validate_os_amzn
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting minimal developer utility installation"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi

    install_ripgrep
    install_pipx
    verify_installation
    log ""
    log "Done."
}

main "$@"
