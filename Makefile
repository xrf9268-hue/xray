SHELL := /usr/bin/env bash
# Source files for linting (includes .bats for shellcheck)
# ShellCheck can handle bats files - see tests/.shellcheckrc for bats-specific config
SRC_LINT := $(shell git ls-files '*.sh' 'bin/*' 'commands/*' 'lib/*' 'modules/**/*' 'services/**/*' 'plugins/**/*.sh' 'scripts/**/*.sh' 'tests/**/*.sh' 'tests/**/*.bats' 2>/dev/null)

# Source files for formatting (excludes .bats - shfmt doesn't support @test syntax)
# See: https://github.com/mvdan/sh/issues/291
SRC_FMT  := $(shell git ls-files '*.sh' 'bin/*' 'commands/*' 'lib/*' 'modules/**/*' 'services/**/*' 'plugins/**/*.sh' 'scripts/**/*.sh' 'tests/**/*.sh' 2>/dev/null)

.PHONY: lint fmt test test-unit test-integration

lint:
	@shellcheck -S error -S warning -x $(SRC_LINT)

fmt:
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not found; see https://github.com/mvdan/sh"; exit 2; }
	@shfmt -i 2 -ci -sr -bn -ln=bash -w $(SRC_FMT)
	@echo "Formatted with shfmt"

test: test-unit test-integration

test-unit:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found; see https://github.com/bats-core/bats-core"; exit 2; }
	@bats tests/unit/*.bats

test-integration:
	@command -v bats >/dev/null 2>&1 || { echo "bats not found; see https://github.com/bats-core/bats-core"; exit 2; }
	@bats tests/integration/*.bats

help:
	@echo "Available targets:"
	@echo "  lint             - Run ShellCheck on all shell scripts"
	@echo "  fmt              - Format all shell scripts with shfmt"
	@echo "  test             - Run all tests (unit + integration)"
	@echo "  test-unit        - Run unit tests"
	@echo "  test-integration - Run integration tests"
	@echo "  help             - Show this help message"
