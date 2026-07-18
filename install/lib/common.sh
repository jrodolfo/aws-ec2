#!/usr/bin/env bash

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

err() {
    printf 'ERROR: %s\n' "$*" >&2
}

run() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log "[dry-run] $*"
        return 0
    fi
    "$@"
}

run_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        run "$@"
    else
        run sudo "$@"
    fi
}

run_as_user() {
    local user_name="$1"
    shift
    if [[ "${EUID}" -eq 0 ]]; then
        run sudo -u "${user_name}" -H "$@"
    else
        run "$@"
    fi
}

run_as_user_shell() {
    local user_name="$1"
    shift
    local shell_command="$1"
    run_as_user "${user_name}" bash -lc "${shell_command}"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Missing required command: ${cmd}"
        exit 1
    fi
}

validate_os_amzn() {
    if [[ ! -f /etc/os-release ]]; then
        if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
            warn "Cannot detect OS: /etc/os-release not found. Continuing due to --dry-run."
            return 0
        fi
        err "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/etc/os-release
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "amzn" ]]; then
        warn "This script is tuned for Amazon Linux (detected ID=${ID:-unknown})."
        warn "Proceeding, but package names or behavior may differ."
    fi
}

resolve_user_home() {
    local user_name="$1"
    local home_dir=""
    if command -v getent >/dev/null 2>&1; then
        home_dir="$(getent passwd "${user_name}" 2>/dev/null | awk -F: '{print $6}')"
    fi
    if [[ -z "${home_dir}" ]]; then
        home_dir="${HOME}"
    fi
    printf '%s\n' "${home_dir}"
}

rpm_available() {
    command -v rpm >/dev/null 2>&1
}

is_pkg_installed_rpm() {
    local pkg="$1"
    rpm_available || return 1
    rpm -q "${pkg}" >/dev/null 2>&1
}

install_pkg_dnf() {
    local pkg="$1"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        run_root dnf install -y "${pkg}"
        return 0
    fi

    if is_pkg_installed_rpm "${pkg}"; then
        log "Already installed: ${pkg}"
        return 0
    fi

    run_root dnf install -y "${pkg}"
}
