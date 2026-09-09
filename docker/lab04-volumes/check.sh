#!/usr/bin/env bash
# Lab 04 — volumes : named volume, bind mount, tmpfs, --mount (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

PGPASS="${PGPASS:-ChangeMe-lab}"
NAMES=(db db2 web-bind web-mount)
VOLUME=db-data

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

[[ -f html/index.html ]] || fail "html/index.html manquant dans le lab"

for img in postgres:16 nginx:1.27-alpine alpine:3.20; do
  docker pull "$img" >/dev/null
done
ok "images pinnees pull (postgres:16 nginx:1.27-alpine alpine:3.20)"

# ---------------------------------------------------------------------------
# 1. Volume nommé + Postgres 16 + persistance via db2
# ---------------------------------------------------------------------------
docker volume create "$VOLUME" >/dev/null
docker volume ls --format '{{.Name}}' | grep -qx "$VOLUME" || fail "volume $VOLUME absent de docker volume ls"
ok "volume $VOLUME cree"

mp="$(docker volume inspect --format '{{.Mountpoint}}' "$VOLUME")"
[[ -n "$mp" ]] || fail "Mountpoint vide pour $VOLUME"
ok "docker volume inspect Mountpoint=$mp"

docker run -d --name db \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_PASSWORD="$PGPASS" \
  postgres:16 >/dev/null

wait_pg() {
  local name="$1"
  local deadline=$((SECONDS + 90))
  while (( SECONDS < deadline )); do
    if docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; then
      return 0
    fi
    running="$(docker inspect --format '{{.State.Running}}' "$name" 2>/dev/null || echo false)"
    if [[ "$running" != "true" ]]; then
      docker logs "$name" >&2 || true
      fail "conteneur $name n'est plus running pendant l'attente pg_isready"
    fi
    sleep 1
  done
  docker logs "$name" >&2 || true
  fail "postgres ($name) n'accepte pas les connexions en 90s"
}

wait_pg db
ok "db pg_isready"

docker exec db psql -U postgres -c "CREATE DATABASE formation;" >/dev/null
docker exec db psql -U postgres -d formation -c \
  "CREATE TABLE notes (id serial PRIMARY KEY, message text NOT NULL);" >/dev/null
docker exec db psql -U postgres -d formation -c \
  "INSERT INTO notes (message) VALUES ('bonjour-volume');" >/dev/null
row="$(docker exec db psql -U postgres -d formation -tAc "SELECT message FROM notes;")"
[[ "$row" == "bonjour-volume" ]] || fail "ligne initiale inattendue: [$row]"
ok "base formation + table notes + ligne bonjour-volume"

docker rm -f db >/dev/null

docker run -d --name db2 \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_PASSWORD="$PGPASS" \
  postgres:16 >/dev/null

wait_pg db2
row2="$(docker exec db2 psql -U postgres -d formation -tAc "SELECT message FROM notes;")"
[[ "$row2" == "bonjour-volume" ]] || fail "persistance cassee apres rm -f db (obtenu: [$row2])"
ok "db2 retrouve bonjour-volume sur le volume $VOLUME"

pgver="$(docker run --rm \
  --mount "type=volume,src=${VOLUME},dst=/data" \
  alpine:3.20 cat /data/PG_VERSION)"
[[ "$pgver" == "16" ]] || fail "PG_VERSION attendu 16 (obtenu: $pgver)"
ok "--mount type=volume : PG_VERSION=16"

# ---------------------------------------------------------------------------
# 2. Bind mount Nginx (sans publier de port hôte : evite les collisions)
# ---------------------------------------------------------------------------
docker run -d --name web-bind \
  -v "$(pwd)/html:/usr/share/nginx/html:ro" \
  nginx:1.27-alpine >/dev/null

html_deadline=$((SECONDS + 30))
page=""
while (( SECONDS < html_deadline )); do
  running="$(docker inspect --format '{{.State.Running}}' web-bind 2>/dev/null || echo false)"
  [[ "$running" == "true" ]] || fail "web-bind n'est plus running"
  if page="$(docker exec web-bind cat /usr/share/nginx/html/index.html 2>/dev/null)"; then
    break
  fi
  sleep 1
done
echo "$page" | grep -q "Hello depuis un bind mount" \
  || fail "bind mount nginx : page inattendue"
ok "bind mount $(pwd)/html -> nginx (page lab)"

if docker exec web-bind touch /usr/share/nginx/html/interdit.txt >/dev/null 2>&1; then
  fail "le bind :ro aurait du refuser l'ecriture"
fi
ok "bind mount :ro refuse l'ecriture"

# ---------------------------------------------------------------------------
# 3. tmpfs
# ---------------------------------------------------------------------------
tmpfs_out="$(docker run --rm --tmpfs /scratch alpine:3.20 \
  sh -c 'echo volatile > /scratch/x && cat /scratch/x && mount | grep /scratch')"
echo "$tmpfs_out" | grep -q volatile || fail "tmpfs : fichier /scratch/x illisible"
echo "$tmpfs_out" | grep -q tmpfs || fail "tmpfs : mount ne montre pas tmpfs sur /scratch"
ok "--tmpfs /scratch (ecriture volatile)"

ok "lab04-volumes termine"
exit 0
