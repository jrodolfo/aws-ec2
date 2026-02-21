# aws-ec2

Reusable server setup repository for provisioning a fresh Linux EC2 instance with personal dotfiles and utility scripts.

## Repository Layout

```text
aws-ec2/
├── install/
│   ├── lib/
│   │   └── common.sh
│   ├── install-dev-utils.sh
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

## Install Base Toolchain (EC2)

```bash
./install/install-toolchain.sh
```

Default behavior:
- updates OS packages (`dnf update -y`)
- installs: Docker, Docker Compose plugin, Git, GitHub CLI, Java, Maven, Node/NPM, htop, tree
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

## Install Optional Dev Utilities (EC2)

```bash
./install/install-dev-utils.sh
```

Installs optional utilities useful for terminal workflows on EC2:
- `shellcheck`
- `shfmt`
- `jq`
- `yq`
- `ripgrep` (`rg`)
- `fd`/`fdfind`
- `gh`
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
- `watch` (installed only if missing)

`act` is intentionally excluded (recommended for local dev machines, not server hosts).
`gnu-sed` and `coreutils` are also not needed on EC2 (Amazon Linux already provides GNU tools).

Useful options:

```bash
./install/install-dev-utils.sh --dry-run
./install/install-dev-utils.sh --no-update
```

Mac-only note:

```bash
PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
```

Use this PATH tweak on macOS only. Do not add it to EC2 startup files.

Homebrew-specific `fzf` Vim runtime examples (for example `set rtp+=/opt/homebrew/opt/fzf`) are also macOS-only and should not be added to EC2 `.vimrc`.

## Fresh EC2 Minimum Sequence

On a brand-new Amazon Linux EC2 instance, run this first:

```bash
sudo dnf update -y
sudo dnf install -y git
git clone https://github.com/<your-user>/<your-repo>.git
cd <your-repo>
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
make bootstrap
```

If the repository is private, configure GitHub authentication before `git clone`.

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
