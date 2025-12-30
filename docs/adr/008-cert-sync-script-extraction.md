# ADR-008: Certificate Sync Script Independence

**Date**: 2025-11-09
**Status**: Accepted

## Problem

`modules/web/caddy.sh` contains 195-line embedded HERE document (certificate sync script).

## Decision

Extract as independent script `scripts/caddy-cert-sync.sh`.

## Rationale

- **Maintainability**: Independent scripts are easier to test, debug, and version control
- **Code complexity**: Eliminated large HERE document, caddy.sh reduced from 444 to 259 lines (-41.7%)
- **Single responsibility**: Certificate sync is an independent function, should be an independent module
- **Testability**: Independent scripts can be tested separately without starting the entire installation process

## Impact

- Clearer file structure
- Easier code review
- Supports independent execution and debugging
