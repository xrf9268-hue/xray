# Xray-Fusion

One-command Xray proxy deployment with automatic certificate management.

[![Tests](https://github.com/xrf9268-hue/xray/actions/workflows/test.yml/badge.svg)](https://github.com/xrf9268-hue/xray/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Quick Start

```bash
# Install (no domain required)
curl -sL https://raw.githubusercontent.com/xrf9268-hue/xray/main/install.sh | bash -s -- --topology reality-only

# View connection links
xrf links

# Check status
xrf status
```

That's it! Copy the link to your client app and connect.

## With Your Own Domain

If you have a domain with DNS pointing to your server:

```bash
curl -sL https://raw.githubusercontent.com/xrf9268-hue/xray/main/install.sh | bash -s -- \
  --topology vision-reality \
  --domain your.domain.com \
  --plugins cert-auto
```

## Commands

| Command | Description |
|---------|-------------|
| `xrf status` | Service status |
| `xrf links` | Connection links |
| `xrf logs` | View logs |
| `xrf health` | Health check |
| `xrf uninstall` | Remove installation |

## Uninstall

```bash
xrf uninstall
```

## Requirements

- Linux (Ubuntu/Debian/CentOS)
- systemd
- 64-bit architecture

## Documentation

| Document | Description |
|----------|-------------|
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |
| [docs/advanced.md](docs/advanced.md) | Advanced configuration |
| [docs/adr/](docs/adr/) | Architecture decisions |

## License

MIT
