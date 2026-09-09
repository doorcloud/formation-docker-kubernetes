#!/usr/bin/env bash
# Lab 03 — namespace + Pod multi-conteneurs (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
POD=deux-conteneurs

kc() {
  kubectl --request-timeout=30s "$@"
}

# shellcheck disable=SC2329 # invoquee via trap EXIT
cleanup() {
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"
[[ -f pod.yaml ]] || fail "pod.yaml manquant"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

kc apply -n "$NS" -f pod.yaml >/dev/null
kc wait -n "$NS" --for=condition=Ready "pod/${POD}" --timeout=120s >/dev/null \
  || fail "pod ${POD} pas Ready en 120s"

nready=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  nready=$((nready + 1))
done < <(kc get pod "$POD" -n "$NS" -o jsonpath='{range .status.containerStatuses[?(@.ready==true)]}{.name}{"\n"}{end}')
[[ "$nready" == "2" ]] || fail "attendu 2/2 Ready (obtenu: $nready)"
ok "pod ${POD} 2/2 Ready"

page="$(kc exec -n "$NS" "$POD" -c sidecar -- wget -qO- http://localhost:80)"
printf '%s' "$page" | grep -qi nginx || fail "wget sidecar -> :80 n'a pas renvoye la page nginx"
ok "sidecar wget http://localhost:80 (page nginx)"

# kubectl run jetable, non interactif (le README montre --rm -it)
tmp="tmp-check-${RANDOM}"
kc run "$tmp" -n "$NS" --restart=Never --image=ghcr.io/doorcloud/formation/busybox:1.36 \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"${tmp}\",\"image\":\"ghcr.io/doorcloud/formation/busybox:1.36\",\"command\":[\"echo\",\"ok\"],\"resources\":{\"requests\":{\"cpu\":\"10m\",\"memory\":\"16Mi\"},\"limits\":{\"cpu\":\"50m\",\"memory\":\"32Mi\"}}}]}}" \
  >/dev/null

tmp_deadline=$((SECONDS + 120))
tmp_phase=""
while (( SECONDS < tmp_deadline )); do
  tmp_phase="$(kc get pod "$tmp" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)"
  if [[ "$tmp_phase" == "Succeeded" || "$tmp_phase" == "Failed" ]]; then
    break
  fi
  sleep 2
done
tmp_out="$(kc logs -n "$NS" "$tmp" 2>/dev/null || true)"
[[ "$tmp_phase" == "Succeeded" && "$tmp_out" == *ok* ]] \
  || fail "kubectl run jetable: phase=${tmp_phase} out=[${tmp_out}]"
ok "kubectl run jetable (non interactif) echo ok"

ok "lab03-namespace-pod termine"
exit 0
