# ADR-012: Xray v26.1.23 Updates Review

**Date**: 2026-01-24
**Status**: Accepted

## Problem

Xray-core released v26.1.23 (2026-01-23) with significant new features and deprecation warnings requiring evaluation for project compatibility.

## Decision

Maintain current configuration; no changes required to core implementation.

## Analysis

### 1. Deprecation Warnings (v26.x)

**VLESS without flow** - Critical deprecation warning added.

**Project Status**: Already compliant. All VLESS configurations include `flow: "xtls-rprx-vision"`:
- `configure.sh:240` - Reality-only inbound
- `configure.sh:332` - Vision inbound
- `configure.sh:358` - Reality inbound (dual topology)

**Other deprecations** (not applicable):
- `allowInsecure` - Not used
- Shadowsocks/VMess/Trojan protocols - Not used

### 2. TUN Inbound Support (v26.1.23)
**Not applicable**
- Client-side feature for Windows/Linux/Android/macOS
- Server deployments do not require TUN inbound
- Requires manual system route configuration

### 3. Process-Based Routing (v26.1.23)
**Not applicable**
- Client-side routing feature
- Matches process name/path for traffic filtering
- Not relevant for server configurations

### 4. Hysteria 2 Protocol (v26.1.23)
**Document for future reference**
- New UDP-based protocol with port hopping
- Salamander obfuscation layer available
- Current REALITY/Vision stack sufficient for most use cases

### 5. TLS Certificate Pinning Changes (v26.x)
**Not applicable**
- `pinnedPeerCertSha256` replaces previous dual parameters
- Client-side TLS configuration only
- Server certificates unaffected

### 6. REALITY Client Improvements (v26.x)
**Document only**
- Enhanced MITM detection warnings in client logs
- No server-side configuration changes required

## Rationale

- All VLESS configurations already include required `flow` parameter
- Project uses recommended REALITY + Vision stack
- TLS 1.3 enforcement (`minVersion: "1.3"`) exceeds baseline security
- Dynamic version fetching (`version="latest"`) automatically uses v26.1.23

## Impact

- Zero breaking changes required
- Full compatibility with Xray-core v26.1.23 confirmed
- No configuration updates needed

## References

- Xray-core v26.1.23 Release: https://github.com/XTLS/Xray-core/releases/tag/v26.1.23
- Previous Review: [ADR-011](./011-xray-v25-review.md) (v25.12.8)
