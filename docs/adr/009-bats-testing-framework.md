# ADR-009: Introduce Automated Testing Framework

**Date**: 2025-11-09
**Status**: Accepted

## Problem

Project lacks automated testing, completely relies on manual testing and static analysis.

## Decision

Establish testing framework and CI/CD pipeline based on bats-core.

## Implementation

- **Test framework**: bats-core + custom test helper functions
- **Unit tests**: 96+ test cases covering core modules
- **CI/CD**: GitHub Actions workflows (Lint, Format, Test, Security)
- **Makefile**: Unified test commands (`make test`, `make test-unit`)

## Rationale

- **Quality assurance**: Automated tests prevent regression errors
- **Fast feedback**: CI/CD automatically runs tests on every commit
- **Documentation**: Test cases are the best usage documentation
- **Continuous improvement**: Test coverage can be continuously improved

## Test Coverage

- lib/args.sh: 100%
- lib/core.sh: ~85%
- lib/plugins.sh: ~90%
- modules/io.sh: ~95%
- services/xray/common.sh: 100%
