#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

TARGET_USER="${SUDO_USER:-${USER:-ec2-user}}"
TARGET_USER_HOME=""
TARGET_USER_GROUP=""
JAVA_MODE="distro"
DRY_RUN=0
SKIP_UPDATE=0
DOCKER_COMPOSE_INSTALL_METHOD="unknown"
NVM_VERSION="${NVM_VERSION:-0.40.5}"
NODEJS_VERSION="${NODEJS_VERSION:-24}"
MAVEN_VERSION="${MAVEN_VERSION:-3.9.11}"
JAVA21_HOME=""
JAVA25_HOME=""

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
    TARGET_USER_GROUP="$(id -gn "${TARGET_USER}")"
}

run_as_target_user() {
    run_as_user "${TARGET_USER}" "$@"
}

run_as_target_user_shell() {
    local shell_command="$1"
    run_as_user_shell "${TARGET_USER}" "${shell_command}"
}

capture_as_target_user_shell() {
    local shell_command="$1"
    if [[ "${EUID}" -eq 0 ]]; then
        sudo -u "${TARGET_USER}" -H bash -lc "${shell_command}"
    else
        bash -lc "${shell_command}"
    fi
}

run_in_target_user_nvm_shell() {
    local command="$1"
    local shell_command="
export NVM_DIR='${TARGET_USER_HOME}/.nvm'
if [ -s \"\$NVM_DIR/nvm.sh\" ]; then
  . \"\$NVM_DIR/nvm.sh\"
fi
nvm use --silent default >/dev/null 2>&1 || true
${command}
"
    run_as_target_user_shell "${shell_command}"
}

capture_in_target_user_nvm_shell() {
    local command="$1"
    local shell_command="
export NVM_DIR='${TARGET_USER_HOME}/.nvm'
if [ -s \"\$NVM_DIR/nvm.sh\" ]; then
  . \"\$NVM_DIR/nvm.sh\"
fi
nvm use --silent default >/dev/null 2>&1 || true
${command}
"
    capture_as_target_user_shell "${shell_command}"
}

ensure_toolchain_shell_snippet() {
    local bashrc_d="${TARGET_USER_HOME}/.bashrc.d"
    local snippet_path="${bashrc_d}/aws-ec2-toolchain.sh"
    local bashrc_path="${TARGET_USER_HOME}/.bashrc"
    # shellcheck disable=SC2016
    local bootstrap_line='[ -f "$HOME/.bashrc.d/aws-ec2-toolchain.sh" ] && . "$HOME/.bashrc.d/aws-ec2-toolchain.sh"'
    local tmp_file=""

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would ensure ${snippet_path} configures PATH, Python alias, and nvm"
        log "[dry-run] Would ensure ${bashrc_path} sources ${snippet_path} before bootstrap"
        return 0
    fi

    tmp_file="$(mktemp /tmp/aws-ec2-toolchain.XXXXXX)"
    cat > "${tmp_file}" <<'EOF'
# Managed by aws-ec2 install-toolchain.sh
export PATH="$HOME/.local/bin:$PATH"
alias python=python3.11

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use --silent default >/dev/null 2>&1 || true
fi
if [ -s "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
fi
EOF

    run_as_target_user mkdir -p "${bashrc_d}"

    if [[ -f "${snippet_path}" ]] && cmp -s "${tmp_file}" "${snippet_path}"; then
        log "Unchanged: ${snippet_path}"
    else
        if [[ "${EUID}" -eq 0 ]]; then
            run_root install -o "${TARGET_USER}" -g "${TARGET_USER_GROUP}" -m 0644 "${tmp_file}" "${snippet_path}"
        else
            run install -m 0644 "${tmp_file}" "${snippet_path}"
        fi
        log "Installed: ${snippet_path}"
    fi

    rm -f "${tmp_file}"

    if [[ ! -f "${bashrc_path}" ]]; then
        run_as_target_user touch "${bashrc_path}"
    fi
    if capture_as_target_user_shell "grep -Fq '${bootstrap_line}' '${bashrc_path}'"; then
        log "Already present in ${bashrc_path}: ${bootstrap_line}"
    else
        run_as_target_user_shell "printf '\n%s\n' '${bootstrap_line}' >> '${bashrc_path}'"
        log "Added to ${bashrc_path}: ${bootstrap_line}"
    fi
}

install_pkg() {
    local pkg="$1"
    install_pkg_dnf "${pkg}"
}

install_base_packages() {
    local pkg
    for pkg in git docker tar bubblewrap; do
        install_pkg "${pkg}"
    done

    # Amazon Linux commonly ships curl-minimal by default. Installing curl can
    # conflict with curl-minimal, so only install a curl provider if missing.
    if ! command -v curl >/dev/null 2>&1; then
        install_pkg_dnf curl-minimal || install_pkg_dnf curl || warn "Could not install curl provider"
    fi
}

docker_compose_available() {
    command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

docker_compose_legacy_available() {
    command -v docker-compose >/dev/null 2>&1
}

install_docker_compose_binary() {
    local arch=""
    local version="${DOCKER_COMPOSE_VERSION:-2.39.4}"
    local plugin_dir="/usr/libexec/docker/cli-plugins"
    local plugin_bin="${plugin_dir}/docker-compose"
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
    require_cmd install
    url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-linux-${arch}"
    run_root mkdir -p "${plugin_dir}"
    run_root curl -fsSL -o "${plugin_bin}" "${url}"
    run_root chmod 0755 "${plugin_bin}"

    # Compatibility symlink for workflows that still call docker-compose directly.
    run_root ln -sfn "${plugin_bin}" /usr/local/bin/docker-compose
    return 0
}

install_docker_compose() {
    if docker_compose_available; then
        log "Docker Compose already available"
        DOCKER_COMPOSE_INSTALL_METHOD="already-present"
        return 0
    fi

    log "Trying Docker Compose via docker-compose-plugin package..."
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        install_pkg_dnf docker-compose-plugin || true
    elif run_root dnf install -y docker-compose-plugin >/dev/null 2>&1; then
        log "Installed: docker-compose-plugin"
    fi
    if docker_compose_available; then
        log "Docker Compose enabled via docker-compose-plugin package"
        DOCKER_COMPOSE_INSTALL_METHOD="docker-compose-plugin"
        return 0
    fi

    warn "docker-compose-plugin package unavailable or did not activate docker compose."

    log "Trying Docker Compose via docker-compose package..."
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        install_pkg_dnf docker-compose || true
    elif run_root dnf install -y docker-compose >/dev/null 2>&1; then
        log "Installed: docker-compose"
    fi
    if docker_compose_available; then
        log "Docker Compose enabled via docker-compose package"
        DOCKER_COMPOSE_INSTALL_METHOD="docker-compose"
        return 0
    fi

    warn "docker-compose package unavailable. Trying binary fallback."
    install_docker_compose_binary || {
        warn "Docker Compose binary fallback failed."
        return 1
    }
    if docker_compose_available || docker_compose_legacy_available; then
        log "Docker Compose enabled via binary fallback"
        DOCKER_COMPOSE_INSTALL_METHOD="binary-fallback"
        return 0
    fi

    warn "Docker Compose install completed, but compose commands are still unavailable."
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

install_nvm() {
    if [[ -s "${TARGET_USER_HOME}/.nvm/nvm.sh" ]]; then
        log "Already installed: nvm"
        return 0
    fi

    run_as_target_user mkdir -p "${TARGET_USER_HOME}/.nvm"
    run_as_target_user_shell "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"
}

install_nodejs() {
    install_nvm
    ensure_toolchain_shell_snippet

    log "Ensuring Node.js ${NODEJS_VERSION} is installed via nvm for ${TARGET_USER}"
    run_in_target_user_nvm_shell "
nvm install ${NODEJS_VERSION}
nvm alias default ${NODEJS_VERSION}
nvm use --silent default >/dev/null
"
}

install_codex_cli() {
    log "Ensuring codex CLI is installed under ${TARGET_USER}'s nvm environment"
    run_in_target_user_nvm_shell "
if npm list -g @openai/codex >/dev/null 2>&1; then
  echo 'Already installed: codex'
else
  npm install -g @openai/codex
fi
"
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

resolve_java21_home() {
    local candidate=""
    if rpm_available && rpm -q java-21-amazon-corretto-devel >/dev/null 2>&1; then
        candidate="$(
            rpm -ql java-21-amazon-corretto-devel 2>/dev/null \
                | awk '/\/bin\/java$/ {sub(/\/bin\/java$/, ""); print; exit}'
        )"
    fi
    if [[ -z "${candidate}" ]] && [[ -d /usr/lib/jvm ]]; then
        candidate="$(find /usr/lib/jvm -maxdepth 1 -type d -name 'java-21-amazon-corretto*' | sort | head -n1)"
    fi
    [[ -n "${candidate}" ]] || return 1
    printf '%s\n' "${candidate}"
}

clear_java25_override_link() {
    local link_path="$1"
    local expected_suffix="$2"
    local link_target=""

    [[ -L "${link_path}" ]] || return 0
    link_target="$(readlink -f "${link_path}" 2>/dev/null || true)"
    case "${link_target}" in
        /opt/java/jdk-25*/bin/"${expected_suffix}")
            run_root rm -f "${link_path}"
            log "Removed legacy Java 25 override: ${link_path}"
            ;;
    esac
}

set_java21_default() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would ensure Java 21 remains the default java/javac toolchain"
        JAVA21_HOME="/usr/lib/jvm/java-21-amazon-corretto"
        return 0
    fi

    JAVA21_HOME="$(resolve_java21_home)" || {
        err "Could not determine Java 21 installation path."
        return 1
    }

    clear_java25_override_link /usr/local/bin/java java
    clear_java25_override_link /usr/local/bin/javac javac

    if command -v alternatives >/dev/null 2>&1; then
        if alternatives --display java 2>/dev/null | grep -Fq "${JAVA21_HOME}/bin/java"; then
            run_root alternatives --set java "${JAVA21_HOME}/bin/java"
        fi
        if alternatives --display javac 2>/dev/null | grep -Fq "${JAVA21_HOME}/bin/javac"; then
            run_root alternatives --set javac "${JAVA21_HOME}/bin/javac"
        fi
    fi

    log "Java 21 default home: ${JAVA21_HOME}"
}

install_java21() {
    install_pkg java-21-amazon-corretto-devel
    set_java21_default
}

resolve_java25_home() {
    local candidate=""
    if [[ -d /opt/java ]]; then
        candidate="$(find /opt/java -maxdepth 1 -type d -name 'jdk-25*' | sort | tail -n1)"
    fi
    [[ -n "${candidate}" ]] || return 1
    printf '%s\n' "${candidate}"
}

install_java_adoptium25() {
    require_cmd uname
    local arch=""
    local tmp_dir="/tmp/aws-ec2-jdk25"
    local tarball="${tmp_dir}/jdk25.tar.gz"
    local url="https://api.adoptium.net/v3/binary/latest/25/ga/linux"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install Adoptium JDK 25 side-by-side under /opt/java without changing the default java"
        JAVA25_HOME="/opt/java/jdk-25"
        return 0
    fi

    if JAVA25_HOME="$(resolve_java25_home 2>/dev/null)"; then
        log "Java 25 already installed side-by-side at ${JAVA25_HOME}"
        return 0
    fi

    case "$(uname -m)" in
        x86_64) arch="x64" ;;
        aarch64) arch="aarch64" ;;
        *)
            err "Unsupported architecture for Adoptium JDK 25: $(uname -m)"
            exit 1
            ;;
    esac

    url="${url}/${arch}/jdk/hotspot/normal/eclipse"

    run rm -rf "${tmp_dir}"
    run mkdir -p "${tmp_dir}"
    run curl -fsSL -o "${tarball}" "${url}"
    run_root mkdir -p /opt/java
    run_root tar -xzf "${tarball}" -C /opt/java

    JAVA25_HOME="$(resolve_java25_home)" || {
        err "Could not find extracted JDK under /opt/java/jdk-25*"
        exit 1
    }

    log "Installed Java 25 side-by-side at ${JAVA25_HOME}"
}

