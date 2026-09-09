#!/usr/bin/env bash
# Détruit toutes les droplets taguées formation-docker (labs uniquement).
# Ne touche PAS aux pools Kubernetes ni aux autres VMs du compte.
# Usage : destroy-vms.sh [--yes]
set -euo pipefail

YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y|--force)
      YES=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage : destroy-vms.sh [--yes]

  Liste puis supprime toutes les droplets portant le tag formation-docker.
  Sans --yes, demande confirmation. Avec --yes (ou -y), suppression immédiate.

  Sécurité : les workers Kubernetes du compte (sans ce tag) ne sont pas visés.
EOF
      exit 0
      ;;
    *)
      echo "Option inconnue : $arg (attendu : --yes)" >&2
      exit 2
      ;;
  esac
done

command -v doctl >/dev/null || { echo "doctl n'est pas installé" >&2; exit 1; }
if ! doctl account get >/dev/null 2>&1; then
  echo "doctl n'est pas authentifié" >&2
  exit 1
fi

echo "Droplets avec le tag formation-docker :"
LIST="$(doctl compute droplet list --tag-name formation-docker --format ID,Name,PublicIPv4,Status,Region --no-header 2>/dev/null || true)"
if [[ -z "$(echo "$LIST" | sed '/^$/d')" ]]; then
  echo "(aucune)"
  exit 0
fi
echo "$LIST"
echo

COUNT="$(echo "$LIST" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$YES" -ne 1 ]]; then
  printf "Supprimer définitivement %s droplet(s) de formation ? Tapez 'oui' pour confirmer : " "$COUNT"
  read -r answer
  if [[ "$answer" != "oui" && "$answer" != "oui." && "$answer" != "y" && "$answer" != "yes" ]]; then
    echo "Annulé."
    exit 1
  fi
fi

# --tag-name + --force : uniquement les VMs de lab, jamais le reste du compte.
doctl compute droplet delete --tag-name formation-docker --force
echo "Suppression demandée pour ${COUNT} droplet(s) taguée(s) formation-docker."
