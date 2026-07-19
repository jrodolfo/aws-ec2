# v1.0.0

## Highlights

This first release packages an opinionated, reproducible Amazon Linux 2023 EC2 workstation bootstrap for my personal development workflow.

## Included

- Fresh-host bootstrap flow for Amazon Linux 2023
- Java 21 as the default toolchain
- Maven 3.9+
- Node.js 24 via `nvm`
- User-scoped Codex installation
- Docker and Docker Compose
- GitHub CLI
- Bubblewrap for the Codex sandbox
- Optional Java 25 installed side-by-side without replacing Java 21
- Optional extras installer for `shellcheck`, `shfmt`, `pre-commit`, `yamllint`, `actionlint`, `bats`, `delta`, `fzf`, `zoxide`, `just`, `tokei`, `hyperfine`, and `trivy`
- Optional Ollama installer with configurable model download support
- Verification and maintenance helpers including `check-toolchain`, `check-disk`, `check-memory`, `check-updates`, `linuxinfo`, `ec2info`, and `docker-prune-safe`

## Documentation

- Clear quick start for a fresh EC2 host
- Smoke test checklist in [`docs/smoke-test.md`](docs/smoke-test.md)
- Explicit design philosophy and scope
- Guidance for Docker group re-login behavior and recommended root volume sizing

## Validation

- Shell test suite passing
- Shell lint passing
- Fresh EC2 host validation completed
