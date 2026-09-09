#!/usr/bin/env bash
# Exécute chaque docker/lab*/check.sh et affiche un tableau PASS/FAIL.
# Portable macOS (bash 3.2) : pas de timeout(1), pas d'options GNU de date.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0
fail=0
lab_names=()
lab_results=()

found=0
for check in docker/lab*/check.sh; do
  if [ ! -f "$check" ]; then
    continue
  fi
  found=1
  lab="$(basename "$(dirname "$check")")"
  echo
  echo "======== ${lab} ========"
  if bash "$check"; then
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

if [ "$found" -eq 0 ]; then
  echo "Aucun docker/lab*/check.sh trouvé."
  exit 0
fi

echo
echo "Récapitulatif"
printf '%-22s %s\n' "Lab" "Résultat"
printf '%-22s %s\n' "----------------------" "--------"

i=0
while [ "$i" -lt "${#lab_names[@]}" ]; do
  printf '%-22s %s\n' "${lab_names[$i]}" "${lab_results[$i]}"
  i=$((i + 1))
done

echo
echo "PASS=${pass}  FAIL=${fail}"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
