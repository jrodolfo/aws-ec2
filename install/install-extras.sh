#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
SKIP_UPDATE=0
TARGET_USER="${SUDO_USER:-${USER:-ec2-user}}"
TARGET_USER_HOME=""
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-0.10.0}"
SHFMT_VERSION="${SHFMT_VERSION:-3.13.1}"
FZF_VERSION="${FZF_VERSION:-0.72.0}"
BATS_VERSION="${BATS_VERSION:-1.13.0}"
DELTA_VERSION="${DELTA_VERSION:-0.19.2}"

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

run_as_target_user() {
    run_as_user "${TARGET_USER}" "$@"
}

install_step() {
    printf 'Installing %s...\n' "$*"
}

add_path_now() {
    local path_dir="$1"
    if [[ ":${PATH}:" != *":${path_dir}:"* ]]; then
        export PATH="${path_dir}:${PATH}"
    fi
}

ensure_local_bin_path() {
    local local_bin="${TARGET_USER_HOME}/.local/bin"
    run_as_target_user mkdir -p "${local_bin}"
    add_path_now "${local_bin}"
}

ensure_cargo_path() {
    local cargo_bin="${TARGET_USER_HOME}/.cargo/bin"
    add_path_now "${cargo_bin}"
}

arch_linux_amd64_arm64() {
    case "$(uname -m)" in
        x86_64) printf '%s\n' "amd64" ;;
        aarch64) printf '%s\n' "arm64" ;;
        *)
            err "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
}

arch_linux_x86_64_aarch64() {
    case "$(uname -m)" in
        x86_64) printf '%s\n' "x86_64" ;;
        aarch64) printf '%s\n' "aarch64" ;;
        *)
            err "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
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

    run_root dnf install -y "${pkg}"
}

dnf_pkg_available() {
    local pkg="$1"
    dnf info "${pkg}" >/dev/null 2>&1
}

ensure_pipx() {
    ensure_local_bin_path

    if command -v pipx >/dev/null 2>&1; then
        log "Already installed: pipx"
        return 0
    fi

    if try_install_pkg pipx && command -v pipx >/dev/null 2>&1; then
        log "Installed: pipx"
        return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install pipx with python3.11 --user"
        return 0
    fi

    require_cmd python3.11
    install_step "pipx with python3.11 user install"
    run_as_target_user python3.11 -m pip install --user --upgrade pip >/dev/null
    run_as_target_user python3.11 -m pip install --user pipx >/dev/null
    ensure_local_bin_path
}

ensure_cargo() {
    ensure_cargo_path

    if command -v cargo >/dev/null 2>&1; then
        log "Already installed: cargo"
        return 0
    fi

    if dnf_pkg_available cargo; then
        try_install_pkg cargo
    elif dnf_pkg_available rust; then
        try_install_pkg rust
    else
        err "Neither cargo nor rust is available from configured repositories."
        return 1
    fi

    ensure_cargo_path
    command -v cargo >/dev/null 2>&1 || {
        err "cargo installation completed, but cargo is still not available."
        return 1
    }
}

download_to_file() {
    local label="$1"
    local url="$2"
    local destination="$3"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would download ${label} from ${url}"
        return 0
    fi

    install_step "${label} from ${url}"
    if ! curl -fsSL -o "${destination}" "${url}"; then
        err "Failed to download ${label} from ${url}"
        return 1
    fi
}

install_release_binary() {
    local label="$1"
    local bin_name="$2"
    local version="$3"
    local url="$4"
    local extracted_bin_relpath="$5"
    local install_path="/usr/local/bin/${bin_name}"
    local archive_ext="$6"
    local tmp_dir="/tmp/aws-ec2-${bin_name}"
    local archive_path="${tmp_dir}/archive.${archive_ext}"

    if command -v "${bin_name}" >/dev/null 2>&1; then
        log "Already installed: ${bin_name}"
        return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install ${label} ${version} from ${url}"
        return 0
    fi

    require_cmd tar
    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    download_to_file "${label} ${version}" "${url}" "${archive_path}"

    case "${archive_ext}" in
        tar.gz)
            install_step "extracting ${label} ${version}"
            run tar -xzf "${archive_path}" -C "${tmp_dir}"
            ;;
        tar.xz)
            if ! command -v xz >/dev/null 2>&1; then
                try_install_pkg xz
            fi
            install_step "extracting ${label} ${version}"
            run tar -xJf "${archive_path}" -C "${tmp_dir}"
            ;;
        *)
            err "Unsupported archive extension: ${archive_ext}"
            return 1
            ;;
    esac

    install_step "installing ${label} ${version} to ${install_path}"
    run_root install -m 0755 "${tmp_dir}/${extracted_bin_relpath}" "${install_path}"
}

