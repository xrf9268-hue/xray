# ADR-007: Mandatory Configuration Validation

**Date**: 2025-10-06
**Status**: Accepted

## Problem

`XRF_SKIP_XRAY_TEST` environment variable may be abused to skip validation.

## Decision

Completely remove configuration test skip functionality.

## Rationale

- Configuration validation is a critical security check, should not be bypassable
- Simplify code logic, reduce maintenance burden (removed 21 lines of redundant code)
- Consistent with "clean code over compatibility" principle
