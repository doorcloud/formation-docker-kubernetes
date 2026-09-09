#!/usr/bin/env bash
# Lab 03 — assertions non interactives (Linux / macOS / WSL / Git Bash).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NAMES=(redis client lab03-host)
NETS=(app-net isolated-net)

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
  docker network rm "${NETS[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

wait_pong() {
  _max="${1:-20}"
  _deadline=$((SECONDS + _max))
  _pong=""
  while [ "$SECONDS" -lt "$_deadline" ]; do
    _pong="$(docker run --rm --network app-net redis:7-alpine redis-cli -h redis -t 5 ping 2>/dev/null || true)"
    if [ "$_pong" = "PONG" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

command -v docker >/dev/null 2>&1 || fail "docker introuvable dans PATH"
docker info >/dev/null 2>&1 || fail "daemon Docker injoignable"

# ---------------------------------------------------------------------------
# Reseaux
# ---------------------------------------------------------------------------
ls_out="$(docker network ls)"
echo "$ls_out" | grep -qw bridge || fail "docker network ls devrait lister bridge"
echo "$ls_out" | grep -qw host || fail "docker network ls devrait lister host"
echo "$ls_out" | grep -qw none || fail "docker network ls devrait lister none"
ok "docker network ls (bridge, host, none)"

docker network create app-net >/dev/null
docker network create isolated-net >/dev/null
ok "docker network create app-net + isolated-net"

subnet_app="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' app-net)"
subnet_iso="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' isolated-net)"
[ -n "$subnet_app" ] || fail "subnet app-net vide"
[ -n "$subnet_iso" ] || fail "subnet isolated-net vide"
[ "$subnet_app" != "$subnet_iso" ] || fail "app-net et isolated-net ont le meme subnet ($subnet_app)"
ok "inspect subnets app-net=$subnet_app isolated-net=$subnet_iso"

# ---------------------------------------------------------------------------
# Redis + DNS
# ---------------------------------------------------------------------------
docker run -d --name redis --network app-net redis:7-alpine >/dev/null

wait_pong 20 || fail "redis-cli -h redis ping n'a pas renvoye PONG depuis app-net"
ok "redis-cli -h redis ping = PONG (app-net)"

if docker run --rm --network isolated-net redis:7-alpine redis-cli -h redis -t 3 ping >/dev/null 2>&1; then
  fail "redis n'aurait pas du etre joignable depuis isolated-net"
fi
ok "redis injoignable depuis isolated-net"

# ---------------------------------------------------------------------------
# network connect
# ---------------------------------------------------------------------------
docker run -d --name client --network isolated-net redis:7-alpine sleep 300 >/dev/null

if docker exec client redis-cli -h redis -t 3 ping >/dev/null 2>&1; then
  fail "client sur isolated-net n'aurait pas du resoudre redis"
fi
ok "client isolated-net : redis-cli echoue"

docker network connect app-net client
connect_pong="$(docker exec client redis-cli -h redis -t 5 ping)"
[ "$connect_pong" = "PONG" ] || fail "apres network connect, PONG attendu (obtenu: $connect_pong)"
ok "docker network connect app-net : PONG"

nets="$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' client)"
echo "$nets" | grep -q app-net || fail "client devrait etre sur app-net (obtenu: $nets)"
echo "$nets" | grep -q isolated-net || fail "client devrait rester sur isolated-net (obtenu: $nets)"
ok "client connecte a app-net et isolated-net"

# ---------------------------------------------------------------------------
# host + none
# ---------------------------------------------------------------------------
docker run -d --name lab03-host --network host alpine:3.20 sleep 30 >/dev/null
mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' lab03-host)"
[ "$mode" = "host" ] || fail "NetworkMode=host attendu (obtenu: $mode)"
ok "NetworkMode=host"

ifaces="$(docker run --rm --network none alpine:3.20 ls /sys/class/net)"
echo "$ifaces" | grep -qx lo || fail "network none devrait exposer lo (obtenu: $ifaces)"
echo "$ifaces" | grep -qx eth0 && fail "network none ne devrait pas exposer eth0"
ok "network none : uniquement lo"

ok "lab03-networking termine"
exit 0
