#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
SKIP_UPDATE=0
MISSING_REQUIRED=()
MISSING_OPTIONAL=()
REQUIRED_TOOLS=(rg jq yq gh actionlint)
OPTIONAL_TOOLS=(shellcheck shfmt pre-commit yamllint bats delta fzf zoxide just tokei hyperfine watch fd)

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

    if run_root dnf install -y "${pkg}" >/dev/null 2>&1; then
        log "Installed: ${pkg}"
        return 0
    fi

    return 1
}

cargo_install_tool() {
    local crate="$1"
    local bin="$2"

    if command -v "${bin}" >/dev/null 2>&1; then
        log "Already installed: ${bin}"
        return 0
    fi

    if ! try_install_pkg cargo; then
        return 1
    fi

    ensure_cargo_path
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would run cargo install ${crate}"
        return 0
    fi

    run_as_login_user cargo install "${crate}" >/dev/null 2>&1 || return 1
    ensure_cargo_path
    command -v "${bin}" >/dev/null 2>&1 || [[ -x "$(target_user_home)/.cargo/bin/${bin}" ]]
}

install_python_tool_with_pipx() {
    local package="$1"
    local bin="$2"

    if command -v "${bin}" >/dev/null 2>&1; then
        log "Already installed: ${bin}"
        return 0
    fi

    if ! command -v pipx >/dev/null 2>&1; then
        if ! try_install_pkg pipx; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log "[dry-run] Would run python3 -m pip install --user pipx"
            else
                require_cmd python3
                run_as_login_user python3 -m pip install --user pipx >/dev/null 2>&1 || return 1
            fi
        fi
    fi

    ensure_local_bin_path
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would run pipx install ${package}"
        return 0
    fi

    if run_as_login_user pipx list --short 2>/dev/null | grep -Fxq "${package}"; then
        log "Already installed via pipx: ${package}"
        return 0
    fi

    run_as_login_user pipx install "${package}" >/dev/null 2>&1 || return 1
    ensure_local_bin_path
    command -v "${bin}" >/dev/null 2>&1 || [[ -x "$(target_user_home)/.local/bin/${bin}" ]]
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
    if cargo_install_tool ripgrep rg; then
        log "ripgrep installed via cargo fallback"
        warn "If 'rg' is still not found in this shell, run: source ~/.bashrc"
        return 0
    fi

    warn "Could not install ripgrep via cargo fallback."
    warn "Manual fallback: https://github.com/BurntSushi/ripgrep/releases"
    return 1
}

install_github_cli() {
    if command -v gh >/dev/null 2>&1; then
        log "Already installed: gh"
        return 0
    fi

    if try_install_pkg gh; then
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

    if try_install_pkg fd-find || try_install_pkg fd; then
        return 0
    fi

    warn "fd package unavailable; trying cargo fallback."
    cargo_install_tool fd-find fd || warn "Could not install fd via package or cargo fallback."
}

install_watch_if_missing() {
    if command -v watch >/dev/null 2>&1; then
        log "Already installed: watch"
        return 0
    fi
    try_install_pkg procps-ng || try_install_pkg watch || warn "Could not install watch"
}

install_productivity_tools() {
    try_install_pkg git-delta || cargo_install_tool git-delta delta || warn "git-delta unavailable"
    try_install_pkg fzf || warn "fzf package unavailable"
    try_install_pkg zoxide || cargo_install_tool zoxide zoxide || warn "zoxide unavailable"
    try_install_pkg just || cargo_install_tool just just || warn "just unavailable"
    try_install_pkg tokei || cargo_install_tool tokei tokei || warn "tokei unavailable"
    try_install_pkg hyperfine || cargo_install_tool hyperfine hyperfine || warn "hyperfine unavailable"
    install_watch_if_missing
}

install_bats() {
    if command -v bats >/dev/null 2>&1; then
        log "Already installed: bats"
        return 0
    fi

    try_install_pkg bats || try_install_pkg bats-core || warn "Could not install bats (bats/bats-core unavailable)"
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

tool_exists() {
    local tool="$1"
    case "${tool}" in
        fd)
            command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1
            ;;
        *)
            command -v "${tool}" >/dev/null 2>&1
            ;;
    esac
}

collect_missing_tools() {
    local tool
    MISSING_REQUIRED=()
    MISSING_OPTIONAL=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        tool_exists "${tool}" || MISSING_REQUIRED+=("${tool}")
    done
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        tool_exists "${tool}" || MISSING_OPTIONAL+=("${tool}")
    done
}

verify_installation() {
    log ""
    log "Installed dev utility versions:"
    print_version_if_available "shellcheck" shellcheck --version
    print_version_if_available "shfmt" shfmt --version
    print_version_if_available "jq" jq --version
    print_version_if_available "yq" yq --version
    print_version_if_available "ripgrep" rg --version
    print_version_if_available "pre-commit" pre-commit --version
    print_version_if_available "yamllint" yamllint --version
    print_version_if_available "actionlint" actionlint -version
    print_version_if_available "bats" bats --version
    print_version_if_available "delta" delta --version
    print_version_if_available "fzf" fzf --version
    print_version_if_available "zoxide" zoxide --version
    print_version_if_available "just" just --version
    print_version_if_available "tokei" tokei --version
    print_version_if_available "hyperfine" hyperfine --version
    print_version_if_available "watch" watch --version

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

print_summary() {
    collect_missing_tools
    log ""
    log "Summary:"
    if [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
        log "  Required tools: ok"
    else
        warn "Required tools missing: ${MISSING_REQUIRED[*]}"
    fi

    if [[ ${#MISSING_OPTIONAL[@]} -eq 0 ]]; then
        log "  Optional tools: all installed"
    else
        warn "Optional tools missing: ${MISSING_OPTIONAL[*]}"
    fi
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

    try_install_pkg shellcheck || warn "shellcheck package not available"
    try_install_pkg shfmt || warn "shfmt package not available"
    try_install_pkg jq || warn "jq package not available"
    try_install_pkg yq || warn "yq package not available"
    install_ripgrep || warn "ripgrep could not be installed"
    try_install_pkg pre-commit || install_python_tool_with_pipx pre-commit pre-commit || warn "pre-commit unavailable"
    try_install_pkg yamllint || install_python_tool_with_pipx yamllint yamllint || warn "yamllint unavailable"
    install_fd
    install_productivity_tools
    install_bats
    install_actionlint || warn "actionlint could not be installed"
    install_github_cli

    verify_installation
    print_summary
    log ""
    if [[ "${DRY_RUN}" -eq 0 ]] && [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
        err "One or more required tools are missing."
        exit 1
    fi
    log "Done."
}

main "$@"
