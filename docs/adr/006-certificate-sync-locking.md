# ADR-006: Certificate Sync Concurrency Lock

**Date**: 2025-10-06
**Status**: Accepted

## Problem

systemd timer may trigger certificate sync script concurrently.

## Decision

Use flock non-blocking lock to protect certificate sync.

## Rationale

- Prevent race conditions that cause certificate corruption or inconsistency
- Non-blocking mode avoids task pileup, second instance exits immediately
- Consistent with project's existing `core::with_flock` pattern
