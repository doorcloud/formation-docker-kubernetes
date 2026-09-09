#!/usr/bin/env bash
# Lab 02 — decouvrir le cluster (lecture seule, non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
warn() { echo "WARN: $*"; }

NS="${NS:-lab-check-$RANDOM}"

kc() {
  kubectl --request-timeout=30s "$@"
}

# shellcheck disable=SC2329 # invoquee via trap EXIT
cleanup() {
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

# ---------------------------------------------------------------------------
# Nœuds Ready ≥ 1
# ---------------------------------------------------------------------------
ready_count=0
while IFS= read -r st; do
  [[ -z "$st" ]] && continue
  if [[ "$st" == "True" ]]; then
    ready_count=$((ready_count + 1))
  fi
done < <(kc get nodes -o jsonpath='{range .items[*].status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}')

(( ready_count >= 1 )) || fail "aucun nœud Ready (obtenu: $ready_count)"
ok "nœuds Ready=$ready_count"

# ---------------------------------------------------------------------------
# StorageClass par defaut : OK si presente, WARN si absente (pas FAIL)
# ---------------------------------------------------------------------------
default_sc="$(kc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}')"
if [[ -z "$default_sc" ]]; then
  default_sc="$(kc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}')"
fi
default_sc="$(printf '%s\n' "$default_sc" | awk 'NF{print; exit}')"

if [[ -n "$default_sc" ]]; then
  ok "StorageClass par defaut=$default_sc"
else
  warn "aucune StorageClass par defaut (sur DKS: door-ssd ; sur kind: standard)"
fi

# ---------------------------------------------------------------------------
# CoreDNS Running
# ---------------------------------------------------------------------------
kc wait -n kube-system --for=condition=Available deploy/coredns --timeout=120s >/dev/null \
  || fail "deploiement coredns non Available dans kube-system"

coredns_running=0
while IFS= read -r phase; do
  [[ -z "$phase" ]] && continue
  if [[ "$phase" == "Running" ]]; then
    coredns_running=$((coredns_running + 1))
  fi
done < <(kc get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}')

if (( coredns_running < 1 )); then
  while IFS= read -r line; do
    name="${line%%	*}"
    phase="${line##*	}"
    if [[ "$name" == *coredns* && "$phase" == "Running" ]]; then
      coredns_running=$((coredns_running + 1))
    fi
  done < <(kc get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}')
fi

(( coredns_running >= 1 )) || fail "aucun pod CoreDNS Running dans kube-system"
ok "CoreDNS Running=$coredns_running"

# Observation CNI (kindnet sur kind, Cilium sur DKS) — ne pas echouer
cni_line="$(kc get pods -n kube-system --no-headers 2>/dev/null | awk 'tolower($0) ~ /kindnet|cilium|calico|flannel/ {print $1,$3}')"
if [[ -n "$cni_line" ]]; then
  ok "CNI observe (lecture seule): $(printf '%s' "$cni_line" | tr '\n' ';')"
else
  warn "aucun pod CNI reconnu (kindnet/cilium/calico/flannel) dans kube-system"
fi

ok "lab02-decouverte termine"
exit 0
