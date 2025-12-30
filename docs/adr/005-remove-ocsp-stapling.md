# ADR-005: Remove OCSP Stapling

**Date**: 2025-10-06
**Status**: Accepted

## Problem

Let's Encrypt stopped OCSP service on 2025-01-30.

## Decision

Remove `ocspStapling` parameter from TLS configuration.

## Rationale

- Let's Encrypt official announcement to stop OCSP Must-Staple support
- Keeping invalid parameters increases maintenance burden
- Alternative solution (CRLite) is automatically handled by browsers, no server-side configuration needed
