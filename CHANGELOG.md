# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-stage improvement plan** based on comprehensive code review (docs/IMPROVEMENT_PLAN.md)
- **Centralized configuration management** (lib/defaults.sh) - Single source of truth for all default values
- **Standardized error code definitions** (lib/errors.sh) - Consistent error handling across all scripts
- **Integration test framework** (tests/integration/) - Foundation for comprehensive integration testing
- **ShellDoc-style API documentation** - 19 core functions now fully documented
- **Fatal and critical log levels** - Better distinction between recoverable and unrecoverable errors
- **Enhanced domain validation**:
  - IPv6 private address detection (::1, fc00::/7, fe80::/10) - RFC 4193, RFC 4291
  - RFC 6761 special-use domain rejection (.test, .invalid)
  - RFC 3927 link-local address rejection (169.254.0.0/16)
- **TLS certificate verification helper** (verify_tls_certificates) - Improved code modularity

### Changed
- **Certificate sync lock file location** - From /var/lock to /var/lib/xray-fusion/locks/ for persistence
- **ShortId generation** - Uses xxd → od → openssl priority chain instead of unreliable hexdump
- **Path validation** - Tightened regex to reject `..` and `//` patterns
- **Certificate lookup optimization** - Reduced maxdepth from 4 to 3 (~25% performance improvement)
- **Error handling in ERR trap** - Uses `critical` level instead of `error`
- **Log output formatting** - Increased column width from %-5s to %-8s for fatal/critical

### Fixed
- **Domain validator security** - Now rejects all RFC-defined private and special-use addresses
- **Lock file ownership** - Handles mixed sudo/non-sudo scenarios correctly (CWE-283)
- **ShortId generation consistency** - All methods now produce 16-character hexadecimal strings
- **Fatal error patterns** - Converted 5 error+exit patterns to single `fatal` log calls

### Security
- **Enhanced input validation** - Comprehensive domain name validation with RFC compliance
- **Improved lock file security** - Atomic creation with install(1) to prevent TOCTOU (CWE-362)
- **Stricter path validation** - Prevents directory traversal and injection attacks
- **Ownership verification** - Lock files always writable by legitimate users

### Documentation
- **Function Documentation Standard** added to AGENTS.md
- **API documentation** for lib/validators.sh, lib/core.sh, modules/io.sh
- **Security considerations** documented with CWE references
- **Usage examples** for all public functions

---

## [1.0.0] - 2025-11-09

### Added
- **Automated testing framework** based on bats-core
  - 96 unit tests with ~80% code coverage
  - 5 test files covering core modules
- **CI/CD pipeline** (GitHub Actions)
  - Lint workflow (ShellCheck)
  - Format workflow (shfmt)
  - Test workflow (bats)
  - Security workflow
- **Independent certificate sync script** (scripts/caddy-cert-sync.sh)
  - Extracted from caddy.sh HERE-doc (195 lines → standalone script)
  - Supports both repo and standalone execution
- **Architecture Decision Records** (ADR-009)

### Changed
- **Certificate sync mechanism** - From systemd Path to Timer unit (ADR-002)
  - More reliable than inotify-based Path units
  - 10-minute check interval (sufficient for 60-90 day cert lifetimes)
- **Xray certificate reload** - Uses restart instead of reload (ADR-003)
  - Xray-core does not support SIGHUP graceful reload
  - Confirmed by official GitHub discussions
- **Certificate validation** - Supports both RSA and ECDSA (ADR-004)
  - Uses public key hash comparison (algorithm-agnostic)
- **Module organization** - Extracted cert-sync from monolithic script (ADR-008)
  - Reduced caddy.sh from 444 lines to 259 lines (-41.7%)

### Removed
- **OCSP stapling support** - Let's Encrypt sunset on 2025-01-30 (ADR-005)
- **Config test skip option** - XRF_SKIP_XRAY_TEST environment variable (ADR-007)
  - Configuration validation is critical and cannot be bypassed

### Fixed
- **Certificate sync concurrency** - Added flock-based protection (ADR-006)
- **Atomic file operations** - Consistent across all modules
- **Trap handling** - Removed traps from utility functions to avoid interference

### Security
- **Systemd service hardening**
  - ProtectSystem=strict
  - NoNewPrivileges=true
  - PrivateTmp=true
- **Plugin system** - Path traversal protection
- **Atomic lock file creation** - Prevents TOCTOU (CWE-362) and ownership issues (CWE-283)

---

## [0.9.0] - 2025-09-XX

### Added
- **Unified parameter system** (ADR-001)
  - Consistent --arg syntax across install.sh and xrf
  - Pipe-friendly: `curl | bash -s -- --domain x.com`
- **Plugin system architecture**
  - Hook-based extension system
  - Enable/disable plugins via CLI
- **Four built-in plugins**
  - cert-auto: Caddy-based automatic certificate management
  - firewall: UFW firewall configuration
  - logrotate-obs: Log rotation for OBS scenarios
  - links-qr: QR code generation for client links
- **Dual topology support**
  - reality-only: VLESS+Reality on port 443
  - vision-reality: VLESS+Vision (8443) + Reality (443)

### Changed
- **Parameter passing** - Migrated from environment variables to command-line arguments
- **Installation method** - Fully pipe-friendly with proper argument forwarding

### Security
- **RFC-compliant domain validation** - Rejects private networks (RFC 1918)
- **Input validation** - All entry points validate user input

---

## [0.1.0] - 2025-08-XX (Initial Release)

### Added
- Basic Xray installation and configuration
- Reality protocol support
- Systemd integration
- Basic logging framework
- Core utility functions (lib/core.sh)

[Unreleased]: https://github.com/xrf9268-hue/xray/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/xrf9268-hue/xray/releases/tag/v1.0.0
[0.9.0]: https://github.com/xrf9268-hue/xray/compare/v0.1.0...v0.9.0
[0.1.0]: https://github.com/xrf9268-hue/xray/releases/tag/v0.1.0
