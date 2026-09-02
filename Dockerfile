FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl gnupg ca-certificates iptables iproute2 redsocks stunnel4 socat \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
       -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
       -o /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

COPY redsocks.conf.template /etc/redsocks.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
