# Project Memory: xray-fusion

> This document records key architectural decisions and core lessons learned. For detailed coding standards, development workflows, and technical details, see [@AGENTS.md](./AGENTS.md).

## ⚠️ Mandatory Development Standards

### Pre-Commit Quality Checks (Mandatory)

**All code commits must meet the following conditions, no exceptions**:

```bash
# All must pass before committing
make fmt           # Code formatting (shfmt)
make lint          # Static analysis (shellcheck)
make test-unit     # Unit tests (bats)
```

**Not allowed to commit**:
- ❌ Code that doesn't conform to formatting standards
- ❌ Code with ShellCheck errors/warnings
- ❌ Code with failing tests
- ❌ Untested new features

### Recommended Development Workflow (TDD)

Adopt Test-Driven Development (TDD) mode by default:

```
1. Write tests, commit    # Write tests first, commit tests
2. Code, iterate, commit   # Write code, iterate until passing, commit code
```

**Core Principles** (Reference: [Anthropic Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)):
- Write tests first, clarify expected inputs/outputs
- Verify test failures (ensure tests are valid)
- Implement features, iterate until tests pass
- Run complete checks before committing: `make fmt && make lint && make test-unit`

**Advantages**:
- Clear iteration goals (test cases)
- Incremental improvements with clear validation criteria
- High test coverage, reduced regression errors

---

## Architecture Decision Records (ADR)

### ADR-001: Unified Parameter Passing System (2025-09-XX)
**Problem**: install.sh and xrf use different parameter formats, environment variables don't work in pipes

**Decision**: Completely unify to command-line parameters, remove mixed environment variable mode

**Rationale**:
- Pipe-friendly: `curl | bash -s -- --domain x.com` works normally
- Zero maintenance burden: Single parameter definition point, no compatibility baggage
- Interface consistency: Different entry points use the same parameters

---

### ADR-002: Certificate Sync from Path Unit to Timer (2025-10-05)
**Problem**: systemd Path units are unreliable in nested directories, NFS, and other scenarios

**Decision**: Use Timer to check certificate changes every 10 minutes

**Rationale**:
- More reliable: Avoids inotify filesystem compatibility issues
- Timely enough: Certificates typically update every 60-90 days, 10-minute checks are sufficient
- Easy to test: Predictable execution time

---

### ADR-003: Xray Certificate Update Uses restart Instead of reload (2025-10-05)
**Problem**: Xray-core doesn't support SIGHUP graceful reload

**Decision**: Use `systemctl restart xray` after certificate updates

**Rationale**:
- Official confirmation: GitHub Discussion #1060 explicitly states no support
- Avoid undefined behavior: SIGHUP may cause abnormal process termination
- Official reference: XTLS/Xray-install scripts have no ExecReload

---

### ADR-004: Certificate Validation Supports ECDSA (2025-10-05)
**Problem**: Original implementation only validates RSA certificates, modern CAs increasingly use ECDSA

**Decision**: Use public key hash comparison, support both RSA and ECDSA

**Rationale**:
- Universal method: `openssl pkey` handles all key types
- Future-oriented: ECDSA has better performance and smaller size
- Algorithm-agnostic: SHA256 hash comparison doesn't depend on specific algorithms

---

### ADR-005: Remove OCSP Stapling (2025-10-06)
**Problem**: Let's Encrypt stopped OCSP service on 2025-01-30

**Decision**: Remove `ocspStapling` parameter from TLS configuration

**Rationale**:
- Let's Encrypt official announcement to stop OCSP Must-Staple support
- Keeping invalid parameters increases maintenance burden
- Alternative solution (CRLite) is automatically handled by browsers, no server-side configuration needed

---

### ADR-006: Certificate Sync Concurrency Lock (2025-10-06)
**Problem**: systemd timer may trigger certificate sync script concurrently

**Decision**: Use flock non-blocking lock to protect certificate sync

**Rationale**:
- Prevent race conditions that cause certificate corruption or inconsistency
- Non-blocking mode avoids task pileup, second instance exits immediately
- Consistent with project's existing `core::with_flock` pattern

