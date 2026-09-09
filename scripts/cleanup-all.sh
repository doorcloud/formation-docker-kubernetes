#!/usr/bin/env bash
# Nettoyage ciblé des ressources créées par les labs Docker.
# Ne jamais exécuter « docker system prune -a » : cela supprimerait
# des images et volumes hors formation.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

echo "Arrêt / suppression des conteneurs de lab…"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  docker rm -f "$name" >/dev/null 2>&1 || true
done <<'EOF'
web
hello
bad
good
flask-bad
flask-good
lab-registry
registry
redis
client
lab03-host
db
db2
web-bind
web-mount
test-web
crash-test
mem-leak
crash-restart
ns-a
ns-b
ns-host
c-limits
secure
EOF

echo "Suppression des réseaux de lab…"
docker network rm app-net isolated-net >/dev/null 2>&1 || true

echo "Suppression du volume db-data…"
docker volume rm db-data >/dev/null 2>&1 || true

compose="docker/lab07-compose/docker-compose.yml"
if [ -f "$compose" ]; then
  echo "docker compose down (lab07)…"
  docker compose -f "$compose" --profile debug down -v --remove-orphans >/dev/null 2>&1 || true
fi

# Volumes anonymes laissés par postgres/mysql (VOLUME dans l'image) une fois les conteneurs supprimés.
echo "Suppression des volumes anonymes orphelins…"
docker volume ls -q --filter dangling=true --filter label=com.docker.volume.anonymous \
  | xargs docker volume rm >/dev/null 2>&1 || true

echo "Nettoyage ciblé terminé (pas de prune global)."
exit 0
