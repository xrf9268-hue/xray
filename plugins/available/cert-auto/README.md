# cert-auto Plugin

Automatic certificate management plugin based on Caddy for automatic TLS certificate issuance and renewal.

## Features

- Automatic Caddy installation
- Automatic TLS certificate configuration for domains
- Automatic certificate renewal
- Integration with vision-reality topology

## Usage

```bash
# Enable plugin and install vision-reality topology
./install.sh --topology vision-reality --domain your.domain.com --plugins cert-auto
```

## Configuration

- Domain (required): Specify via `--domain` parameter
- `XRAY_VISION_PORT`: Vision port (default 8443)

## How It Works

1. Install Caddy and configure automatic TLS
2. Caddy automatically requests Let's Encrypt certificates
3. Synchronize certificates to Xray certificate directory
4. Set up scheduled task for automatic renewal

## Requirements

- Domain must point to server IP
- Ports 80 and 443 must be available
- Server must have internet access