---

### ADR-007: Mandatory Configuration Validation (2025-10-06)
**Problem**: `XRF_SKIP_XRAY_TEST` environment variable may be abused to skip validation

**Decision**: Completely remove configuration test skip functionality

**Rationale**:
- Configuration validation is a critical security check, should not be bypassable
- Simplify code logic, reduce maintenance burden (removed 21 lines of redundant code)
- Consistent with "clean code over compatibility" principle

---

### ADR-008: Certificate Sync Script Independence (2025-11-09)
**Problem**: `modules/web/caddy.sh` contains 195-line embedded HERE document (certificate sync script)

**Decision**: Extract as independent script `scripts/caddy-cert-sync.sh`

**Rationale**:
- Maintainability: Independent scripts are easier to test, debug, and version control
- Code complexity: Eliminated large HERE document, caddy.sh reduced from 444 to 259 lines (-41.7%)
- Single responsibility: Certificate sync is an independent function, should be an independent module
- Testability: Independent scripts can be tested separately without starting the entire installation process

**Impact**:
- Clearer file structure
- Easier code review
- Supports independent execution and debugging

---

### ADR-009: Introduce Automated Testing Framework (2025-11-09)
**Problem**: Project lacks automated testing, completely relies on manual testing and static analysis

**Decision**: Establish testing framework and CI/CD pipeline based on bats-core

**Implementation**:
- Test framework: bats-core + custom test helper functions
- Unit tests: 96 test cases covering core modules (5 test files)
- CI/CD: GitHub Actions 6 workflows (Lint, Format, Test, Security)
- Makefile: Unified test commands (`make test`, `make test-unit`)

**Rationale**:
- Quality assurance: Automated tests prevent regression errors
- Fast feedback: CI/CD automatically runs tests on every commit
- Documentation: Test cases are the best usage documentation
- Continuous improvement: Test coverage can be continuously improved

**Test Coverage**:
- lib/args.sh: 100% (21 tests)
- lib/core.sh: ~85% (8 tests)
- lib/plugins.sh: ~90% (26 tests)
- modules/io.sh: ~95% (21 tests)
- services/xray/common.sh: 100% (20 tests)
- **Total**: 96 test cases, ~80% code coverage

---

### ADR-010: Phase 1 Security Enhancements (2025-11-10)
**Problem**: Code review found three high-priority security/stability issues

**Decision**: Implement Phase 1 security fixes: domain validation enhancement, shortId generation unification, lock file management improvement

**Implementation**:
1. **Domain Validation Enhancement** (lib/validators.sh)
   - Added RFC 3927 link-local address detection (169.254.0.0/16)
   - Added RFC 6761 special-use domain detection (.test, .invalid)
   - Added IPv6 private address detection (::1, fc00::/7, fe80::/10)
   - Added 9 unit tests

2. **shortId Generation Unification** (commands/install.sh)
   - Use reliable tool chain: xxd → od → openssl
   - Fixed hexdump format string error
   - Guarantee all methods generate 16-character hexadecimal strings

3. **Lock File Management Improvement** (scripts/caddy-cert-sync.sh)
   - Migrate lock file location: /var/lock → /var/lib/xray-fusion/locks/
   - Use install(1) atomic creation (prevent TOCTOU - CWE-362)
   - Handle mixed sudo/non-sudo running scenarios (prevent CWE-283)

**Rationale**:
- Security: Close known validation vulnerabilities (IPv6, reserved domains)
- Reliability: Unified shortId generation avoids length inconsistency
- Stability: Lock file management supports mixed permission runtime environments
- Standardization: Follow RFC specifications and systemd best practices

**Reference Documents**:
- RFC 6761: Special-Use Domain Names
- RFC 4193: IPv6 Unique Local Addresses
- RFC 3927: IPv4 Link-Local Addresses
- Systemd best practices for lock files

---

### ADR-011: Xray v25.12.8 Updates Review (2025-12-09)
**Problem**: Xray-core released multiple updates (v25.9.5 - v25.12.8) with new features requiring evaluation for project integration

**Decision**: Maintain current configuration; no changes required to core implementation

