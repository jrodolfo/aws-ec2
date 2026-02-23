# aws-ec2

Reusable server setup repository for provisioning a fresh Linux EC2 instance with personal dotfiles and utility scripts.

## Who This Is For

- Use as-is: run this repo directly to apply the author's EC2 setup.
- Customize: fork/edit `dotfiles/` and `ops/` to apply your own setup.

## Fresh EC2 Minimum Sequence

### Use As-Is (author setup)

```bash
sudo dnf update -y
sudo dnf install -y git
git clone https://github.com/jrodolfo/aws-ec2.git
cd aws-ec2
./install/install-toolchain.sh
./install/install-dev-utils.sh
./bootstrap.sh
```

Optional (if you prefer Make targets):

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

For complete SSH setup and troubleshooting instructions, see:
- [`doc/ssh/NOTES.md`](doc/ssh/NOTES.md)

## Install Base Toolchain (EC2)

```bash
./install/install-toolchain.sh
```

Default behavior:
- updates OS packages (`dnf update -y`)
- installs: Docker, Docker Compose, Git, GitHub CLI, Java, Node/NPM, curl
- enables and starts Docker service
- adds the selected user to the `docker` group

Useful options:

```bash
./install/install-toolchain.sh --dry-run
./install/install-toolchain.sh --no-update
./install/install-toolchain.sh --user ec2-user
./install/install-toolchain.sh --java-mode distro
./install/install-toolchain.sh --java-mode adoptium25
```

Notes:
- Script is tuned for Amazon Linux (`dnf`/`rpm`).
- After Docker group changes, log out and back in.
- Docker Compose package names may vary by AMI; the script falls back automatically if `docker-compose-plugin` is unavailable.
- Binary fallback installs Docker Compose as a Docker CLI plugin at `/usr/libexec/docker/cli-plugins/docker-compose`.

## Install Minimal Dev Utilities (EC2)

```bash
./install/install-dev-utils.sh
```

Installs only the minimal extra tools used by this setup:
- `ripgrep` (`rg`)
- `pipx`

Fallback behavior:
- If `ripgrep` is unavailable in enabled repos, script installs it via `cargo`.
- Script updates `~/.bashrc` so `~/.cargo/bin` and `~/.local/bin` are in `PATH` when needed.

Useful options:

```bash
./install/install-dev-utils.sh --dry-run
./install/install-dev-utils.sh --no-update
```

## Install Optional Extras (EC2)

If you want additional utilities (not required for the base setup), run:

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

Useful options:

```bash
./install/install-extras.sh --dry-run
./install/install-extras.sh --no-update
```

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

## Pull Files from an Existing EC2 Host

Use your PEM key and correct SSH username for the AMI:

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
- `make test-shell`

## Repository Layout

```text
aws-ec2/
├── install/
│   ├── lib/
│   │   └── common.sh
│   ├── install-dev-utils.sh
│   ├── install-extras.sh
│   └── install-toolchain.sh
├── dotfiles/
│   ├── .bashrc
│   ├── .bash_profile
│   ├── .vimrc
│   └── .gitconfig
├── ops/
│   ├── ec2info
│   ├── linuxinfo
│   └── showip
├── tests/
│   └── scripts.bats
└── bootstrap.sh
```
