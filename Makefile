SHELL := /usr/bin/env bash

SHELL_SCRIPTS := bootstrap.sh install/lib/common.sh install/install-toolchain.sh install/install-dev-utils.sh install/install-extras.sh $(wildcard ops/*)

.PHONY: help bootstrap dry-run force install-toolchain install-toolchain-dry-run install-dev-utils install-dev-utils-dry-run install-extras install-extras-dry-run lint-shell test-shell

help:
	@echo "Targets:"
	@echo "  make bootstrap   Run bootstrap installer"
	@echo "  make dry-run     Preview bootstrap changes"
	@echo "  make force       Reinstall all managed files"
	@echo "  make install-toolchain          Install base machine toolchain"
	@echo "  make install-toolchain-dry-run  Preview toolchain installation"
	@echo "  make install-dev-utils          Install minimal EC2 dev utilities"
	@echo "  make install-dev-utils-dry-run  Preview minimal EC2 dev utility installation"
	@echo "  make install-extras             Install optional EC2 extras"
	@echo "  make install-extras-dry-run     Preview optional EC2 extras installation"
	@echo "  make lint-shell  Lint shell scripts with shellcheck"
	@echo "  make test-shell  Run bats shell tests"

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

install-extras:
	./install/install-extras.sh

install-extras-dry-run:
	./install/install-extras.sh --dry-run

lint-shell:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(SHELL_SCRIPTS); \
	else \
		echo "shellcheck not found. Install it, then re-run 'make lint-shell'."; \
	fi

test-shell:
	@if command -v bats >/dev/null 2>&1; then \
		bats tests; \
	else \
		echo "bats not found. Install it, then re-run 'make test-shell'."; \
	fi
