#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

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
  --no-update                   Skip system package update
  -n, --dry-run                 Print actions without making changes
  -h, --help                    Show this help
EOF
}

SKIP_UPDATE=0

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

ensure_user_exists() {
    if ! id "${TARGET_USER}" >/dev/null 2>&1; then
        err "User does not exist: ${TARGET_USER}"
        exit 1
    fi
}

install_pkg() {
    local pkg="$1"
    install_pkg_dnf "${pkg}"
}

install_base_packages() {
    local pkg
    for pkg in git docker maven nodejs npm htop tree curl tar; do
        install_pkg "${pkg}"
    done
}

docker_compose_available() {
    command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

target_user_home() {
    local home_dir=""
    if command -v getent >/dev/null 2>&1; then
        home_dir="$(getent passwd "${TARGET_USER}" | awk -F: '{print $6}')"
    fi
    if [[ -z "${home_dir}" ]]; then
        home_dir="/home/${TARGET_USER}"
    fi
    printf '%s\n' "${home_dir}"
}

install_docker_compose_binary() {
    local arch=""
    local version="${DOCKER_COMPOSE_VERSION:-2.39.4}"
    local url=""

    case "$(uname -m)" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)
            warn "Unsupported architecture for docker compose binary fallback: $(uname -m)"
            return 1
            ;;
    esac

    require_cmd curl
    url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-linux-${arch}"
    run_root curl -fsSL -o /usr/local/bin/docker-compose "${url}"
    run_root chmod 0755 /usr/local/bin/docker-compose
    return 0
}

ensure_docker_compose_plugin_link() {
    local home_dir
    home_dir="$(target_user_home)"
    local plugin_dir="${home_dir}/.docker/cli-plugins"
    local plugin_bin="${plugin_dir}/docker-compose"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        run_root mkdir -p "${plugin_dir}"
        run_root ln -sfn /usr/local/bin/docker-compose "${plugin_bin}"
        return 0
    fi

    run_root mkdir -p "${plugin_dir}"
    run_root ln -sfn /usr/local/bin/docker-compose "${plugin_bin}"
    run_root chown -R "${TARGET_USER}":"${TARGET_USER}" "${home_dir}/.docker"
}

install_docker_compose() {
    if docker_compose_available; then
        log "Docker Compose already available"
        return 0
    fi

    if install_pkg_dnf docker-compose-plugin && docker_compose_available; then
        log "Docker Compose enabled via docker-compose-plugin package"
        return 0
    fi

    warn "docker-compose-plugin package unavailable or did not activate docker compose."

    if install_pkg_dnf docker-compose && docker_compose_available; then
        log "Docker Compose enabled via docker-compose package"
        return 0
    fi

    warn "docker-compose package unavailable. Trying binary fallback."
    install_docker_compose_binary || {
        warn "Docker Compose binary fallback failed."
        return 1
    }
    ensure_docker_compose_plugin_link
    if docker_compose_available; then
        log "Docker Compose enabled via binary fallback"
        return 0
    fi

    warn "Docker Compose install completed, but 'docker compose' is still not available."
    return 1
}

install_github_cli() {
    if command -v gh >/dev/null 2>&1; then
        log "Already installed: gh"
        return 0
    fi

    if install_pkg_dnf gh; then
        return 0
    fi

    warn "Package 'gh' not available in current repos. Adding official GitHub CLI repo."
    if ! is_pkg_installed_rpm dnf-plugins-core; then
        run_root dnf install -y dnf-plugins-core || run_root dnf install -y 'dnf-command(config-manager)'
    fi
    run_root dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    run_root dnf install -y gh
}

configure_docker() {
    run_root systemctl enable --now docker

    install_docker_compose || warn "Docker Compose is not available yet. Re-run later or install manually."

    if id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx docker; then
        log "User '${TARGET_USER}' already in docker group"
    else
        run_root usermod -aG docker "${TARGET_USER}"
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            warn "Would add '${TARGET_USER}' to docker group. Re-login is required for group changes to take effect."
        else
            warn "Added '${TARGET_USER}' to docker group. Re-login is required for group changes to take effect."
        fi
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
    validate_os_amzn
    ensure_user_exists
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting toolchain installation"
    log "Target user : ${TARGET_USER}"
    log "Java mode   : ${JAVA_MODE}"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run     : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi
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
