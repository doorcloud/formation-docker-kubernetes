#!/usr/bin/env bash
# Exécute chaque kubernetes/lab*/check.sh (sauf lab01, manuel) et affiche
# un tableau PASS/FAIL. NS unique par lab. Respecte KUBECONFIG.
# Portable macOS (bash 3.2) : pas de timeout(1), pas d'options GNU de date.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0
fail=0
skip=0
lab_names=()
lab_results=()

if command -v kubectl >/dev/null 2>&1; then
  echo "Contexte kubectl : $(kubectl config current-context 2>/dev/null || echo '(aucun)')"
else
  echo "kubectl introuvable dans PATH (les check.sh échoueront)."
fi

found=0
for check in kubernetes/lab*/check.sh; do
  if [ ! -f "$check" ]; then
    continue
  fi
  lab="$(basename "$(dirname "$check")")"

  case "$lab" in
    lab01-*)
      echo
      echo "======== ${lab} ========"
      echo "SKIP: ${lab} (manuel — console Door / kubeconfig, pas de check.sh CI)"
      lab_names+=("$lab")
      lab_results+=("SKIP")
      skip=$((skip + 1))
      continue
      ;;
  esac

  found=1
  # Namespace DNS-1123, unique pour ce lab dans cette exécution.
  ns="lab-ci-${lab}-${RANDOM}"
  echo
  echo "======== ${lab} (NS=${ns}) ========"
  if NS="$ns" bash "$check"; then
    echo "--> ${lab}: PASS"
    lab_names+=("$lab")
    lab_results+=("PASS")
    pass=$((pass + 1))
  else
    echo "--> ${lab}: FAIL"
    lab_names+=("$lab")
    lab_results+=("FAIL")
    fail=$((fail + 1))
  fi
done

if [ "$found" -eq 0 ] && [ "$skip" -eq 0 ]; then
  echo "Aucun kubernetes/lab*/check.sh trouvé."
  exit 0
fi

if [ "$found" -eq 0 ]; then
  echo
  echo "Aucun check.sh automatisé (hors lab01). Rien à exécuter."
fi

echo
echo "Récapitulatif"
printf '%-28s %s\n' "Lab" "Résultat"
printf '%-28s %s\n' "----------------------------" "--------"

i=0
while [ "$i" -lt "${#lab_names[@]}" ]; do
  printf '%-28s %s\n' "${lab_names[$i]}" "${lab_results[$i]}"
  i=$((i + 1))
done

echo
echo "PASS=${pass}  FAIL=${fail}  SKIP=${skip}"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
