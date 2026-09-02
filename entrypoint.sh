#!/bin/bash
set -e

update-alternatives --set iptables /usr/sbin/iptables-nft >/dev/null 2>&1 || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft >/dev/null 2>&1 || true
mkdir -p /var/lib/tailscale /var/run/tailscale

# --- Génère la config redsocks à partir des variables d'env ---
sed -e "s/__UPSTREAM_PROXY_HOST__/${UPSTREAM_PROXY_HOST}/" \
    -e "s/__UPSTREAM_PROXY_PORT__/${UPSTREAM_PROXY_PORT}/" \
    -e "s/__UPSTREAM_PROXY_USER__/${UPSTREAM_PROXY_USER}/" \
    -e "s/__UPSTREAM_PROXY_PASS__/${UPSTREAM_PROXY_PASS}/" \
    /etc/redsocks.conf.template > /etc/redsocks.conf

# --- Démarre Tailscale ---
tailscaled --state=/var/lib/tailscale/tailscaled.state \
           --socket=/var/run/tailscale/tailscaled.sock &

until tailscale --socket=/var/run/tailscale/tailscaled.sock status >/dev/null 2>&1; do
  sleep 0.5
done

tailscale --socket=/var/run/tailscale/tailscaled.sock up \
  --authkey="${TS_AUTHKEY}" \
  --hostname="${TS_HOSTNAME:-proxy-exit-node}" \
  --advertise-exit-node \
  ${TS_EXTRA_ARGS}

# --- Tunnel TLS vers le proxy amont (le proxy exige HTTPS) ---
cat > /etc/stunnel.conf <<STUNNEL_EOF
foreground = yes
syslog = no
pid = /var/run/stunnel.pid
[proxy-tls]
client = yes
accept = 127.0.0.1:8888
connect = ${UPSTREAM_PROXY_HOST}:${UPSTREAM_PROXY_PORT}
verifyChain = yes
CAfile = /etc/ssl/certs/ca-certificates.crt
checkHost = ${UPSTREAM_PROXY_HOST}
STUNNEL_EOF
stunnel4 /etc/stunnel.conf &
sleep 1

# --- Génère la config redsocks vers le tunnel local ---
cat > /etc/redsocks.conf <<REDSOCKS_EOF
base {
    log_debug = off;
    log_info = on;
    log = stderr;
    daemon = off;
    redirector = iptables;
}
redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 8888;
    type = http-connect;
    login = "${UPSTREAM_PROXY_USER}";
    password = "${UPSTREAM_PROXY_PASS}";
}
REDSOCKS_EOF

# --- Démarre redsocks en arrière-plan ---
redsocks -c /etc/redsocks.conf &
sleep 1

# --- iptables : redirige tout le TCP entrant depuis tailscale0 vers redsocks ---
iptables -t nat -N REDSOCKS
iptables -t nat -A REDSOCKS -d 0.0.0.0/8      -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8     -j RETURN
iptables -t nat -A REDSOCKS -d 100.64.0.0/10  -j RETURN   # plage CGNAT Tailscale, NE PAS rediriger
iptables -t nat -A REDSOCKS -d 127.0.0.0/8    -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12  -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4    -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4    -j RETURN
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

iptables -t nat -A PREROUTING -i tailscale0 -p tcp -j REDSOCKS

# --- Bloque l'UDP sortant du tailnet pour éviter une fuite hors-proxy ---
iptables -A FORWARD -i tailscale0 -p udp ! --dport 41641 -j DROP

echo "Exit node prêt : tout le TCP du tailnet est routé via ${UPSTREAM_PROXY_HOST}:${UPSTREAM_PROXY_PORT}"
wait
