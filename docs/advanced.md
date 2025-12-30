# Advanced Configuration

## Installation Options

```bash
--topology reality-only|vision-reality  # Deployment mode (required)
--domain <domain>                       # Domain (required for vision-reality)
--version <version>                     # Xray version (default: latest)
--plugins <plugin1,plugin2>             # Comma-separated plugin list
--template <template-id>                # Use predefined template
--uuid <uuid>                           # Custom UUID
--debug                                 # Enable debug logging
```

## Templates

| Template | Topology | Use Case |
|----------|----------|----------|
| `home` | reality-only | Personal use |
| `office` | vision-reality | Small team (5-20 users) |
| `server` | vision-reality | Production (50+ users) |

```bash
curl -sL install.sh | bash -s -- --template office --domain vpn.company.com
```

## Deployment Modes

### Reality-only
- No domain required
- SNI camouflage (default: `www.microsoft.com`)
- Port: 443

### Vision-Reality
- Domain ownership required
- Real TLS + Reality fallback
- Ports: 8443 (Vision), 443 (Reality)

## Plugins

| Plugin | Description |
|--------|-------------|
| `cert-auto` | Automatic TLS certificates via Caddy |
| `firewall` | Firewall port management |
| `logrotate-obs` | Log rotation |
| `links-qr` | QR code for client links |

```bash
xrf plugin list
xrf plugin enable cert-auto
xrf plugin info cert-auto
```

## Backup & Restore

```bash
xrf backup create
xrf backup create --name pre-upgrade
xrf backup list
xrf backup restore <name>
xrf backup verify <name>
```

## Environment Variables

```bash
XRAY_SNI=www.microsoft.com    # Reality SNI
XRAY_VISION_PORT=8443         # Vision port
XRAY_REALITY_PORT=443         # Reality port
CADDY_HTTP_PORT=80            # ACME challenge
CADDY_HTTPS_PORT=8444         # Caddy HTTPS
```

## Port Allocation (vision-reality)

| Port | Service |
|------|---------|
| 443 | Reality |
| 8443 | Vision |
| 8444 | Caddy HTTPS |
| 8080 | Caddy fallback |

## Client Requirements

**Recommended**: Xray-core v25.10.15+ (includes uTLS fix)

| Version | Status |
|---------|--------|
| v25.10.15+ | ✅ Recommended |
| v1.8.0 - v25.10.14 | ✅ Supported |
| < v1.8.0 | ❌ Not supported |

## Development

```bash
make fmt        # Format
make lint       # Lint
make test-unit  # Test
```
