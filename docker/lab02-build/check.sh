#!/usr/bin/env bash
# Lab 02 — assertions non interactives (Linux / macOS / WSL / Git Bash).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NAMES=(flask-bad flask-good registry)
IMAGES=(
  flask-bad:1.0.0
  flask-good:1.0.0
  localhost:5005/flask-good:1.0.0
)

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
  docker rmi "${IMAGES[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

wait_http() {
  _url="$1"
  _max="${2:-60}"
  _deadline=$((SECONDS + _max))
  while [ "$SECONDS" -lt "$_deadline" ]; do
    if curl -fsS "$_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_healthy() {
  _name="$1"
  _max="${2:-45}"
  _deadline=$((SECONDS + _max))
  while [ "$SECONDS" -lt "$_deadline" ]; do
    _s="$(docker inspect --format '{{.State.Health.Status}}' "$_name" 2>/dev/null || echo starting)"
    case "$_s" in
      healthy) return 0 ;;
      unhealthy) return 1 ;;
    esac
    sleep 1
  done
  return 1
}

command -v docker >/dev/null 2>&1 || fail "docker introuvable dans PATH"
command -v curl >/dev/null 2>&1 || fail "curl introuvable dans PATH"
docker info >/dev/null 2>&1 || fail "daemon Docker injoignable"

# ---------------------------------------------------------------------------
# Builds
# ---------------------------------------------------------------------------
docker build -t flask-bad:1.0.0 bad/
ok "docker build flask-bad:1.0.0"

docker build -t flask-good:1.0.0 .
ok "docker build flask-good:1.0.0"

bad_size="$(docker image inspect flask-bad:1.0.0 --format '{{.Size}}')"
good_size="$(docker image inspect flask-good:1.0.0 --format '{{.Size}}')"
[ "$good_size" -lt "$bad_size" ] || fail "flask-good ($good_size) devrait etre plus petite que flask-bad ($bad_size)"
ok "taille flask-good ($good_size) < flask-bad ($bad_size)"

hist_bad="$(docker history flask-bad:1.0.0)"
echo "$hist_bad" | grep -qi python || fail "docker history flask-bad inattendu"
ok "docker history flask-bad:1.0.0"

hist_good="$(docker history flask-good:1.0.0)"
echo "$hist_good" | grep -qi HEALTHCHECK || fail "docker history flask-good devrait montrer HEALTHCHECK"
ok "docker history flask-good:1.0.0 (HEALTHCHECK)"

# ---------------------------------------------------------------------------
# Run + HTTP
# ---------------------------------------------------------------------------
docker run -d --name flask-bad -p 5001:5000 flask-bad:1.0.0 >/dev/null
docker run -d --name flask-good -p 5002:5000 flask-good:1.0.0 >/dev/null

wait_http "http://127.0.0.1:5001/" 60 || fail "flask-bad n'a pas repondu sur :5001"
wait_http "http://127.0.0.1:5002/" 60 || fail "flask-good n'a pas repondu sur :5002"

bad_page="$(curl -fsS http://127.0.0.1:5001/)"
echo "$bad_page" | grep -q "Hello from Docker" || fail "reponse flask-bad inattendue: $bad_page"
ok "curl flask-bad :5001"

good_page="$(curl -fsS http://127.0.0.1:5002/)"
echo "$good_page" | grep -q "Hello from Docker" || fail "reponse flask-good inattendue: $good_page"
ok "curl flask-good :5002"

health_page="$(curl -fsS http://127.0.0.1:5002/health)"
echo "$health_page" | grep -q ok || fail "/health devrait renvoyer ok"
ok "curl flask-good /health"

bad_uid="$(docker exec flask-bad id -u)"
[ "$bad_uid" = "0" ] || fail "flask-bad devrait tourner en root (uid=0), obtenu: $bad_uid"
ok "flask-bad uid=0 (root)"

good_uid="$(docker exec flask-good id -u)"
[ "$good_uid" = "1000" ] || fail "flask-good devrait tourner uid=1000, obtenu: $good_uid"
ok "flask-good uid=1000 (non-root)"

wait_healthy flask-good 45 || fail "flask-good n'est pas healthy (status=$(docker inspect --format '{{.State.Health.Status}}' flask-good 2>/dev/null || echo unknown))"
ok "HEALTHCHECK flask-good = healthy"

# secrets copies dans l'image mauvaise
docker exec flask-bad test -f /app/secrets.env || fail "bad/secrets.env devrait etre dans l'image flask-bad (COPY .)"
ok "COPY . a embarque secrets.env dans flask-bad"

# ---------------------------------------------------------------------------
# Registre local :5005
# ---------------------------------------------------------------------------
docker rm -f flask-good >/dev/null 2>&1 || true

docker run -d --name registry -p 5005:5000 registry:2 >/dev/null
wait_http "http://127.0.0.1:5005/v2/" 30 || fail "registry:2 n'a pas repondu sur :5005/v2/"
ok "registry:2 ecoute sur 5005"

docker tag flask-good:1.0.0 localhost:5005/flask-good:1.0.0
docker push localhost:5005/flask-good:1.0.0 >/dev/null
ok "docker push localhost:5005/flask-good:1.0.0"

catalog="$(curl -fsS http://127.0.0.1:5005/v2/_catalog)"
echo "$catalog" | grep -q flask-good || fail "catalogue registre inattendu: $catalog"
ok "GET /v2/_catalog contient flask-good"

docker rmi flask-good:1.0.0 localhost:5005/flask-good:1.0.0 >/dev/null
docker pull localhost:5005/flask-good:1.0.0 >/dev/null
pulled="$(docker images localhost:5005/flask-good:1.0.0 --format '{{.Repository}}:{{.Tag}}')"
echo "$pulled" | grep -q "localhost:5005/flask-good:1.0.0" || fail "pull registre n'a pas restaure l'image"
ok "docker rmi puis pull localhost:5005/flask-good:1.0.0"

ok "lab02-build termine"
exit 0
