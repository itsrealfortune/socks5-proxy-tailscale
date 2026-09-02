# socks5-proxy-tailscale

A Dockerized Tailscale exit node that routes all tailnet TCP traffic through an upstream SOCKS5/HTTPS proxy.

## How it works

1. **Tailscale** joins your tailnet and advertises itself as an exit node.
2. **stunnel** establishes a TLS tunnel to the upstream proxy (for proxies that require HTTPS).
3. **redsocks** transparently redirects TCP connections into the TLS tunnel using iptables.
4. **iptables** captures all TCP traffic arriving on the `tailscale0` interface and redirects it to redsocks, excluding private/CGNAT ranges.

UDP traffic (except WireGuard port 41641) is dropped to prevent leaks outside the proxy.

## Quick start

```bash
cp .env.example .env
# Edit .env with your Tailscale auth key and proxy details
docker compose up -d
```

## Configuration

Copy `.env.example` to `.env` and fill in the values:

| Variable | Description |
|---|---|
| `TS_AUTHKEY` | Tailscale auth key ([generate one here](https://login.tailscale.com/admin/settings/keys)) |
| `UPSTREAM_PROXY_HOST` | Hostname or IP of the upstream SOCKS5/HTTPS proxy |
| `UPSTREAM_PROXY_PORT` | Port of the upstream proxy |
| `UPSTREAM_PROXY_USER` | Proxy authentication username |
| `UPSTREAM_PROXY_PASS` | Proxy authentication password |

## Usage

Once running, go to your [Tailscale admin console](https://login.tailscale.com/admin/machines) and approve the exit node. Then other devices on your tailnet can route traffic through it by enabling the exit node in their Tailscale settings.

## Requirements

- Docker and Docker Compose
- A Tailscale auth key
- An upstream SOCKS5 or HTTP-CONNECT proxy with TLS support

## License

MIT with Attribution and Integrity Clause - see [LICENSE](LICENSE) for details.
