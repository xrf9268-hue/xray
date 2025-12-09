# Xray-Fusion

A lightweight Xray management tool focused on simple and reliable deployment.

[![Tests](https://github.com/xrf9268-hue/xray/actions/workflows/test.yml/badge.svg)](https://github.com/xrf9268-hue/xray/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Why Xray-Fusion?

- **Production Ready**: 472 unit tests, ~80% coverage, comprehensive CI/CD
- **Security First**: RFC-compliant validation, systemd hardening, atomic operations
- **Zero Config**: One-line install with sensible defaults
- **Flexible**: Templates for common scenarios, plugin system for extensibility
- **Reliable**: Automatic backups, SHA256 verification, atomic restore
- **Well Documented**: ShellDoc API docs, troubleshooting guides, ADRs

## Quick Start

```bash
# Reality-only mode (no domain required)
curl -sL https://github.com/xrf9268-hue/xray/raw/main/install.sh | bash -s -- --topology reality-only

# Vision + Reality with auto certificates
curl -sL https://github.com/xrf9268-hue/xray/raw/main/install.sh | bash -s -- \
  --topology vision-reality --domain your.domain.com --plugins cert-auto
```

**Uninstall**:
```bash
curl -sL https://github.com/xrf9268-hue/xray/raw/main/uninstall.sh | bash
```

## Installation

### Using Templates

Pre-configured templates for common scenarios:

| Template | Topology | Use Case | Plugins |
|----------|----------|----------|---------|
| `home` | reality-only | Personal use, single device | - |
| `office` | vision-reality | Small team (5-20 users) | cert-auto, firewall |
| `server` | vision-reality | Production (50+ users) | cert-auto, firewall, monitoring |

```bash
# Deploy with template
curl -sL install.sh | bash -s -- --template home

# Template + custom domain
curl -sL install.sh | bash -s -- --template office --domain vpn.company.com
```

### Custom Installation

```bash
# Basic options
--topology reality-only|vision-reality  # Deployment mode (required)
--domain <domain>                       # Domain (required for vision-reality)
--version <version>                     # Xray version (default: latest)
--plugins <plugin1,plugin2>             # Comma-separated plugin list

# Advanced options
--template <template-id>                # Use predefined template
--uuid <uuid>                           # Custom UUID
--uuid-from-string <string>             # Generate UUID from string
--debug                                 # Enable debug logging
```

**Examples**:
```bash
# Reality-only with firewall
curl -sL install.sh | bash -s -- --topology reality-only --plugins firewall

# Vision-Reality with specific version
curl -sL install.sh | bash -s -- \
  --topology vision-reality \
  --domain example.com \
  --version v1.8.0 \
  --plugins cert-auto,firewall
```

### Manual Installation

```bash
# Clone repository
git clone https://github.com/xrf9268-hue/xray.git
cd xray-fusion

# Install
bin/xrf install --topology reality-only
```

## Usage

### Basic Commands

```bash
# Service status
bin/xrf status

# Connection links
bin/xrf links

# View logs
bin/xrf logs
bin/xrf logs --follow              # Real-time
bin/xrf logs --level error         # Filter by level
bin/xrf logs --since "1 hour ago"  # Time range

# Health check
bin/xrf health
```

### Backup & Restore

```bash
# Create backup
bin/xrf backup create
bin/xrf backup create --name pre-upgrade

# List backups
bin/xrf backup list

# Restore (automatically creates pre-restore backup)
bin/xrf backup restore <backup-name>

# Verify integrity (SHA256)
bin/xrf backup verify <backup-name>

# Delete old backups
bin/xrf backup delete <backup-name>
```

**Automatic Backups**: Installation automatically creates backups when upgrading existing installations.

### Plugin Management

```bash
# List plugins
bin/xrf plugin list

# Enable/disable
bin/xrf plugin enable cert-auto
bin/xrf plugin disable cert-auto

# Plugin info
bin/xrf plugin info cert-auto
```

**Available Plugins**:
- `cert-auto`: Automatic TLS certificates (Caddy + Let's Encrypt)
- `firewall`: Firewall port management
- `logrotate-obs`: Log rotation and observability
- `links-qr`: QR code generation for client links

## Client Requirements

### Recommended Client Version

Use Xray-core **v25.10.15 or later** for optimal compatibility. This version includes:
- **uTLS library fixes** for Chrome fingerprint simulation (critical for stability)
- Improved connection reliability
- Enhanced protocol support

### Download

- **Official Releases**: https://github.com/XTLS/Xray-core/releases/latest
- **Installation Guide**: https://xtls.github.io/en/document/install.html

### Version Check

```bash
xray version
```

### Compatibility

| Client Version | Status | Notes |
|----------------|--------|-------|
| v25.10.15+ | ✅ Recommended | Includes uTLS Chrome fingerprint fix |
| v25.9.5 - v25.10.14 | ⚠️ Use with caution | May have connection issues |
| v1.8.0 - v25.9.4 | ✅ Supported | Minimum required version |
| < v1.8.0 | ❌ Not supported | Please upgrade |

**Latest Tested**: v25.12.8 (2025-12-09)

### Troubleshooting Client Issues

If you experience connection problems:

1. **Check client version**: `xray version`
2. **Upgrade if outdated**: Download latest from [releases](https://github.com/XTLS/Xray-core/releases/latest)
3. **Verify configuration**: Ensure client config matches server-provided links
4. **Check logs**: `xray run -c config.json` to see detailed error messages

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Advanced Configuration

### Deployment Modes

**Reality-only**:
- No domain required
- SNI camouflage (default: `www.microsoft.com`)
- Port: 443
- Ideal for: Personal use

**Vision-Reality**:
- Domain ownership required
- Real TLS + Reality fallback
- Ports: 8443 (Vision), 443 (Reality)
- Ideal for: Teams, production

### Environment Variables

```bash
# Xray configuration
XRAY_SNI=www.microsoft.com       # Reality SNI (camouflage domain)
XRAY_VISION_PORT=8443            # Vision port (vision-reality mode)
XRAY_REALITY_PORT=443            # Reality port

# Caddy configuration (cert-auto plugin)
CADDY_HTTP_PORT=80               # HTTP port for ACME challenge
CADDY_HTTPS_PORT=8444            # HTTPS port (avoids Vision conflict)
```

### Port Allocation (vision-reality mode)

- **443**: Reality (recommended, follows official best practices)
- **8443**: Vision (real TLS)
- **8444**: Caddy HTTPS (certificate management)
- **8080**: Caddy fallback (handles non-proxy traffic)

## Development

### Testing

```bash
# Format code
make fmt

# Lint
make lint

# Run all tests
make test

# Unit tests only
make test-unit
```

**Test Framework**: [bats-core](https://github.com/bats-core/bats-core)
**Coverage**: ~80% (472 unit tests across 6 modules)

### CI/CD

GitHub Actions workflows:
- 🔍 ShellCheck static analysis
- 📐 shfmt format validation
- 🧪 Multi-version Ubuntu testing
- 🔒 Security scanning

## Documentation

- 📖 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- 📋 [CHANGELOG.md](CHANGELOG.md) - Version history
- 🏗️ [AGENTS.md](AGENTS.md) - Development standards and technical details
- 💡 [CLAUDE.md](CLAUDE.md) - Architecture Decision Records (ADRs)

## System Requirements

- Ubuntu/Debian/CentOS/RHEL
- systemd
- curl, unzip
- 64-bit architecture

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Project Philosophy**: Simple, reliable, production-ready. No unnecessary complexity, comprehensive testing, security-first design.
