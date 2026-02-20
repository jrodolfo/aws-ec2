SHELL := /usr/bin/env bash

SHELL_SCRIPTS := bootstrap.sh install/install-tools.sh $(wildcard tools/*)

.PHONY: help bootstrap dry-run force install-tools install-tools-dry-run lint-shell

help:
	@echo "Targets:"
	@echo "  make bootstrap   Run bootstrap installer"
	@echo "  make dry-run     Preview bootstrap changes"
	@echo "  make force       Reinstall all managed files"
	@echo "  make install-tools          Install base machine tools"
	@echo "  make install-tools-dry-run  Preview tool installation"
	@echo "  make lint-shell  Lint shell scripts with shellcheck"

bootstrap:
	./bootstrap.sh

dry-run:
	./bootstrap.sh --dry-run

force:
	./bootstrap.sh --force

install-tools:
	./install/install-tools.sh

install-tools-dry-run:
	./install/install-tools.sh --dry-run

lint-shell:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_SCRIPTS); \
	else \
		echo "shellcheck not found. Install it, then re-run 'make lint-shell'."; \
	fi