install_single_binary() {
    local label="$1"
    local bin_name="$2"
    local version="$3"
    local url="$4"
    local install_path="/usr/local/bin/${bin_name}"
    local tmp_path="/tmp/aws-ec2-${bin_name}"

    if command -v "${bin_name}" >/dev/null 2>&1; then
        log "Already installed: ${bin_name}"
        return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install ${label} ${version} from ${url}"
        return 0
    fi

    download_to_file "${label} ${version}" "${url}" "${tmp_path}"
    install_step "installing ${label} ${version} to ${install_path}"
    run_root install -m 0755 "${tmp_path}" "${install_path}"
    run rm -f "${tmp_path}"
}

install_pipx_package() {
    local package_name="$1"
    local label="${2:-$1}"

    ensure_pipx

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install ${label} with pipx"
        run_as_target_user pipx install "${package_name}"
        return 0
    fi

    if run_as_target_user pipx list --short 2>/dev/null | grep -Fqx "${package_name}"; then
        log "Already installed with pipx: ${package_name}"
        return 0
    fi

    install_step "${label} with pipx"
    run_as_target_user pipx install "${package_name}" >/dev/null
}

install_cargo_package() {
    local crate_name="$1"
    local version="${2:-}"

    ensure_cargo

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        if [[ -n "${version}" ]]; then
            log "[dry-run] Would install ${crate_name} ${version} with cargo"
            run_as_target_user cargo install --locked "${crate_name}" --version "${version}"
        else
            log "[dry-run] Would install ${crate_name} with cargo"
            run_as_target_user cargo install --locked "${crate_name}"
        fi
        return 0
    fi

    if command -v "${crate_name}" >/dev/null 2>&1; then
        log "Already installed: ${crate_name}"
        return 0
    fi

    if [[ -n "${version}" ]]; then
        install_step "${crate_name} ${version} with cargo"
        run_as_target_user cargo install --locked "${crate_name}" --version "${version}" >/dev/null
    else
        install_step "${crate_name} with cargo"
        run_as_target_user cargo install --locked "${crate_name}" >/dev/null
    fi
}

install_shellcheck() {
    local arch
    local url

    if command -v shellcheck >/dev/null 2>&1; then
        log "Already installed: shellcheck"
        return 0
    fi

    if dnf_pkg_available shellcheck; then
        try_install_pkg shellcheck
        command -v shellcheck >/dev/null 2>&1 && return 0
    fi

    arch="$(arch_linux_x86_64_aarch64)"
    url="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${arch}.tar.xz"
    install_release_binary "shellcheck" shellcheck "${SHELLCHECK_VERSION}" "${url}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "tar.xz"
}

install_shfmt() {
    local arch
    local url

    if command -v shfmt >/dev/null 2>&1; then
        log "Already installed: shfmt"
        return 0
    fi

    if dnf_pkg_available shfmt; then
        try_install_pkg shfmt
        command -v shfmt >/dev/null 2>&1 && return 0
    fi

    arch="$(arch_linux_amd64_arm64)"
    url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${arch}"
    install_single_binary "shfmt" shfmt "${SHFMT_VERSION}" "${url}"
}

install_pre_commit() {
    if command -v pre-commit >/dev/null 2>&1; then
        log "Already installed: pre-commit"
        return 0
    fi

    if dnf_pkg_available pre-commit; then
        try_install_pkg pre-commit
        command -v pre-commit >/dev/null 2>&1 && return 0
    fi

    install_pipx_package pre-commit
}

install_yamllint() {
    if command -v yamllint >/dev/null 2>&1; then
        log "Already installed: yamllint"
        return 0
    fi

    if dnf_pkg_available yamllint; then
        try_install_pkg yamllint
        command -v yamllint >/dev/null 2>&1 && return 0
    fi

    install_pipx_package yamllint
}

install_bats() {
    local url="https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz"
    local tmp_dir="/tmp/aws-ec2-bats"
    local archive_path="${tmp_dir}/bats.tar.gz"

    if command -v bats >/dev/null 2>&1; then
        log "Already installed: bats"
        return 0
    fi

    if dnf_pkg_available bats; then
        try_install_pkg bats
        command -v bats >/dev/null 2>&1 && return 0
    fi
    if dnf_pkg_available bats-core; then
        try_install_pkg bats-core
        command -v bats >/dev/null 2>&1 && return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install bats-core ${BATS_VERSION} from source tarball"
        return 0
    fi

    require_cmd tar
    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    download_to_file "bats-core ${BATS_VERSION}" "${url}" "${archive_path}"
    install_step "extracting bats-core ${BATS_VERSION}"
    run tar -xzf "${archive_path}" -C "${tmp_dir}"
    install_step "installing bats-core ${BATS_VERSION} to /usr/local"
    run_root "${tmp_dir}/bats-core-${BATS_VERSION}/install.sh" /usr/local >/dev/null
}

