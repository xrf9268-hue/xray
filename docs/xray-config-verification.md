# Xray Configuration Verification Report

**Date**: 2026-02-28
**Xray Stable Baseline**: v26.2.6 (released 2026-02-06)
**Project**: xray-fusion

---

## Executive Summary

✅ **Overall Status**: **COMPLIANT WITH v26.2.6 STABLE BEST PRACTICES**

Current Vision/REALITY deployment remains valid on v26.2.6. This round adds stronger operational compatibility controls:

1. `latest` version resolution hardening (`jq` preferred + fallback parser + retry).
2. Main release ZIP download retry.
3. Compatibility warnings surfaced in deploy and health checks.
4. Optional VLESS Encryption support for Reality inbound/link output (default disabled).

---

## I. Configuration Verification

### 1.1 Reality Inbound

- Protocol: `vless`
- Flow: `xtls-rprx-vision`
- Transport: `tcp + reality`
- Decryption:
  - Default: `none`
  - Optional: configurable via `XRAY_VLESS_DECRYPTION` when VLESS Encryption is enabled

Status: ✅ Compatible with current v26 stable server behavior.

### 1.2 Vision Inbound (dual topology)

- Protocol: `vless`
- Flow: `xtls-rprx-vision`
- Transport: `tcp + tls`
- TLS baseline:
  - `minVersion: "1.3"`
  - `alpn: ["h2", "http/1.1"]`
- Decryption remains fixed to `none`

Status: ✅ Compatible and intentionally strict on TLS baseline.

### 1.3 Client Link Generation

- Reality links include:
  - `security=reality`
  - `flow=xtls-rprx-vision`
  - `pbk`, `sid`, `sni`, `fp`
  - `encryption=` value from state (default `none`, optional custom)
- Vision links remain unchanged and do not inherit Reality encryption settings

Status: ✅ Behavior matches topology design and avoids cross-inbound leakage.

---

## II. v26 Migration Guidance (Deprecation-Aware)

The following fields are considered migration risks when encountered in user-provided or legacy JSON:

| Legacy Field | Risk | Migration Target |
|--------------|------|------------------|
| `allowInsecure` | Deprecated/insecure trust model | Use `pinnedPeerCertSha256` + `verifyPeerCertByName` |
| `verifyPeerCertInNames` | Deprecated | Use `verifyPeerCertByName` |
| `serverNameToVerify` | Deprecated | Use `verifyPeerCertByName` |

Notes:
- These fields are primarily client/outbound TLS concerns.
- Server-side default topology in this project does not require introducing these legacy options.

### Example Migration

#### Avoid (legacy)
```json
{
  "tlsSettings": {
    "allowInsecure": true,
    "verifyPeerCertInNames": ["example.com"]
  }
}
```

#### Prefer (v26-era guidance)
```json
{
  "tlsSettings": {
    "verifyPeerCertByName": "example.com",
    "pinnedPeerCertSha256": ["<sha256-base64-or-hex-per-upstream-format>"]
  }
}
```

---

## III. Runtime Compatibility Guardrails

### 3.1 Deploy-Time Warning Surface

During `xray -test` success path:
- output is scanned for known deprecation markers;
- warnings are emitted as structured logs with actionable hints.

### 3.2 Health Check Compatibility Section

`xrf health` now includes a dedicated **Compatibility** item:
- no warning: pass state;
- known deprecated markers detected: warning state (informational, non-blocking).

### 3.3 Version Resolution Stability

`--version latest` now uses:
- `core::retry` for API fetch and package download;
- `jq` first, fallback parser second for release tag extraction.

This reduces failures from short-lived API/network instability.

---

## IV. Optional VLESS Encryption Scope

VLESS Encryption is now supported as an advanced opt-in capability.

- Default: disabled (`XRAY_VLESS_ENCRYPTION_ENABLED=false`)
- Scope:
  - `reality-only`: applies to the single Reality inbound
  - `vision-reality`: applies only to Reality inbound/link; Vision inbound remains `decryption: none`
- Failure policy:
  - If enabled but values cannot be generated or validated, installation fails fast with explicit logs.

---

## V. Verification Checklist

- [x] Reality inbound syntax/semantics validated on v26 baseline.
- [x] Vision inbound syntax/semantics validated on v26 baseline.
- [x] Client links preserve Vision/Reality role separation.
- [x] Deprecated field migration notes updated (`allowInsecure`, `verifyPeerCertInNames`, `serverNameToVerify`).
- [x] Health report includes compatibility warning summary.

---

## References

- [Xray-core v26.2.6 Release](https://github.com/XTLS/Xray-core/releases/tag/v26.2.6)
- [Compare v26.1.23...v26.2.6](https://github.com/XTLS/Xray-core/compare/v26.1.23...v26.2.6)
- [Xray-examples Repository](https://github.com/XTLS/Xray-examples)
- [VLESS outbound configuration](https://xtls.github.io/en/config/outbounds/vless.html)
