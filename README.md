# aws-ec2

[![Shell Lint](https://github.com/jrodolfo/aws-ec2/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/jrodolfo/aws-ec2/actions/workflows/shell-lint.yml)
[![Script Smoke](https://github.com/jrodolfo/aws-ec2/actions/workflows/bootstrap-dry-run.yml/badge.svg)](https://github.com/jrodolfo/aws-ec2/actions/workflows/bootstrap-dry-run.yml)
[![Bash](https://img.shields.io/badge/Shell-Bash-121011?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![ShellCheck](https://img.shields.io/badge/Lint-ShellCheck-89e051)](https://www.shellcheck.net/)
[![Tests](https://img.shields.io/badge/Tests-Bats-15aeef)](https://bats-core.readthedocs.io/)
[![AWS EC2](https://img.shields.io/badge/AWS-EC2-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/ec2/)
[![Amazon Linux](https://img.shields.io/badge/Platform-Amazon%20Linux-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/amazon-linux-2/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Opinionated bootstrap for turning a fresh Amazon Linux 2023 EC2 instance into my preferred development workstation. This repository optimizes for reproducibility and simplicity, not broad compatibility with arbitrary Linux distributions or historical machine state.

This repository is maintained primarily for my own EC2 development workflow, but it may also serve as a reference for engineers building a reproducible Amazon Linux 2023 workstation.

## Quick Start

Start with a root volume sized for development work, not the tiny default. A 30 GiB gp3 root volume is recommended for the base development workstation. Use more space when keeping several Docker images, larger Ollama models, or additional project data.

```bash
sudo dnf update -y
sudo dnf install -y git
git clone https://github.com/jrodolfo/aws-ec2.git
cd aws-ec2
./install/install-toolchain.sh
./install/install-dev-utils.sh
./bootstrap.sh
check-toolchain
```

If Docker commands still fail without `sudo` after installation, log out and back in so the new `docker` group membership takes effect, then run `check-toolchain` again.

Optional after the base setup:

Optional tools are kept separate so the base workstation remains small and quick to provision.

```bash
./install/install-extras.sh
./install/install-ollama.sh
check-toolchain
```

After the installation completes, follow [`docs/smoke-test.md`](docs/smoke-test.md) to validate the workstation on a fresh host.

Notes:
- `install-toolchain.sh` installs Docker, Docker Compose, Git, GitHub CLI, Bubblewrap, Java 21, Maven 3.9+, Python 3.11, `yt-dlp`, Node 24 via `nvm`, and Codex under the target user.
- `install-dev-utils.sh` installs the minimal extra tools used by this setup: `ripgrep` and `pipx`.
- `bootstrap.sh` installs dotfiles and helper scripts into the current user account.
- `install-toolchain.sh` adds the current user to the `docker` group. The current shell may not see that change yet, so `docker` can still fail without `sudo` until you log out and back in.
- `--java-mode adoptium25` installs Java 25 side-by-side under `/opt/java` without overriding the default Java 21 toolchain.
- `check-toolchain` is the fastest way to confirm the machine is ready.

If the repository is private, configure GitHub authentication before `git clone`.

## Script Reference

### Required Setup

- `./install/install-toolchain.sh`
  Installs the base development toolchain for a fresh Amazon Linux 2023 host.
  Useful flags: `--dry-run`, `--no-update`, `--user ec2-user`, `--java-mode adoptium25`

- `./install/install-dev-utils.sh`
  Installs minimal day-to-day utilities used by this setup.
  Useful flags: `--dry-run`, `--no-update`

- `./bootstrap.sh`
  Installs repository dotfiles into `$HOME` and copies helper scripts into `$HOME/.local/bin`.
  Useful flags: `--dry-run`, `--force`

### Optional Setup

- `./install/install-extras.sh`
  Installs optional extras such as `shellcheck`, `shfmt`, `pre-commit`, `yamllint`, `actionlint`, `bats`, `delta`, `fzf`, `zoxide`, `just`, `tokei`, `hyperfine`, and `trivy`.
  Uses a mix of `dnf`, `pipx`, `cargo`, and official release binaries.
  Useful flags: `--dry-run`, `--no-update`

- `./install/install-ollama.sh`
  Installs Ollama and configures the service so Docker containers on the same host can reach it.
  Useful flags: `--dry-run`, `--version 0.11.6`, `--model <name>`, `--no-start`

### Verification And Ops

- `check-toolchain`
  Shows the current core toolchain and optional extras with versions.

- `check-disk`
  Shows root filesystem usage, large home directories, and Docker disk usage.

- `check-memory --top 10`
  Shows a memory snapshot and top memory-consuming processes.

- `check-updates`
  Checks for Amazon Linux release updates on `dnf`-based systems.

- `docker-prune-safe`
  Prunes unused Docker images and build cache without deleting volumes.

- `linuxinfo`
  Prints a local Linux system snapshot.

- `ec2info`
  Prints EC2 instance and Linux summary details.

- `showip`
  Prints the current public IP.

## Make Targets

Use `make help` to see the available shortcuts. The main targets are:

```bash
make install-toolchain
make install-dev-utils
make install-extras
make install-ollama
make bootstrap
make test-shell
make lint-shell
```

## Customization

If you want to adapt this repository for your own setup:

1. Fork the repository.
2. Replace files in `dotfiles/` and `ops/` with your own.
3. Run the same base sequence:

```bash
./install/install-toolchain.sh
./install/install-dev-utils.sh
./bootstrap.sh
```

`bootstrap.sh` installs whatever is currently in `dotfiles/` and `ops/`.

## Restore From An Existing Host

Use your PEM key and the correct SSH username for the AMI:

```bash
scp -i ~/.ssh/<key>.pem ec2-user@<public-ip>:~/.bashrc dotfiles/
scp -i ~/.ssh/<key>.pem ec2-user@<public-ip>:~/.bash_profile dotfiles/
scp -i ~/.ssh/<key>.pem ec2-user@<public-ip>:~/.vimrc dotfiles/
scp -i ~/.ssh/<key>.pem ec2-user@<public-ip>:'~/bin/*' ops/
```

Common usernames:
- Amazon Linux: `ec2-user`
- Ubuntu: `ubuntu`

For SSH setup and troubleshooting notes, see [`doc/ssh/NOTES.md`](doc/ssh/NOTES.md).

## Repository Layout

```text
aws-ec2/
├── install/
├── dotfiles/
├── ops/
├── tests/
└── bootstrap.sh
```

## CI

GitHub Actions runs shell lint, dry-run smoke checks, and Bats tests on pushes and pull requests.

## Contact

- Software Developer: Rod Oliveira
- GitHub: https://github.com/jrodolfo
- Webpage: https://jrodolfo.net

## License

- MIT License
- Copyright (c) 2026 Rod Oliveira
- See [LICENSE](./LICENSE)
