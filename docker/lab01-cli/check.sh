#!/usr/bin/env bash
# Lab 01 — assertions non interactives (Linux / macOS / WSL / Git Bash).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NAMES=(hello web)

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

wait_http() {
  # $1=url $2=max seconds
  _url="$1"
  _max="${2:-30}"
  _deadline=$((SECONDS + _max))
  while [ "$SECONDS" -lt "$_deadline" ]; do
    if curl -fsS "$_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

command -v docker >/dev/null 2>&1 || fail "docker introuvable dans PATH"
command -v curl >/dev/null 2>&1 || fail "curl introuvable dans PATH"

docker info >/dev/null 2>&1 || fail "daemon Docker injoignable (Desktop non lance, ou utilisateur hors groupe docker)"
ok "docker info"

docker version >/dev/null
ok "docker version"

# ---------------------------------------------------------------------------
# hello-world
# ---------------------------------------------------------------------------
hello_out="$(docker run --name hello hello-world)"
echo "$hello_out" | grep -q "Hello from Docker" || fail "hello-world n'a pas affiche 'Hello from Docker'"
ok "docker run hello-world"

imgs="$(docker images hello-world)"
echo "$imgs" | grep -q hello-world || fail "docker images ne liste pas hello-world"
ok "docker images hello-world"

ps_a="$(docker ps -a --filter name=^hello$ --format '{{.Names}} {{.Status}}')"
echo "$ps_a" | grep -q hello || fail "docker ps -a devrait lister hello"
echo "$ps_a" | grep -q "Exited (0)" || fail "hello devrait etre Exited (0) (obtenu: $ps_a)"
ok "docker ps -a liste hello (Exited 0)"

docker rm hello >/dev/null
gone="$(docker ps -a --filter name=^hello$ --format '{{.Names}}')"
[ -z "$gone" ] || fail "hello aurait du disparaitre apres docker rm"
ok "docker rm hello"

# ---------------------------------------------------------------------------
# nginx publie sur 8080
# ---------------------------------------------------------------------------
docker run -d --name web -p 8080:80 nginx:1.27-alpine >/dev/null

status="$(docker inspect --format '{{.State.Status}}' web)"
[ "$status" = "running" ] || fail "web devrait etre running (obtenu: $status)"
ok "web est running"

image="$(docker inspect --format '{{.Config.Image}}' web)"
[ "$image" = "nginx:1.27-alpine" ] || fail "image web=nginx:1.27-alpine attendue (obtenu: $image)"
ok "inspect --format Image=nginx:1.27-alpine"

ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web)"
[ -n "$ip" ] || fail "inspect n'a pas renvoye d'adresse IP"
ok "inspect --format IPAddress=$ip"

wait_http "http://127.0.0.1:8080" 30 || fail "Nginx n'a pas repondu sur http://127.0.0.1:8080 en 30s"
page="$(curl -fsS http://127.0.0.1:8080)"
echo "$page" | grep -qi nginx || fail "la page 8080 devrait contenir nginx"
ok "curl http://127.0.0.1:8080 (Welcome to nginx)"

logs="$(docker logs web 2>&1)"
echo "$logs" | grep -q "start worker" || fail "docker logs web devrait contenir 'start worker'"
ok "docker logs web"

html="$(docker exec web cat /usr/share/nginx/html/index.html)"
echo "$html" | grep -qi nginx || fail "docker exec cat index.html inattendu"
ok "docker exec cat index.html"

docker exec web nginx -t >/dev/null 2>&1 || fail "docker exec web nginx -t a echoue"
ok "docker exec web nginx -t"

docker stop web >/dev/null
docker rm web >/dev/null
ok "docker stop + rm web"

ok "lab01-cli termine"
exit 0
