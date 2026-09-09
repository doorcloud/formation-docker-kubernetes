#!/usr/bin/env bash
# Lab 09 — NetworkPolicy deny-all puis allow frontend→backend (non interactif).
# Détecte si le CNI applique réellement les policies (Cilium oui, kindnet non).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
URL="http://backend:8080"
PROBE_DEADLINE_S=30

kc() { kubectl --request-timeout=30s "$@"; }

# shellcheck disable=SC2329 # invoquee via trap EXIT
cleanup() {
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"
[[ -f frontend.yaml && -f backend.yaml && -f deny-all.yaml && -f allow-frontend.yaml ]] \
  || fail "manifests manquants dans le lab"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

kc apply -n "$NS" -f frontend.yaml -f backend.yaml -f intrus.yaml >/dev/null
kc wait -n "$NS" --for=condition=Available deploy/frontend deploy/backend --timeout=120s >/dev/null
kc wait -n "$NS" --for=condition=Ready pod/intrus --timeout=120s >/dev/null
ok "frontend, backend et intrus Ready"

# wget depuis le pod source (les labels du Pod comptent pour NetworkPolicy).
probe() {
  kc exec -n "$NS" "$1" -- wget -q -T 3 -O /dev/null "$URL" >/dev/null 2>&1
}

wait_deny() {
  local target="$1"
  local deadline=$((SECONDS + PROBE_DEADLINE_S))
  while (( SECONDS < deadline )); do
    if ! probe "$target"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_allow() {
  local target="$1"
  local deadline=$((SECONDS + PROBE_DEADLINE_S))
  while (( SECONDS < deadline )); do
    if probe "$target"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_allow deploy/frontend || fail "baseline : frontend n'atteint pas $URL"
wait_allow pod/intrus || fail "baseline : intrus n'atteint pas $URL"
ok "sans policy : frontend et intrus joignent le backend"

kc apply -n "$NS" -f deny-all.yaml >/dev/null
kc get -n "$NS" networkpolicy deny-all -o jsonpath='{.spec.podSelector}' >/dev/null
ok "NetworkPolicy deny-all appliquee (podSelector vide)"

if wait_deny deploy/frontend; then
  ok "deny-all enforce : frontend n'atteint plus le backend"
else
  kc apply -n "$NS" -f allow-frontend.yaml >/dev/null
  kc apply -n "$NS" -f deny-egress.yaml -f allow-egress-dns.yaml >/dev/null
  np_count="$(kc get -n "$NS" networkpolicy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')"
  echo "$np_count" | grep -q deny-all || fail "deny-all absente apres apply"
  echo "$np_count" | grep -q allow-frontend || fail "allow-frontend absente apres apply"
  ok "manifests NetworkPolicy appliques (API) : $np_count"
  echo "WARN: CNI sans NetworkPolicy (kindnet) — assertions d'isolation ignorées"
  ok "lab09-networkpolicy termine (CNI non enforceur)"
  exit 0
fi

probe pod/intrus && fail "deny-all : intrus devrait etre bloque aussi"
ok "deny-all enforce : intrus bloque aussi"

kc apply -n "$NS" -f allow-frontend.yaml >/dev/null
ok "NetworkPolicy allow-frontend appliquee (role=frontend -> backend:8080)"

wait_allow deploy/frontend || fail "allow-frontend : frontend devrait joindre $URL"
ok "allow-frontend : frontend joint le backend"

if probe pod/intrus; then
  fail "allow-frontend : intrus ne devrait PAS joindre le backend"
fi
ok "allow-frontend : intrus reste bloque"

ok "lab09-networkpolicy termine"
exit 0
