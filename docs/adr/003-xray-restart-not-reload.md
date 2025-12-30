# ADR-003: Xray Certificate Update Uses restart Instead of reload

**Date**: 2025-10-05
**Status**: Accepted

## Problem

Xray-core doesn't support SIGHUP graceful reload.

## Decision

Use `systemctl restart xray` after certificate updates.

## Rationale

- **Official confirmation**: GitHub Discussion #1060 explicitly states no support
- **Avoid undefined behavior**: SIGHUP may cause abnormal process termination
- **Official reference**: XTLS/Xray-install scripts have no ExecReload

## Reference

- https://github.com/XTLS/Xray-core/discussions/1060
