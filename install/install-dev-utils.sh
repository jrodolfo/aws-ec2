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

Install optional developer utilities for EC2 hosts.
This script intentionally does not install 'act'.

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

install_pkg_if_present() {
    local pkg="$1"
    install_pkg_dnf "${pkg}"
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
    if ! is_pkg_installed_rpm dnf-plugins-core; then
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
    validate_os_amzn
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting developer utility installation"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"
    log "Excluding tool: act"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi

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
