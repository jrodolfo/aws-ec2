SHELL := /usr/bin/env bash

SHELL_SCRIPTS := bootstrap.sh install/install-toolchain.sh install/install-dev-utils.sh $(wildcard ops/*)

.PHONY: help bootstrap dry-run force install-toolchain install-toolchain-dry-run install-dev-utils install-dev-utils-dry-run lint-shell

help:
	@echo "Targets:"
	@echo "  make bootstrap   Run bootstrap installer"
	@echo "  make dry-run     Preview bootstrap changes"
	@echo "  make force       Reinstall all managed files"
	@echo "  make install-toolchain          Install base machine toolchain"
	@echo "  make install-toolchain-dry-run  Preview toolchain installation"
	@echo "  make install-dev-utils          Install optional EC2 dev utilities"
	@echo "  make install-dev-utils-dry-run  Preview optional EC2 dev utility installation"
	@echo "  make lint-shell  Lint shell scripts with shellcheck"

bootstrap:
	./bootstrap.sh

dry-run:
	./bootstrap.sh --dry-run

force:
	./bootstrap.sh --force

install-toolchain:
	./install/install-toolchain.sh

install-toolchain-dry-run:
	./install/install-toolchain.sh --dry-run

install-dev-utils:
	./install/install-dev-utils.sh

install-dev-utils-dry-run:
	./install/install-dev-utils.sh --dry-run

lint-shell:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_SCRIPTS); \
	else \
		echo "shellcheck not found. Install it, then re-run 'make lint-shell'."; \
	fi
