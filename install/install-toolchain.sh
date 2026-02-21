#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-${USER:-ec2-user}}"
JAVA_MODE="distro"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: ./install/install-toolchain.sh [OPTIONS]

Install common dev/runtime toolchain packages on an EC2 Linux host.

Options:
  -u, --user <name>             User to add to docker group (default: current login user)
  -j, --java-mode <mode>        Java install mode: distro|adoptium25 (default: distro)
  -n, --dry-run                 Print actions without making changes
  -h, --help                    Show this help
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

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Missing required command: ${cmd}"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--user)
                shift
                [[ $# -gt 0 ]] || { err "Missing value for --user"; exit 1; }
                TARGET_USER="$1"
                ;;
            -j|--java-mode)
                shift
                [[ $# -gt 0 ]] || { err "Missing value for --java-mode"; exit 1; }
                JAVA_MODE="$1"
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

validate_os() {
    if [[ ! -f /etc/os-release ]]; then
        err "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "amzn" ]]; then
        warn "This script is tuned for Amazon Linux (detected ID=${ID:-unknown})."
        warn "Proceeding, but package names or behavior may differ."
    fi
}

ensure_user_exists() {
    if ! id "${TARGET_USER}" >/dev/null 2>&1; then
        err "User does not exist: ${TARGET_USER}"
        exit 1
    fi
}

is_pkg_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

install_pkg() {
    local pkg="$1"
    if is_pkg_installed "${pkg}"; then
        log "Already installed: ${pkg}"
    else
        run_root dnf install -y "${pkg}"
    fi
}

install_base_packages() {
    local pkg
    for pkg in git docker docker-compose-plugin maven nodejs npm htop tree curl tar; do
        install_pkg "${pkg}"
    done
}

install_github_cli() {
    if command -v gh >/dev/null 2>&1; then
        log "Already installed: gh"
        return 0
    fi

    if run_root dnf install -y gh; then
        return 0
    fi

    warn "Package 'gh' not available in current repos. Adding official GitHub CLI repo."
    if ! is_pkg_installed dnf-plugins-core; then
        run_root dnf install -y dnf-plugins-core || run_root dnf install -y 'dnf-command(config-manager)'
    fi
    run_root dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    run_root dnf install -y gh
}

configure_docker() {
    run_root systemctl enable --now docker

    if id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx docker; then
        log "User '${TARGET_USER}' already in docker group"
    else
        run_root usermod -aG docker "${TARGET_USER}"
        warn "Added '${TARGET_USER}' to docker group. Re-login is required for group changes to take effect."
    fi
}

install_java_distro() {
    if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
        log "Java already available in PATH"
        return 0
    fi

    if run_root dnf install -y java-21-amazon-corretto-devel; then
        return 0
    fi

    warn "Could not install Java 21 Corretto package. Trying Java 17 Corretto."
    run_root dnf install -y java-17-amazon-corretto-devel
}

install_java_adoptium25() {
    require_cmd uname
    local arch=""
    case "$(uname -m)" in
        x86_64) arch="x64" ;;
        aarch64) arch="aarch64" ;;
        *)
            err "Unsupported architecture for Adoptium JDK 25: $(uname -m)"
            exit 1
            ;;
    esac

    local tmp_dir="/tmp/aws-ec2-jdk25"
    local tarball="${tmp_dir}/jdk25.tar.gz"
    local url="https://api.adoptium.net/v3/binary/latest/25/ga/linux/${arch}/jdk/hotspot/normal/eclipse"

    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    run curl -fsSL -o "${tarball}" "${url}"
    run_root mkdir -p /opt/java
    run_root tar -xzf "${tarball}" -C /opt/java

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Detect latest extracted /opt/java/jdk-25* and link java/javac"
        return 0
    fi

    local jdk_dir
    jdk_dir="$(
        find /opt/java -maxdepth 1 -type d -name 'jdk-25*' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr \
            | head -n1 \
            | cut -d' ' -f2-
    )"
    if [[ -z "${jdk_dir}" ]]; then
        err "Could not find extracted JDK under /opt/java/jdk-25*"
        exit 1
    fi

    run_root ln -sfn "${jdk_dir}/bin/java" /usr/local/bin/java
    run_root ln -sfn "${jdk_dir}/bin/javac" /usr/local/bin/javac
}

install_java() {
    case "${JAVA_MODE}" in
        distro)
            install_java_distro
            ;;
        adoptium25)
            install_java_adoptium25
            ;;
        *)
            err "Invalid --java-mode: ${JAVA_MODE}. Use 'distro' or 'adoptium25'."
            exit 1
            ;;
    esac
}

print_version_if_available() {
    local label="$1"
    shift
    if command -v "$1" >/dev/null 2>&1; then
        printf '%-16s %s\n' "${label}:" "$("$@" 2>/dev/null | head -n1)"
    else
        printf '%-16s %s\n' "${label}:" "not found"
    fi
}

verify_installation() {
    log ""
    log "Installed toolchain versions:"
    print_version_if_available "Docker" docker --version

    if command -v docker >/dev/null 2>&1; then
        local compose_version
        compose_version="$(docker compose version 2>/dev/null || true)"
        if [[ -n "${compose_version}" ]]; then
            printf '%-16s %s\n' "Docker Compose:" "${compose_version}"
        else
            printf '%-16s %s\n' "Docker Compose:" "not available"
        fi
    fi

    print_version_if_available "Git" git --version
    print_version_if_available "GitHub CLI" gh --version
    print_version_if_available "Java" java -version
    print_version_if_available "Javac" javac -version
    print_version_if_available "Maven" mvn -version
    print_version_if_available "Node" node -v
    print_version_if_available "NPM" npm -v
}

main() {
    parse_args "$@"
    validate_os
    ensure_user_exists
    require_cmd dnf
    require_cmd rpm

    log "Starting toolchain installation"
    log "Target user : ${TARGET_USER}"
    log "Java mode   : ${JAVA_MODE}"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run     : enabled"

    run_root dnf update -y
    install_base_packages
    install_github_cli
    configure_docker
    install_java
    verify_installation

    log ""
    log "Done."
    log "If docker commands fail without sudo, log out and back in for group changes to apply."
}

main "$@"
