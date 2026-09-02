# 🧅 socks5-proxy-tailscale

> A Dockerized **Tailscale exit node** that transparently routes all tailnet TCP traffic through an upstream SOCKS5 / HTTPS proxy.

[![Docker](https://img.shields.io/badge/Docker-compose-2496ED.svg?logo=docker&logoColor=white)](https://www.docker.com/)
[![Tailscale](https://img.shields.io/badge/Tailscale-exit%20node-000000.svg?logo=tailscale&logoColor=white)](https://tailscale.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-bash-4EAA25.svg?logo=gnubash&logoColor=white)](entrypoint.sh)

> [!NOTE]
> **Not affiliated with, endorsed by, or sponsored by Tailscale Inc. or any upstream proxy provider.** "Tailscale" is a trademark of Tailscale Inc. This is an independent, community project that uses Tailscale's public products.

---

## 🚀 Quick start

```bash
# 1. Configure your environment
cp .env.example .env

# 2. Fill in your Tailscale auth key + proxy credentials
$EDITOR .env

# 3. Build and launch
docker compose up -d
```

That's it. Once the container boots, approve the exit node from the [Tailscale admin console](https://login.tailscale.com/admin/machines), then point any tailnet device at it via its Tailscale settings.

---

## 🧠 How it works

```
                  ┌───────────────────────────────────────────────────────┐
                  │                    YOUR DEVICE                         │
                  │              (any node on the tailnet)                 │
                  └──────────────────────────┬────────────────────────────┘
                                             │ tailnet / WireGuard
                                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                              exit-node container                         │
│                                                                          │
│   tailscale0 ──► iptables ──► redsocks ──► stunnel ──► upstream proxy    │
│   (tailnet TCP)   REDSOCKS     transparent   TLS      (SOCKS5/HTTPS)     │
│                  chain         redirect      tunnel                      │
└──────────────────────────────────────────────────────────────────────────┘
                  │
                  ▼
           the public internet
```

At a glance:

| Layer | Tool | Role |
|-------|------|------|
| **1** | Tailscale | Joins the tailnet, advertises itself as an exit node |
| **2** | stunnel | Opens a TLS tunnel to the upstream proxy (required when the proxy only speaks HTTPS) |
| **3** | redsocks | Transparently converts TCP connections into SOCKS5/HTTP-CONNECT requests |
| **4** | iptables | Captures all TCP arriving on `tailscale0` and redirects it to redsocks |

> [!IMPORTANT]
> **UDP handling.** All outbound UDP (except WireGuard's own port `41641`) is **dropped** to prevent traffic from leaking outside the proxy. This project routes TCP only.

---

## ⚙️ Configuration

Copy `.env.example` to `.env` and fill in the values:

| Variable | Required | Default | Description |
|----------|:--------:|---------|-------------|
| `TS_AUTHKEY` | ✅ | — | Tailscale auth key. [Generate one here](https://login.tailscale.com/admin/settings/keys) |
| `UPSTREAM_PROXY_HOST` | ✅ | — | Hostname or IP of the upstream SOCKS5 / HTTPS proxy |
| `UPSTREAM_PROXY_PORT` | ✅ | — | TCP port of the upstream proxy |
| `UPSTREAM_PROXY_USER` | ✅ | — | Proxy authentication username |
| `UPSTREAM_PROXY_PASS` | ✅ | — | Proxy authentication password |

<details>
<summary>🧬 Optional: extra Tailscale flags via <code>TS_EXTRA_ARGS</code></summary>

Set the `TS_EXTRA_ARGS` environment variable in `docker-compose.yml` (or an entry in `.env`) to pass additional arguments to `tailscale up`, e.g.:

```yaml
environment:
  - TS_EXTRA_ARGS=--advertise-routes=192.168.1.0/24
```

</details>

---

## 🏗️ Architecture reference

<details>
<summary>Component breakdown</summary>

**`Dockerfile`** - Debian `bookworm-slim` base with:

- `tailscaled` / `tailscale` (installed from the official Tailscale apt repo)
- `redsocks`, `stunnel4` for proxying
- `iptables`, `iproute2` for traffic redirection

**`entrypoint.sh`** - Startup order:

1. Generates the redsocks config from environment variables
2. Boots `tailscaled` and waits for the socket
3. Runs `tailscale up --advertise-exit-node`
4. Writes and starts a TLS `stunnel` tunnel to the upstream proxy
5. Launches `redsocks`
6. Installs the `REDSOCKS` iptables NAT chain and forwards `tailscale0` TCP into it
7. Drops non-WireGuard UDP to avoid leaks

**`docker-compose.yml`** - Requires `NET_ADMIN` capability and a `/dev/net/tun` device, enables IPv4/IPv6 forwarding, and persists Tailscale state in `./data`.

**`redsocks.conf.template`** - Placeholder config consumed by the entrypoint via `sed`.

</details>

---

## 🐛 Troubleshooting

<details>
<summary>Common issues</summary>

**Traffic isn't being proxied**
Verify the exit node is approved in the admin console, and that the client device has "Use exit node" enabled.

**`cannot open TUN/TAP device`**
The container needs the `/dev/net/tun` device and the `NET_ADMIN` capability. Confirm your `docker-compose.yml` includes both.

**TLS handshake fails with the upstream proxy**
Double-check `UPSTREAM_PROXY_HOST` and `UPSTREAM_PROXY_PORT`, and that the proxy actually supports HTTPS/TLS on that port.

**My device leaks IP on UDP**
This is expected and by design. UDP (outside WireGuard) is intentionally dropped; the proxy layer only handles TCP.

</details>

---

## ✅ Roadmap

- [x] Transparent TCP routing via redsocks
- [x] TLS tunnel for HTTPS-only proxies
- [ ] IPv6 proxying support
- [ ] UDP proxying via `udp2raw` / TUN-UDP

---

## 🛡️ Security notes

- **The `.env` file contains secrets** (your Tailscale auth key and proxy credentials). It is git-ignored - never commit it.
- Prefer ephemeral, scoped auth keys from Tailscale rather than reusable ones.
- Treat your proxy credentials with the same care as any other password.

---

## 📜 License

MIT with **Attribution and Integrity Clause** - see [LICENSE](LICENSE) for details.

> [!NOTE]
> **Not affiliated with Tailscale Inc.** "Tailscale" is a registered trademark of Tailscale Inc. This project is an independent implementation and is not sponsored, endorsed, or associated with Tailscale Inc. or any upstream proxy provider.
