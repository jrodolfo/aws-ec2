# aws-ec2

[![Shell Lint](https://github.com/jrodolfo/aws-ec2/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/jrodolfo/aws-ec2/actions/workflows/shell-lint.yml)
[![Script Smoke](https://github.com/jrodolfo/aws-ec2/actions/workflows/bootstrap-dry-run.yml/badge.svg)](https://github.com/jrodolfo/aws-ec2/actions/workflows/bootstrap-dry-run.yml)
[![Bash](https://img.shields.io/badge/Shell-Bash-121011?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![ShellCheck](https://img.shields.io/badge/Lint-ShellCheck-89e051)](https://www.shellcheck.net/)
[![Tests](https://img.shields.io/badge/Tests-Bats-15aeef)](https://bats-core.readthedocs.io/)
[![AWS EC2](https://img.shields.io/badge/AWS-EC2-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/ec2/)
[![Amazon Linux](https://img.shields.io/badge/Platform-Amazon%20Linux-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/amazon-linux-2/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Reusable server setup repository for provisioning a fresh Linux EC2 instance with personal dotfiles and utility scripts.

## Design Philosophy

This repository is opinionated by design. It bootstraps a fresh Amazon Linux 2023 EC2 instance into my preferred development environment. It is optimized for reproducibility and simplicity rather than supporting every possible existing configuration or Linux distribution.

## Project Structure

```text
aws-ec2/
├── install/
│   ├── lib/
│   │   └── common.sh
│   ├── install-dev-utils.sh
│   ├── install-extras.sh
│   ├── install-ollama.sh
│   └── install-toolchain.sh
├── dotfiles/
│   ├── .bashrc
│   ├── .bash_profile
│   ├── .vimrc
│   └── .gitconfig
├── ops/
│   ├── check-memory
│   ├── check-updates
│   ├── check-disk
│   ├── check-toolchain
│   ├── docker-prune-safe
│   ├── ec2info
│   ├── linuxinfo
│   └── showip
├── tests/
│   └── scripts.bats
└── bootstrap.sh
```

## Who This Is For

- Use as-is: run this repo directly to apply the author's EC2 setup.
- Customize: fork and edit `dotfiles/` and `ops/` to apply your own setup.

## Fresh EC2 Minimum Sequence

### Use As-Is (author setup)

Start with a root volume sized for development work, not the tiny default. For Docker and local AI tooling, use roughly 30 to 40 GB.

```bash
sudo dnf update -y
sudo dnf install -y git
git clone https://github.com/jrodolfo/aws-ec2.git
cd aws-ec2
./install/install-toolchain.sh
./install/install-dev-utils.sh
./bootstrap.sh
```

Optional, if you prefer Make targets:

```bash
sudo dnf install -y make
make install-toolchain-dry-run
make install-toolchain
make install-dev-utils-dry-run
make install-dev-utils
make install-extras-dry-run
make install-extras
make bootstrap
```

If the repository is private, configure GitHub authentication before `git clone`.

### Customize for Your Own Setup

If you want your own configuration:

1. Fork this repository.
2. Replace files in `dotfiles/` and `ops/` with your own.
3. Run:

```bash
./install/install-toolchain.sh
./install/install-dev-utils.sh
./bootstrap.sh
```

`bootstrap.sh` installs whatever is currently in `dotfiles/` and `ops/`.

## SSH Access

For complete SSH setup and troubleshooting instructions, see [`doc/ssh/NOTES.md`](doc/ssh/NOTES.md).

## Install Base Toolchain (EC2)

```bash
./install/install-toolchain.sh
```

Default behavior:
- updates OS packages with `dnf update -y`
- installs Docker, Docker Compose, Git, GitHub CLI, Bubblewrap, Java 21, Apache Maven 3.9+, `curl`, Python 3.11, and `yt-dlp`
- installs `nvm` for the target user, then installs Node.js 24 and Codex inside that user-scoped environment
- enables and starts Docker service
- adds the selected user to the `docker` group
- installs a managed `~/.bashrc.d/aws-ec2-toolchain.sh` snippet for `nvm`, `PATH`, and Python alias setup

Useful options:

```bash
./install/install-toolchain.sh --dry-run
./install/install-toolchain.sh --no-update
./install/install-toolchain.sh --user ec2-user
./install/install-toolchain.sh --java-mode distro
./install/install-toolchain.sh --java-mode adoptium25
```

Notes:
- Script is tuned for Amazon Linux 2023 with `dnf`, `rpm`, and a standard fresh-host layout.
- After Docker group changes, log out and back in.
- Docker Compose package names may vary by AMI; the script falls back automatically if `docker-compose-plugin` is unavailable.
- Binary fallback installs Docker Compose as a Docker CLI plugin at `/usr/libexec/docker/cli-plugins/docker-compose`.
- Java 21 stays the default toolchain.
- `--java-mode adoptium25` installs Java 25 side-by-side under `/opt/java` without overriding the default `java`, `javac`, or Maven runtime.

## Python and yt-dlp Baseline (Amazon Linux 2023)

`yt-dlp` requires Python 3.10+.
This setup installs `yt-dlp` with Python 3.11 user-local packages to avoid runtime mismatches.

```bash
python3.11 --version
~/.local/bin/yt-dlp --version
```

If `yt-dlp --version` fails after running the toolchain installer, stop and fix Python and `yt-dlp` before continuing bootstrap steps.

## Install Minimal Dev Utilities (EC2)

```bash
./install/install-dev-utils.sh
```

Installs only the minimal extra tools used by this setup:
- `ripgrep` (`rg`)
- `pipx`

Fallback behavior:
- If `ripgrep` is unavailable in enabled repos, the script installs it via `cargo`.
- The script updates `~/.bashrc` so `~/.cargo/bin` and `~/.local/bin` are in `PATH` when needed.

Useful options:

```bash
./install/install-dev-utils.sh --dry-run
./install/install-dev-utils.sh --no-update
```

## Install Optional Extras (EC2)

If you want additional utilities that are not required for the base setup, run:

```bash
./install/install-extras.sh
```

This includes tools such as:
- `shellcheck`
- `shfmt`
- `pre-commit`
- `yamllint`
- `actionlint`
- `bats`
- `git-delta`
- `fzf`
- `zoxide`
- `just`
- `tokei`
- `hyperfine`
- `trivy`

Useful options:

```bash
./install/install-extras.sh --dry-run
./install/install-extras.sh --no-update
```

Installation notes:
- The script is optimized for a fresh Amazon Linux 2023 host.
- It uses a mix of `dnf`, `pipx`, `cargo`, and official release binaries depending on the tool.
- If one of the declared extras cannot be installed in the standard fresh-host path, the script fails instead of silently skipping it.

## Install Optional Ollama (EC2)

If you want a local Ollama service for model work on the EC2 host, run:

```bash
./install/install-ollama.sh
```

Default behavior:
- installs Ollama using the official Linux installer
- configures a systemd override with `OLLAMA_HOST=0.0.0.0:11434`
- enables and restarts the `ollama` service

Useful options:

```bash
./install/install-ollama.sh --dry-run
./install/install-ollama.sh --version 0.11.6
./install/install-ollama.sh --model qwen2.5-coder:7b
./install/install-ollama.sh --model llama3.1:8b --model nomic-embed-text
./install/install-ollama.sh --no-start
```

Notes:
- The default host binding allows Docker containers on the same machine to reach Ollama.
- Model downloads are optional. No models are pulled unless you request them with `--model`.
- Keep your EC2 security group tight if you expose port `11434`.

## Bootstrap on a New Machine

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Or use Make:

```bash
make bootstrap
```

What it does:
- installs dotfiles to `$HOME`
- installs EC2 helper scripts from `ops/` to `$HOME/.local/bin`
- preserves replaced files in `~/.bootstrap-backups/<timestamp>/`

Useful `ops/` helpers after bootstrap:
- `check-disk` shows root filesystem usage, large home directories, and Docker disk usage
- `check-memory --top 10` shows a memory snapshot and top memory-consuming processes
- `check-toolchain` shows the current core toolchain and optional extras with versions
- `check-updates` checks for Amazon Linux release updates on `dnf`-based systems
- `docker-prune-safe` prunes unused Docker images and build cache without deleting volumes
- `ec2info` prints EC2 instance and Linux summary details
- `linuxinfo` prints a local Linux system snapshot
- `showip` prints the current public IP

## Pull Files from an Existing EC2 Host

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

## Bootstrap Options

```bash
./bootstrap.sh --dry-run
./bootstrap.sh --force
./bootstrap.sh --help
```

- `--dry-run`: prints planned actions without writing files
- `--force`: reinstalls even when destination content is unchanged

## Make Shortcuts

```bash
make help
make dry-run
make force
make install-toolchain
make install-toolchain-dry-run
make install-dev-utils
make install-dev-utils-dry-run
make install-extras
make install-extras-dry-run
make install-ollama
make install-ollama-dry-run
make lint-shell
make test-shell
```

## CI

GitHub Actions runs shell checks and smoke tests on every push and pull request:
- `bash -n bootstrap.sh`
- `make lint-shell`
- `./bootstrap.sh --dry-run`
- `./install/install-toolchain.sh --dry-run --no-update`
- `./install/install-dev-utils.sh --dry-run --no-update`
- `./install/install-extras.sh --dry-run --no-update`
- `./install/install-ollama.sh --dry-run`
- `make test-shell`

## Contact

- Software Developer: Rod Oliveira
- GitHub: https://github.com/jrodolfo
- Webpage: https://jrodolfo.net

## License

- MIT License
- Copyright (c) 2026 Rod Oliveira
- See [LICENSE](./LICENSE)
