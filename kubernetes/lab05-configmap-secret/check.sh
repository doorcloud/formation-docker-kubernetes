#!/usr/bin/env bash
# Lab 05 — ConfigMap + Secret + Pod redis (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
POD=redis

kc() {
  kubectl --request-timeout=30s "$@"
}

# shellcheck disable=SC2329 # invoquee via trap EXIT
cleanup() {
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"
[[ -f redis.conf ]] || fail "redis.conf manquant"
[[ -f configmap.yaml ]] || fail "configmap.yaml manquant"
[[ -f secret.yaml ]] || fail "secret.yaml manquant"
[[ -f pod.yaml ]] || fail "pod.yaml manquant"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

kc apply -n "$NS" -f configmap.yaml -f secret.yaml -f pod.yaml >/dev/null
kc wait -n "$NS" --for=condition=Ready "pod/${POD}" --timeout=120s >/dev/null \
  || fail "pod ${POD} pas Ready en 120s"
ok "pod ${POD} Ready"

env_out="$(kc exec -n "$NS" "$POD" -- env)"
printf '%s\n' "$env_out" | grep -q '^DB_PASSWORD=ChangeMe-lab$' \
  || fail "DB_PASSWORD absent ou inattendu dans env"
ok "env DB_PASSWORD=ChangeMe-lab"

conf="$(kc exec -n "$NS" "$POD" -- cat /usr/local/etc/redis/redis.conf)"
printf '%s\n' "$conf" | grep -q 'maxmemory 2mb' \
  || fail "redis.conf monte : maxmemory 2mb introuvable"
ok "fichier /usr/local/etc/redis/redis.conf monte"

pong="$(kc exec -n "$NS" "$POD" -- redis-cli ping)"
[[ "$pong" == "PONG" ]] || fail "redis-cli ping attendu PONG (obtenu: [$pong])"
ok "redis-cli ping -> PONG"

ok "lab05-configmap-secret termine"
exit 0