install_git_delta() {
    local arch
    local url

    if command -v delta >/dev/null 2>&1; then
        log "Already installed: delta"
        return 0
    fi

    if dnf_pkg_available git-delta; then
        try_install_pkg git-delta
        command -v delta >/dev/null 2>&1 && return 0
    fi

    arch="$(arch_linux_x86_64_aarch64)"
    case "${arch}" in
        x86_64) arch="x86_64-unknown-linux-gnu" ;;
        aarch64) arch="aarch64-unknown-linux-gnu" ;;
    esac
    url="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${arch}.tar.gz"
    install_release_binary "delta" delta "${DELTA_VERSION}" "${url}" "delta-${DELTA_VERSION}-${arch}/delta" "tar.gz"
}

install_fzf() {
    local arch
    local url

    if command -v fzf >/dev/null 2>&1; then
        log "Already installed: fzf"
        return 0
    fi

    if dnf_pkg_available fzf; then
        try_install_pkg fzf
        command -v fzf >/dev/null 2>&1 && return 0
    fi

    arch="$(arch_linux_amd64_arm64)"
    url="https://github.com/junegunn/fzf/releases/download/${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${arch}.tar.gz"
    install_release_binary "fzf" fzf "${FZF_VERSION}" "${url}" "fzf" "tar.gz"
}

install_zoxide() {
    if command -v zoxide >/dev/null 2>&1; then
        log "Already installed: zoxide"
        return 0
    fi

    if dnf_pkg_available zoxide; then
        try_install_pkg zoxide
        command -v zoxide >/dev/null 2>&1 && return 0
    fi

    install_cargo_package zoxide 0.9.9
}

install_just() {
    if command -v just >/dev/null 2>&1; then
        log "Already installed: just"
        return 0
    fi

    if dnf_pkg_available just; then
        try_install_pkg just
        command -v just >/dev/null 2>&1 && return 0
    fi

    install_cargo_package just 1.50.0
}

install_tokei() {
    if command -v tokei >/dev/null 2>&1; then
        log "Already installed: tokei"
        return 0
    fi

    if dnf_pkg_available tokei; then
        try_install_pkg tokei
        command -v tokei >/dev/null 2>&1 && return 0
    fi

    install_cargo_package tokei 14.0.0
}

install_hyperfine() {
    if command -v hyperfine >/dev/null 2>&1; then
        log "Already installed: hyperfine"
        return 0
    fi

    if dnf_pkg_available hyperfine; then
        try_install_pkg hyperfine
        command -v hyperfine >/dev/null 2>&1 && return 0
    fi

    install_cargo_package hyperfine 1.20.0
}

install_actionlint() {
    if command -v actionlint >/dev/null 2>&1; then
        log "Already installed: actionlint"
        return 0
    fi

    if dnf_pkg_available actionlint; then
        try_install_pkg actionlint
        command -v actionlint >/dev/null 2>&1 && return 0
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
            err "Unsupported architecture for actionlint fallback: $(uname -m)"
            exit 1
            ;;
    esac

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install actionlint ${version} from GitHub release"
        return 0
    fi

    require_cmd tar
    url="https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_linux_${arch}.tar.gz"
    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    download_to_file "actionlint ${version}" "${url}" "${tarball}"
    install_step "extracting actionlint ${version}"
    run tar -xzf "${tarball}" -C "${tmp_dir}"
    install_step "installing actionlint ${version} to /usr/local/bin/actionlint"
    run_root install -m 0755 "${tmp_dir}/actionlint" /usr/local/bin/actionlint
}

install_trivy() {
    local repo_path="/etc/yum.repos.d/trivy.repo"
    local tmp_repo=""

    if command -v trivy >/dev/null 2>&1; then
        log "Already installed: trivy"
        return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install Trivy repository configuration at ${repo_path}"
        run_root dnf install -y trivy
        return 0
    fi

    tmp_repo="$(mktemp /tmp/aws-ec2-trivy.XXXXXX)"
    cat > "${tmp_repo}" <<'EOF'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
EOF

    if [[ ! -f "${repo_path}" ]] || ! cmp -s "${tmp_repo}" "${repo_path}"; then
        install_step "Trivy repository configuration"
        run_root install -m 0644 "${tmp_repo}" "${repo_path}"
        log "Installed: ${repo_path}"
    else
        log "Unchanged: ${repo_path}"
    fi
    rm -f "${tmp_repo}"

    install_step "trivy from configured repository"
    run_root dnf install -y trivy >/dev/null || {
        err "trivy package not available after enabling the Trivy repository."
        return 1
    }
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
    TARGET_USER_HOME="$(resolve_user_home "${TARGET_USER}")"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting optional extras installation"
    log "Target user : ${TARGET_USER}"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run     : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi

    install_shellcheck
    install_shfmt
    install_pre_commit
    install_yamllint
    install_bats
    install_git_delta
    install_fzf
    install_zoxide
    install_just
    install_tokei
    install_hyperfine
    install_actionlint
    install_trivy

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
    print_version_if_available "trivy" trivy --version
    log ""
    log "Done."
}

main "$@"
