#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
OLLAMA_VERSION="${OLLAMA_VERSION:-}"
OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
ENABLE_SERVICE=1
START_SERVICE=1
declare -a MODELS=()

usage() {
    cat <<'EOF'
Usage: ./install/install-ollama.sh [OPTIONS]

Install Ollama as an optional local model service for Amazon Linux 2023.
The default configuration binds Ollama to 0.0.0.0:11434 so Docker containers
on the same host can reach it.

Options:
  --version <version>     Install a specific Ollama version
  --host <host:port>      Bind address for the Ollama service (default: 0.0.0.0:11434)
  --model <name>          Pull a model after the service starts (repeatable)
  --no-enable             Do not enable the systemd service
  --no-start              Do not start or restart the service
  -n, --dry-run           Print actions without making changes
  -h, --help              Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                shift
                [[ $# -gt 0 ]] || { err "Missing value for --version"; exit 1; }
                OLLAMA_VERSION="$1"
                ;;
            --host)
                shift
                [[ $# -gt 0 ]] || { err "Missing value for --host"; exit 1; }
                OLLAMA_HOST="$1"
                ;;
            --model)
                shift
                [[ $# -gt 0 ]] || { err "Missing value for --model"; exit 1; }
                MODELS+=("$1")
                ;;
            --no-enable)
                ENABLE_SERVICE=0
                ;;
            --no-start)
                START_SERVICE=0
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

install_ollama() {
    local install_command="curl -fsSL https://ollama.com/install.sh | "
    if [[ -n "${OLLAMA_VERSION}" ]]; then
        install_command+="OLLAMA_VERSION=${OLLAMA_VERSION} sh"
    else
        install_command+="sh"
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would run: ${install_command}"
        return 0
    fi

    if command -v ollama >/dev/null 2>&1 && [[ -z "${OLLAMA_VERSION}" ]]; then
        log "Already installed: ollama"
        return 0
    fi

    run_root bash -lc "${install_command}"
}

configure_systemd_override() {
    local override_dir="/etc/systemd/system/ollama.service.d"
    local override_path="${override_dir}/override.conf"
    local tmp_file=""

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] Would configure ${override_path} with OLLAMA_HOST=${OLLAMA_HOST}"
        return 0
    fi

    tmp_file="$(mktemp /tmp/aws-ec2-ollama.XXXXXX)"
    cat > "${tmp_file}" <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST}"
EOF

    run_root mkdir -p "${override_dir}"
    if [[ ! -f "${override_path}" ]] || ! cmp -s "${tmp_file}" "${override_path}"; then
        run_root install -m 0644 "${tmp_file}" "${override_path}"
        log "Installed: ${override_path}"
    else
        log "Unchanged: ${override_path}"
    fi
    rm -f "${tmp_file}"

    run_root systemctl daemon-reload
}

manage_service() {
    if [[ "${ENABLE_SERVICE}" -eq 1 ]]; then
        run_root systemctl enable ollama
    fi

    if [[ "${START_SERVICE}" -eq 1 ]]; then
        run_root systemctl restart ollama
    else
        log "Skipping service start/restart by request"
    fi
}

pull_models() {
    local model

    if [[ "${#MODELS[@]}" -eq 0 ]]; then
        log "No Ollama models requested"
        return 0
    fi

    if [[ "${START_SERVICE}" -ne 1 ]]; then
        err "Cannot pull models when --no-start is set."
        return 1
    fi

    for model in "${MODELS[@]}"; do
        run ollama pull "${model}"
    done
}

verify_installation() {
    log ""
    log "Installed Ollama version:"
    if command -v ollama >/dev/null 2>&1; then
        ollama -v 2>/dev/null | head -n1
    else
        log "not found"
    fi

    log ""
    log "Configured service host: ${OLLAMA_HOST}"
}

main() {
    parse_args "$@"
    validate_os_amzn

    if [[ "${DRY_RUN}" -eq 0 ]]; then
        require_cmd curl
        require_cmd systemctl
    fi

    log "Starting Ollama installation"
    log "Host binding : ${OLLAMA_HOST}"
    [[ -n "${OLLAMA_VERSION}" ]] && log "Version      : ${OLLAMA_VERSION}"
    [[ "${DRY_RUN}" -eq 1 ]] && log "Dry run      : enabled"
    [[ "${ENABLE_SERVICE}" -eq 0 ]] && log "Enable step  : skipped"
    [[ "${START_SERVICE}" -eq 0 ]] && log "Start step   : skipped"

    install_ollama
    configure_systemd_override
    manage_service
    pull_models
    verify_installation

    log ""
    log "Done."
}

main "$@"
