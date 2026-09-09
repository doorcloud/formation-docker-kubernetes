#!/usr/bin/env bash
# Lab 01 — contexte kubectl, nœuds, namespace, SC, Cilium (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
warn() { echo "WARN: $*"; }

NS="${NS:-lab-check}"

kc() {
  kubectl --request-timeout=15s "$@"
}

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"

# ---------------------------------------------------------------------------
# API joignable
# ---------------------------------------------------------------------------
if ! kc cluster-info >/dev/null 2>&1; then
  fail "contexte kubectl injoignable (cluster-info, timeout 15s) — Public / KUBECONFIG ?"
fi
ok "kubectl cluster-info (timeout 15s)"

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
ok "nœuds Ready=${ready_count}"

# ---------------------------------------------------------------------------
# Mineure serveur ≥ 1.30
# ---------------------------------------------------------------------------
minor=""
ver_json="$(kc get --raw /version 2>/dev/null || true)"
if [[ -n "$ver_json" ]]; then
  minor="$(printf '%s' "$ver_json" | sed -n 's/.*"minor":"\([0-9][0-9]*\).*/\1/p' | head -n 1)"
fi
if [[ -z "$minor" ]]; then
  minor="$(kc version 2>/dev/null | sed -n 's/.*Server Version: v1\.\([0-9][0-9]*\).*/\1/p' | head -n 1)"
fi
[[ -n "$minor" ]] || fail "impossible de lire la mineure Kubernetes serveur"
if (( minor < 30 )); then
  fail "mineure serveur 1.${minor} < 1.30"
fi
ok "serveur Kubernetes 1.${minor}.x (>= 1.30)"

# ---------------------------------------------------------------------------
# Namespace : existe ou creation
# ---------------------------------------------------------------------------
if kc get namespace "$NS" >/dev/null 2>&1; then
  ok "namespace ${NS} existe"
else
  kc create namespace "$NS" >/dev/null
  ok "namespace ${NS} cree"
fi
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

# ---------------------------------------------------------------------------
# API server masque (pas d'hote complet dans les logs)
# ---------------------------------------------------------------------------
server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
if [[ -z "$server" ]]; then
  warn "impossible de lire cluster.server dans le kubeconfig"
else
  masked="$(printf '%s' "$server" | sed -E 's#^(https?://)[^:/]+#\1***#')"
  ok "API server ${masked}"
fi

# ---------------------------------------------------------------------------
# StorageClass par defaut (WARN si absente)
# ---------------------------------------------------------------------------
default_sc="$(kc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
if [[ -z "$default_sc" ]]; then
  default_sc="$(kc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
fi
default_sc="$(printf '%s\n' "$default_sc" | awk 'NF { print; exit }')"

if [[ -n "$default_sc" ]]; then
  ok "StorageClass par defaut=${default_sc}"
else
  warn "aucune StorageClass par defaut (sur DKS: door-ssd ; sur kind: standard)"
fi

# ---------------------------------------------------------------------------
# Cilium (WARN si absent — kind = kindnet)
# ---------------------------------------------------------------------------
cilium_line="$(kc get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null || true)"
if [[ -n "$(printf '%s' "$cilium_line" | awk 'NF')" ]]; then
  ok "pods Cilium presents (kube-system, k8s-app=cilium)"
else
  warn "pas de pods Cilium (k8s-app=cilium) — sur kind le CNI est kindnet"
fi

ok "lab01-cluster-dks termine"
exit 0
