# ADR-002: Certificate Sync from Path Unit to Timer

**Date**: 2025-10-05
**Status**: Accepted

## Problem

systemd Path units are unreliable in nested directories, NFS, and other scenarios.

## Decision

Use Timer to check certificate changes every 10 minutes.

## Rationale

- **More reliable**: Avoids inotify filesystem compatibility issues
- **Timely enough**: Certificates typically update every 60-90 days, 10-minute checks are sufficient
- **Easy to test**: Predictable execution time
