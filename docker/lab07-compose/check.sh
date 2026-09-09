#!/usr/bin/env bash
# Lab 07 — assertions non interactives (Linux, macOS, WSL).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
cd "$ROOT"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

cleanup() {
  docker compose --profile debug down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
cp .env.example .env

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
. ./.env
set +a

[[ -n "${MYSQL_PASSWORD:-}" ]] || fail "MYSQL_PASSWORD absent après cp .env.example .env"

docker compose config >/dev/null || fail "docker compose config a échoué"
ok "docker compose config"

docker compose up -d --build

wait_mysql_healthy() {
  local i=0 cid h
  while [ "$i" -lt 90 ]; do
    cid="$(docker compose ps -q mysql 2>/dev/null || true)"
    if [ -n "$cid" ]; then
      h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null || true)"
      if [ "$h" = "healthy" ]; then
        return 0
      fi
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

wait_http_ok() {
  local i=0 body
  while [ "$i" -lt 90 ]; do
    body="$(curl -sS --max-time 5 http://127.0.0.1:8080 2>/dev/null || true)"
    if grep -F -q "Connexion MySQL réussie" <<<"$body"; then
      echo "$body"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

wait_mysql_healthy || fail "mysql n'est pas healthy en ≤90s"
ok "mysql est healthy"

body="$(wait_http_ok)" || fail "curl http://127.0.0.1:8080 ne contient pas « Connexion MySQL réussie » en ≤90s"
grep -F -q "Connexion MySQL réussie" <<<"$body" || fail "page d'accueil sans Connexion MySQL réussie"
ok "curl contient Connexion MySQL réussie"

logs_out="$(docker compose logs --no-color 2>&1 || true)"
[[ -n "$logs_out" ]] || fail "docker compose logs vide"
ok "docker compose logs"

dbs_out="$(docker compose exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" -N -e "SHOW DATABASES;"' </dev/null)" \
  || fail "mysql SHOW DATABASES a échoué"
grep -q appdb <<<"$dbs_out" || fail "la base appdb est absente"
ok "mysql SHOW DATABASES (appdb)"

docker compose exec -T mysql sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" -D appdb -e "CREATE TABLE IF NOT EXISTS lab_persist (id INT PRIMARY KEY); INSERT IGNORE INTO lab_persist VALUES (1);"' \
  </dev/null \
  || fail "CREATE TABLE lab_persist a échoué"
ok "table lab_persist créée"

docker compose down
docker compose up -d

wait_mysql_healthy || fail "mysql n'est pas healthy après down/up"
ok "mysql healthy après down/up (volume conservé)"

count_out="$(docker compose exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" -D appdb -N -e "SELECT COUNT(*) FROM lab_persist;"' </dev/null)" \
  || fail "SELECT lab_persist a échoué après down/up"
count="$(tr -d '[:space:]' <<<"$count_out")"
[[ "$count" == "1" ]] || fail "persistance attendue (COUNT=1), obtenu: $count"
ok "persistance: lab_persist survit à docker compose down"

body2="$(wait_http_ok)" || fail "curl après down/up sans « Connexion MySQL réussie »"
grep -F -q "Connexion MySQL réussie" <<<"$body2" || fail "page après down/up incorrecte"
ok "HTTP OK après down/up"

ok "lab07-compose terminé"
exit 0