install_java() {
    install_java21
    case "${JAVA_MODE}" in
        distro)
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

install_maven() {
    local base_dir="/opt/apache-maven-${MAVEN_VERSION}"
    local current_link="/opt/apache-maven"
    local tarball="/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    local url="https://downloads.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    local wrapper="/usr/local/bin/mvn"
    local debug_wrapper="/usr/local/bin/mvnDebug"
    local tmp_wrapper=""

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would install Apache Maven ${MAVEN_VERSION} under ${base_dir}"
        log "[dry-run] Would install mvn wrapper pinned to Java 21"
        return 0
    fi

    if [[ ! -d "${base_dir}" ]]; then
        run curl -fsSL -o "${tarball}" "${url}" || run curl -fsSL -o "${tarball}" \
            "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
        run_root tar -xzf "${tarball}" -C /opt
    else
        log "Already installed: Apache Maven ${MAVEN_VERSION}"
    fi

    run_root ln -sfn "${base_dir}" "${current_link}"

    tmp_wrapper="$(mktemp /tmp/aws-ec2-mvn.XXXXXX)"
    cat > "${tmp_wrapper}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export JAVA_HOME="${JAVA21_HOME}"
exec /opt/apache-maven/bin/mvn "\$@"
EOF
    run_root install -m 0755 "${tmp_wrapper}" "${wrapper}"
    rm -f "${tmp_wrapper}"

    tmp_wrapper="$(mktemp /tmp/aws-ec2-mvndebug.XXXXXX)"
    cat > "${tmp_wrapper}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export JAVA_HOME="${JAVA21_HOME}"
exec /opt/apache-maven/bin/mvnDebug "\$@"
EOF
    run_root install -m 0755 "${tmp_wrapper}" "${debug_wrapper}"
    rm -f "${tmp_wrapper}"
}

