#!/usr/bin/env bash
# Supprime uniquement les namespaces dont le nom correspond à ^lab- .
# Liste d'abord, demande confirmation sauf --yes / -y.
# Ne touche jamais default ni kube-* (filtre ^lab- + garde-fous).
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/k8s-cleanup-all.sh [--yes|-y]

Liste les namespaces Kubernetes dont le nom commence par « lab- »,
puis les supprime après confirmation.

  --yes, -y   ne pas demander confirmation (CI / non interactif)

Ne supprime jamais default, kube-system, kube-public, kube-node-lease
ni tout nom commençant par kube-.
EOF
}

yes=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue : $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl introuvable dans PATH." >&2
  exit 1
fi

# Liste brute ; awk filtre ^lab- (POSIX).
ns_raw="$(kubectl get ns --request-timeout=30s -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
if [ -z "$ns_raw" ]; then
  echo "Impossible de lister les namespaces (cluster injoignable ?)." >&2
  exit 1
fi

to_delete=()
while IFS= read -r ns; do
  [ -n "$ns" ] || continue
  case "$ns" in
    default|kube-system|kube-public|kube-node-lease)
      continue
      ;;
    kube-*)
      continue
      ;;
    lab-*)
      to_delete+=("$ns")
      ;;
    *)
      continue
      ;;
  esac
done <<EOF
$(printf '%s\n' "$ns_raw" | awk '/^lab-/ { print }')
EOF

if [ "${#to_delete[@]}" -eq 0 ]; then
  echo "Aucun namespace « lab-* » à supprimer."
  exit 0
fi

echo "Namespaces candidats (motif ^lab-) :"
i=0
while [ "$i" -lt "${#to_delete[@]}" ]; do
  echo "  - ${to_delete[$i]}"
  i=$((i + 1))
done

if [ "$yes" -ne 1 ]; then
  if [ ! -t 0 ]; then
    echo "stdin non interactif : relancez avec --yes pour confirmer." >&2
    exit 1
  fi
  printf 'Supprimer ces %s namespace(s) ? [y/N] ' "${#to_delete[@]}"
  read -r reply
  case "$reply" in
    y|Y|yes|YES|oui|OUI) ;;
    *)
      echo "Annulé."
      exit 0
      ;;
  esac
fi

i=0
while [ "$i" -lt "${#to_delete[@]}" ]; do
  ns="${to_delete[$i]}"
  case "$ns" in
    lab-*)
      echo "Suppression de ${ns}…"
      kubectl delete ns "$ns" --wait=false --request-timeout=30s || true
      ;;
    *)
      echo "IGNORE (garde-fou) : $ns"
      ;;
  esac
  i=$((i + 1))
done

echo "Demandes de suppression envoyées (--wait=false)."
exit 0
