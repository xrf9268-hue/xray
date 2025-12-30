# ADR-010: Phase 1 Security Enhancements

**Date**: 2025-11-10
**Status**: Accepted

## Problem

Code review found three high-priority security/stability issues.

## Decision

Implement Phase 1 security fixes:
1. Domain validation enhancement
2. shortId generation unification
3. Lock file management improvement

## Implementation

### 1. Domain Validation Enhancement (lib/validators.sh)
- Added RFC 3927 link-local address detection (169.254.0.0/16)
- Added RFC 6761 special-use domain detection (.test, .invalid)
- Added IPv6 private address detection (::1, fc00::/7, fe80::/10)

### 2. shortId Generation Unification (commands/install.sh)
- Use reliable tool chain: xxd → od → openssl
- Fixed hexdump format string error
- Guarantee all methods generate 16-character hexadecimal strings

### 3. Lock File Management Improvement (scripts/caddy-cert-sync.sh)
- Migrate lock file location: /var/lock → /var/lib/xray-fusion/locks/
- Use install(1) atomic creation (prevent TOCTOU - CWE-362)
- Handle mixed sudo/non-sudo running scenarios (prevent CWE-283)

## Rationale

- **Security**: Close known validation vulnerabilities (IPv6, reserved domains)
- **Reliability**: Unified shortId generation avoids length inconsistency
- **Stability**: Lock file management supports mixed permission runtime environments
- **Standardization**: Follow RFC specifications and systemd best practices

## References

- RFC 6761: Special-Use Domain Names
- RFC 4193: IPv6 Unique Local Addresses
- RFC 3927: IPv4 Link-Local Addresses
