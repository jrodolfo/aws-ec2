#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
SKIP_UPDATE=0

usage() {
    cat <<'EOF'
Usage: ./install/install-extras.sh [OPTIONS]

Install optional extras for EC2 environments.
These tools are not required for the base server setup.

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

install_actionlint() {
    if command -v actionlint >/dev/null 2>&1; then
        log "Already installed: actionlint"
        return 0
    fi

    if try_install_pkg actionlint; then
        return 0
    fi

    local arch=""
    local version="${ACTIONLINT_VERSION:-1.7.4}"
    local tmp_dir="/tmp/aws-ec2-actionlint"
    local tarball="${tmp_dir}/actionlint.tar.gz"
    local url=""

    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            warn "Unsupported architecture for actionlint fallback: $(uname -m)"
            return 1
            ;;
    esac

    require_cmd curl
    require_cmd tar
    url="https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_linux_${arch}.tar.gz"
    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    run curl -fsSL -o "${tarball}" "${url}"
    run tar -xzf "${tarball}" -C "${tmp_dir}"
    run_root install -m 0755 "${tmp_dir}/actionlint" /usr/local/bin/actionlint
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

main() {
    parse_args "$@"
    validate_os_amzn
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting optional extras installation"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi

    try_install_pkg shellcheck || warn "shellcheck package not available"
    try_install_pkg shfmt || warn "shfmt package not available"
    try_install_pkg pre-commit || warn "pre-commit package not available"
    try_install_pkg yamllint || warn "yamllint package not available"
    try_install_pkg bats || try_install_pkg bats-core || warn "bats package not available"
    try_install_pkg git-delta || warn "git-delta package not available"
    try_install_pkg fzf || warn "fzf package not available"
    try_install_pkg zoxide || warn "zoxide package not available"
    try_install_pkg just || warn "just package not available"
    try_install_pkg tokei || warn "tokei package not available"
    try_install_pkg hyperfine || warn "hyperfine package not available"
    install_actionlint || warn "actionlint could not be installed"

    log ""
    log "Installed extras versions:"
    print_version_if_available "shellcheck" shellcheck --version
    print_version_if_available "shfmt" shfmt --version
    print_version_if_available "pre-commit" pre-commit --version
    print_version_if_available "yamllint" yamllint --version
    print_version_if_available "bats" bats --version
    print_version_if_available "delta" delta --version
    print_version_if_available "fzf" fzf --version
    print_version_if_available "zoxide" zoxide --version
    print_version_if_available "just" just --version
    print_version_if_available "tokei" tokei --version
    print_version_if_available "hyperfine" hyperfine --version
    print_version_if_available "actionlint" actionlint -version
    log ""
    log "Done."
}

main "$@"
