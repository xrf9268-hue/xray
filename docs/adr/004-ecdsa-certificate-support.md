# ADR-004: Certificate Validation Supports ECDSA

**Date**: 2025-10-05
**Status**: Accepted

## Problem

Original implementation only validates RSA certificates, modern CAs increasingly use ECDSA.

## Decision

Use public key hash comparison, support both RSA and ECDSA.

## Rationale

- **Universal method**: `openssl pkey` handles all key types
- **Future-oriented**: ECDSA has better performance and smaller size
- **Algorithm-agnostic**: SHA256 hash comparison doesn't depend on specific algorithms

## Implementation

```bash
# Universal method: Compare public key hashes
cert_pub=$(openssl x509 -in cert.pem -pubkey -noout | sha256sum | awk '{print $1}')
key_pub=$(openssl pkey -in key.pem -pubout | sha256sum | awk '{print $1}')
[[ "${cert_pub}" == "${key_pub}" ]] || exit 1
```
