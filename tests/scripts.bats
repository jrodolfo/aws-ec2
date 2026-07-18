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

  cat > "${TEST_HOME}/.bashrc.d/aws-ec2-toolchain.sh" <<'EOF'
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

  run env -i HOME="${TEST_HOME}" PATH="/usr/bin:/bin" TERM="${TERM:-xterm}" bash -lc 'command -v codex; codex; command -v node; node'
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

@test "linuxinfo prints root disk total used and available" {
  run "${REPO_ROOT}/ops/linuxinfo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Root Disk     : "* ]]
  [[ "$output" == *" used, "* ]]
  [[ "$output" == *" available)"* ]]
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
  [[ "$output" == *"Would install shellcheck 0.10.0 from https://github.com/koalaman/shellcheck/releases/download/v0.10.0/"* || "$output" == *"Already installed: shellcheck"* ]]
  [[ "$output" == *"Would install shfmt 3.13.1 from https://github.com/mvdan/sh/releases/download/v3.13.1/"* || "$output" == *"Already installed: shfmt"* ]]
  [[ "$output" == *"Would install pre-commit with pipx"* || "$output" == *"pipx install pre-commit"* || "$output" == *"Already installed: pre-commit"* ]]
  [[ "$output" == *"Would install yamllint with pipx"* || "$output" == *"pipx install yamllint"* || "$output" == *"Already installed: yamllint"* ]]
  [[ "$output" == *"Would install bats-core 1.13.0 from source tarball"* || "$output" == *"Already installed: bats"* ]]
  [[ "$output" == *"Would install delta 0.19.2 from https://github.com/dandavison/delta/releases/download/0.19.2/delta-0.19.2-x86_64-unknown-linux-gnu.tar.gz"* || "$output" == *"Would install delta 0.19.2 from https://github.com/dandavison/delta/releases/download/0.19.2/delta-0.19.2-aarch64-unknown-linux-gnu.tar.gz"* || "$output" == *"Already installed: delta"* ]]
  [[ "$output" == *"Would install fzf 0.72.0 from https://github.com/junegunn/fzf/releases/download/v0.72.0/"* || "$output" == *"Already installed: fzf"* ]]
  [[ "$output" == *"Would install zoxide 0.9.9 with cargo"* || "$output" == *"cargo install --locked zoxide --version 0.9.9"* || "$output" == *"Already installed: zoxide"* ]]
  [[ "$output" == *"Would install just 1.50.0 with cargo"* || "$output" == *"cargo install --locked just --version 1.50.0"* || "$output" == *"Already installed: just"* ]]
  [[ "$output" == *"Would install tokei 14.0.0 with cargo"* || "$output" == *"cargo install --locked tokei --version 14.0.0"* || "$output" == *"Already installed: tokei"* ]]
  [[ "$output" == *"Would install hyperfine 1.20.0 with cargo"* || "$output" == *"cargo install --locked hyperfine --version 1.20.0"* || "$output" == *"Already installed: hyperfine"* ]]
  [[ "$output" == *"Would install Trivy repository configuration"* || "$output" == *"Already installed: trivy"* || "$output" == *"dnf install -y trivy"* ]]
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
