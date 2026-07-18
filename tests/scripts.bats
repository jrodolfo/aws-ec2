#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "repo bashrc keeps nvm-managed codex ahead of ~/.local/bin codex" {
  export TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_HOME}/.bashrc.d" "${TEST_HOME}/.local/bin" "${TEST_HOME}/.nvm/versions/node/v24.18.0/bin"
  cp "${REPO_ROOT}/dotfiles/.bashrc" "${TEST_HOME}/.bashrc"
  cp "${REPO_ROOT}/dotfiles/.bash_profile" "${TEST_HOME}/.bash_profile"

  cat > "${TEST_HOME}/.local/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo local-codex
EOF
  chmod +x "${TEST_HOME}/.local/bin/codex"

  cat > "${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo nvm-codex
EOF
  chmod +x "${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/codex"

  cat > "${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/node" <<'EOF'
#!/usr/bin/env bash
echo v24.18.0
EOF
  chmod +x "${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/node"

  cat > "${TEST_HOME}/.nvm/nvm.sh" <<'EOF'
export PATH="$HOME/.nvm/versions/node/v24.18.0/bin:$PATH"
nvm() {
  if [ "$1" = "use" ]; then
    export PATH="$HOME/.nvm/versions/node/v24.18.0/bin:$PATH"
  fi
  return 0
}
EOF

  run env HOME="${TEST_HOME}" bash -lc 'command -v codex; codex; command -v node; node'
  [ "$status" -eq 0 ]
  [[ "$output" == *"${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/codex"* ]]
  [[ "$output" == *"nvm-codex"* ]]
  [[ "$output" == *"${TEST_HOME}/.nvm/versions/node/v24.18.0/bin/node"* ]]
  [[ "$output" == *"v24.18.0"* ]]
}

@test "repo bashrc exports preferred editors" {
  export TEST_HOME="${BATS_TEST_TMPDIR}/editor-home"
  mkdir -p "${TEST_HOME}"
  cp "${REPO_ROOT}/dotfiles/.bashrc" "${TEST_HOME}/.bashrc"

  run env HOME="${TEST_HOME}" bash --noprofile --norc -lc '. "$HOME/.bashrc"; printf "%s|%s|%s\n" "$EDITOR" "$VISUAL" "$SYSTEMD_EDITOR"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"vi|vi|vi"* ]]
}

@test "bootstrap help works" {
  run "${REPO_ROOT}/bootstrap.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./bootstrap.sh [OPTIONS]"* ]]
}

@test "bootstrap dry-run works" {
  run "${REPO_ROOT}/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Setting up environment..."* ]]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "toolchain help works" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./install/install-toolchain.sh [OPTIONS]"* ]]
}

@test "toolchain invalid option fails" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --bad-option
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bad-option"* ]]
}

@test "toolchain dry-run works in non-amzn environments" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --dry-run --no-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run     : enabled"* ]]
  [[ "$output" == *"Node.js     : nvm 24"* ]]
  [[ "$output" == *"Maven       : 3.9.11"* ]]
  [[ "$output" == *"Would ensure /"*".bashrc.d/aws-ec2-toolchain.sh configures PATH, Python alias, and nvm"* ]]
  [[ "$output" == *"Ensuring Node.js 24 is installed via nvm"* ]]
  [[ "$output" == *"Ensuring codex CLI is installed under"* ]]
  [[ "$output" == *"Would ensure Java 21 remains the default java/javac toolchain"* ]]
  [[ "$output" == *"Would install Apache Maven 3.9.11"* ]]
  [[ "$output" == *"\$ java --version"* ]]
  [[ "$output" == *"\$ mvn --version"* ]]
}

@test "toolchain dry-run with adoptium25 keeps Java 21 as default" {
  run "${REPO_ROOT}/install/install-toolchain.sh" --dry-run --no-update --java-mode adoptium25
  [ "$status" -eq 0 ]
  [[ "$output" == *"Java mode   : adoptium25"* ]]
  [[ "$output" == *"Would install Adoptium JDK 25 side-by-side under /opt/java without changing the default java"* ]]
  [[ "$output" == *"Would ensure Java 21 remains the default java/javac toolchain"* ]]
}

@test "dev-utils help works" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./install/install-dev-utils.sh [OPTIONS]"* ]]
}

@test "dev-utils invalid option fails" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --bad-option
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bad-option"* ]]
}

@test "dev-utils dry-run works in non-amzn environments" {
  run "${REPO_ROOT}/install/install-dev-utils.sh" --dry-run --no-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run : enabled"* ]]
}

@test "extras dry-run includes trivy" {
  run "${REPO_ROOT}/install/install-extras.sh" --dry-run --no-update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already installed: trivy"* || "$output" == *"dnf install -y trivy"* ]]
}

@test "ollama help works" {
  run "${REPO_ROOT}/install/install-ollama.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./install/install-ollama.sh [OPTIONS]"* ]]
}

@test "ollama dry-run supports optional models and host binding" {
  run "${REPO_ROOT}/install/install-ollama.sh" --dry-run --host 0.0.0.0:11434 --model qwen2.5-coder:7b
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host binding : 0.0.0.0:11434"* ]]
  [[ "$output" == *"Would run: curl -fsSL https://ollama.com/install.sh | sh"* ]]
  [[ "$output" == *"[dry-run] ollama pull qwen2.5-coder:7b"* ]]
}