install_python_ytdlp() {
    install_pkg python3.11
    install_pkg python3.11-pip

    run_as_target_user mkdir -p "${TARGET_USER_HOME}/.local/bin"
    run_as_target_user python3.11 -m pip install --user --upgrade pip setuptools wheel
    run_as_target_user python3.11 -m pip install --user --upgrade --force-reinstall yt-dlp

    ensure_toolchain_shell_snippet
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

print_target_user_version_if_available() {
    local label="$1"
    local command="$2"
    local output=""

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf '%-16s %s\n' "${label}:" "[dry-run]"
        return 0
    fi

    output="$(capture_in_target_user_nvm_shell "${command}" 2>/dev/null | head -n1 || true)"
    if [[ -n "${output}" ]]; then
        printf '%-16s %s\n' "${label}:" "${output}"
    else
        printf '%-16s %s\n' "${label}:" "not found"
    fi
}

print_verification_command() {
    local label="$1"
    local command="$2"
    local runner="$3"

    log ""
    log "\$ ${label}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] ${label}"
        return 0
    fi

    if [[ "${runner}" == "target-user-nvm" ]]; then
        capture_in_target_user_nvm_shell "${command}" 2>&1 || true
    else
        bash -lc "${command}" 2>&1 || true
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
            printf '%-16s %s\n' "Compose method:" "${DOCKER_COMPOSE_INSTALL_METHOD}"
        else
            local legacy_compose_version
            legacy_compose_version="$(docker-compose version 2>/dev/null | head -n1 || true)"
            if [[ -n "${legacy_compose_version}" ]]; then
                printf '%-16s %s\n' "Docker Compose:" "${legacy_compose_version} (legacy docker-compose)"
                printf '%-16s %s\n' "Compose method:" "${DOCKER_COMPOSE_INSTALL_METHOD}"
            else
                printf '%-16s %s\n' "Docker Compose:" "not available"
            fi
        fi
    fi

    print_version_if_available "Git" git --version
    print_version_if_available "GitHub CLI" gh --version
    print_version_if_available "Bubblewrap" bwrap --version
    print_version_if_available "Java" java --version
    print_version_if_available "Javac" javac --version
    print_version_if_available "Maven" mvn --version
    print_target_user_version_if_available "Node" "node -v"
    print_target_user_version_if_available "NPM" "npm -v"
    print_target_user_version_if_available "Codex CLI" "codex --version"
    print_version_if_available "Python 3.11" python3.11 --version

    local ytdlp_bin="${TARGET_USER_HOME}/.local/bin/yt-dlp"
    if [[ -x "${ytdlp_bin}" ]]; then
        printf '%-16s %s\n' "yt-dlp:" "$("${ytdlp_bin}" --version 2>/dev/null | head -n1)"
    else
        printf '%-16s %s\n' "yt-dlp:" "not found"
    fi

    log ""
    log "Verification:"
    print_verification_command "java --version" "java --version" "host"
    print_verification_command "mvn --version" "mvn --version" "host"
}

main() {
    parse_args "$@"
    validate_os_amzn
    ensure_user_exists
    TARGET_USER_HOME="$(resolve_user_home "${TARGET_USER}")"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd dnf
        require_cmd rpm
    fi

    log "Starting toolchain installation"
    log "Target user : ${TARGET_USER}"
    log "Java mode   : ${JAVA_MODE}"
    log "Node.js     : nvm ${NODEJS_VERSION}"
    log "Maven       : ${MAVEN_VERSION}"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run     : enabled"
    [[ "${SKIP_UPDATE}" -eq 1 ]] && log "Update step : skipped"

    if [[ "${SKIP_UPDATE}" -eq 0 ]]; then
        run_root dnf update -y
    fi

    install_base_packages
    install_github_cli
    install_nodejs
    install_codex_cli
    configure_docker
    install_java
    install_maven
    install_python_ytdlp
    verify_installation

    log ""
    log "Done."
    log "Verify with: docker info && docker compose version"
    log "If docker commands fail without sudo, log out and back in for group changes to apply."
}

main "$@"