**Analysis**:
1. **`trustedXForwardedFor` (v25.12.8)**: Not applicable
   - Feature applies to XHTTP, WebSocket, HTTP Upgrade protocols only
   - Project uses TCP + TLS/REALITY (Layer 4), not HTTP-based protocols (Layer 7)
   - X-Forwarded-For headers do not exist in TCP streams

2. **VLESS Encryption with ML-KEM-768 (v25.9.5)**: Document for future reference
   - Post-quantum encryption feature (1-RTT PFS, 0-RTT anti-replay)
   - Most valuable for scenarios WITHOUT TLS (CDN, relay chains)
   - Current architecture already has strong encryption (TLS 1.3 + REALITY)
   - Adding encryption on top of TLS provides minimal benefit vs. complexity

3. **Vision "pre-connect" (v25.12.8)**: Observe and wait
   - Experimental feature for latency optimization
   - Requires 3-6 months observation for stability validation
   - Re-evaluate when moved to stable status

4. **uTLS library fix (v25.10.15)**: Document client upgrade recommendation
   - Chrome fingerprint issues resolved
   - Recommend users upgrade clients to v25.10.15+

**Rationale**:
- Configuration verification confirms full compliance with latest official examples
- TLS 1.3 enforcement (ADR-005) exceeds baseline and aligns with 2025 security standards
- ALPN order ["h2", "http/1.1"] matches official recommendations
- All REALITY and Vision parameters validated against Xray-examples repository
- No security vulnerabilities or deprecated features identified in current implementation

**Impact**:
- Zero breaking changes required
- Documentation-only updates needed (client upgrade recommendations)
- Future-proof: VLESS Encryption and pre-connect documented for potential future integration

**Reference**:
- Analysis Report: `xray-updates-analysis.md`
- Configuration Verification: `docs/xray-config-verification.md`
- Official Examples: https://github.com/XTLS/Xray-examples
- Release Notes: https://github.com/XTLS/Xray-core/releases (v25.9.5 - v25.12.8)

---

## Core Lessons Learned

### 1. Verify Official Support, Don't Assume
- Consult official documentation and GitHub discussions
- Verify actual support for critical features (e.g., SIGHUP reload)

### 2. Choose Technology Appropriate for the Scenario
- Timer is more reliable than Path (although it doesn't look as "advanced")
- Mature solutions (Caddy) are better than reinventing the wheel (acme.sh)

### 3. Complete Error Recovery Mechanisms
- Atomic operations need to consider multi-file scenarios
- Add backup and rollback mechanisms

### 4. Secure Defaults and Least Privilege
- systemd services enable security hardening (ProtectSystem, NoNewPrivileges)
- File permissions follow least privilege principle

### 5. Clean Code Over Compatibility
- No users means no burden, don't do unnecessary backward compatibility
- Delete incomplete or deprecated code

### 6. Security Configuration Cannot Be Compromised
- TLS 1.3 mandatory, no backward compatibility (2025 security standard)
- Configuration validation always executes, no skip option
- Concurrency protection must be implemented, prevent race conditions

### 7. Integrity Verification Must Precede Code Execution
- Downloaded code verification must be completed before any source/execution (prevent CWE-494)
- Validation logic cannot depend on the code being validated itself ("chicken-egg" problem)
- Use trusted system tools (git, gpg) for independent verification
- Validation failure must immediately terminate, leave no backdoors

### 8. Upstream Tool Compatibility Requires Defensive Parsing
- External tool output formats change silently between versions (learned from PR #2)
- Exact string matching breaks; use normalized label matching with multiple patterns
- Test with actual tool binaries, not mocked data
- Add version-specific test cases for known format variations
- Silent format changes can cause production failures months/years after release

**Real Example**: Xray v25.8.31+ changed x25519 output from "Public key:" to "Password:", breaking installations until robust parser was implemented (commit dfbce58).

---

**Document Maintenance**: Review regularly, update as project evolves. Follow "specific, concise, actionable" principles.

**Detailed Technical Documentation**: See [@AGENTS.md](./AGENTS.md)
