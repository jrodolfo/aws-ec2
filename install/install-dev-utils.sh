#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: ./install/install-dev-utils.sh [OPTIONS]

Install optional developer utilities for EC2 hosts.
This script intentionally does not install 'act'.

Options:
  -n, --dry-run   Print actions without making changes
  -h, --help      Show this help
EOF
}

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
    if [[ "${DRY_RUN}" -eq 1 ]]; then
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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Missing required command: ${cmd}"
        exit 1
    fi
}

validate_os() {
    if [[ ! -f /etc/os-release ]]; then
        err "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "amzn" ]]; then
        warn "This script is tuned for Amazon Linux (detected ID=${ID:-unknown})."
        warn "Proceeding, but package names may differ."
    fi
}

is_pkg_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

install_pkg_if_present() {
    local pkg="$1"
    if is_pkg_installed "${pkg}"; then
        log "Already installed: ${pkg}"
        return 0
    fi

    if run_root dnf install -y "${pkg}"; then
        return 0
    fi

    return 1
}

install_github_cli() {
    if command -v gh >/dev/null 2>&1; then
        log "Already installed: gh"
        return 0
    fi

    if install_pkg_if_present gh; then
        return 0
    fi

    warn "Package 'gh' not available in current repos. Adding official GitHub CLI repo."
    if ! is_pkg_installed dnf-plugins-core; then
        run_root dnf install -y dnf-plugins-core || run_root dnf install -y 'dnf-command(config-manager)'
    fi
    run_root dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    run_root dnf install -y gh
}

install_fd() {
    if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
        log "Already installed: fd/fdfind"
        return 0
    fi

    if install_pkg_if_present fd-find; then
        return 0
    fi

    if install_pkg_if_present fd; then
        return 0
    fi

    warn "Could not install fd (fd-find/fd package unavailable)."
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
    log "Installed dev utility versions:"
    print_version_if_available "shellcheck" shellcheck --version
    print_version_if_available "shfmt" shfmt --version
    print_version_if_available "jq" jq --version
    print_version_if_available "yq" yq --version
    print_version_if_available "ripgrep" rg --version

    if command -v fd >/dev/null 2>&1; then
        printf '%-16s %s\n' "fd:" "$(fd --version 2>/dev/null | head -n1)"
    elif command -v fdfind >/dev/null 2>&1; then
        printf '%-16s %s\n' "fdfind:" "$(fdfind --version 2>/dev/null | head -n1)"
        warn "Binary is 'fdfind'. Optionally add alias: alias fd='fdfind'"
    else
        printf '%-16s %s\n' "fd/fdfind:" "not found"
    fi

    print_version_if_available "GitHub CLI" gh --version
}

main() {
    parse_args "$@"
    validate_os
    require_cmd dnf
    require_cmd rpm

    log "Starting developer utility installation"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run : enabled"
    log "Excluding tool: act"

    run_root dnf update -y

    install_pkg_if_present shellcheck || warn "shellcheck package not available"
    install_pkg_if_present shfmt || warn "shfmt package not available"
    install_pkg_if_present jq || warn "jq package not available"
    install_pkg_if_present yq || warn "yq package not available"
    install_pkg_if_present ripgrep || warn "ripgrep package not available"
    install_fd
    install_github_cli

    verify_installation
    log ""
    log "Done."
}

main "$@"
