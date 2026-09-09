#!/usr/bin/env bash
# Télécharge les images figées utilisées par les labs.
# À lancer la veille, sur une connexion personnelle (Wi-Fi hors salle),
# après « docker login » : Docker Hub limite les pulls anonymes
# (10 / h / IP) et la salle sort souvent par une seule IP NAT.
set -uo pipefail

fail=0
pulled=0

echo "Pré-téléchargement des images de formation…"
echo "Conseil : docker login (compte Hub gratuit) avant de lancer ce script."
echo

while IFS= read -r img; do
  [ -n "$img" ] || continue
  echo "=== docker pull ${img} ==="
  if docker pull "$img"; then
    pulled=$((pulled + 1))
  else
    echo "ECHEC: ${img}"
    fail=$((fail + 1))
  fi
done <<'EOF'
hello-world
nginx:1.27-alpine
alpine:3.20
redis:7-alpine
postgres:16
busybox:1.36
python:3.12-slim
python:3.12
mysql:8.4
php:8.3-fpm
registry:2
EOF

echo
echo "OK=${pulled}  ECHEC=${fail}"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
