# ADR-011: Xray v25.12.8 Updates Review

**Date**: 2025-12-09
**Status**: Accepted

## Problem

Xray-core released multiple updates (v25.9.5 - v25.12.8) with new features requiring evaluation for project integration.

## Decision

Maintain current configuration; no changes required to core implementation.

## Analysis

### 1. `trustedXForwardedFor` (v25.12.8)
**Not applicable**
- Feature applies to XHTTP, WebSocket, HTTP Upgrade protocols only
- Project uses TCP + TLS/REALITY (Layer 4), not HTTP-based protocols (Layer 7)
- X-Forwarded-For headers do not exist in TCP streams

### 2. VLESS Encryption with ML-KEM-768 (v25.9.5)
**Document for future reference**
- Post-quantum encryption feature (1-RTT PFS, 0-RTT anti-replay)
- Most valuable for scenarios WITHOUT TLS (CDN, relay chains)
- Current architecture already has strong encryption (TLS 1.3 + REALITY)

### 3. Vision "pre-connect" (v25.12.8)
**Observe and wait**
- Experimental feature for latency optimization
- Requires 3-6 months observation for stability validation

### 4. uTLS library fix (v25.10.15)
**Document client upgrade recommendation**
- Chrome fingerprint issues resolved
- Recommend users upgrade clients to v25.10.15+

## Rationale

- Configuration verification confirms full compliance with latest official examples
- TLS 1.3 enforcement exceeds baseline and aligns with 2025 security standards
- All REALITY and Vision parameters validated against Xray-examples repository

## Impact

- Zero breaking changes required
- Documentation-only updates needed
- Future-proof: VLESS Encryption and pre-connect documented for potential integration

## References

- Official Examples: https://github.com/XTLS/Xray-examples
- Release Notes: https://github.com/XTLS/Xray-core/releases
