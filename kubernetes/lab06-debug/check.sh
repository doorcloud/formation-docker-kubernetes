#!/usr/bin/env bash
# Lab 06 — ImagePullBackOff, CrashLoopBackOff, probe / endpoints (non interactif).
# shellcheck disable=SC2329
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
TIMEOUT="${TIMEOUT:-240}"  # DKS : les pulls sont serialises par noeud, une image lente retarde les autres

kc() {
  kubectl --request-timeout=30s "$@"
}

cleanup() {
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! kc get namespace "$NS" >/dev/null 2>&1; then
  kc create namespace "$NS" >/dev/null
fi
ok "namespace $NS"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

wait_until() {
  local desc="$1"
  local deadline=$((SECONDS + TIMEOUT))
  shift
  while (( SECONDS < deadline )); do
    if "$@"; then
      return 0
    fi
    sleep 2
  done
  echo "--- diagnostic namespace $NS ---" >&2
  kc get pods -n "$NS" -o wide >&2 || true
  fail "timeout ${TIMEOUT}s : $desc"
}

pod_waiting_reason() {
  kc get pod "$1" -n "$NS" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true
}

pod_restarts() {
  local c
  c="$(kc get pod "$1" -n "$NS" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)"
  echo "${c:-0}"
}

endpoint_ips() {
  kc get endpoints "$1" -n "$NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true
}

is_image_pull_fail() {
  local r
  r="$(pod_waiting_reason image-introuvable)"
  [[ "$r" == "ImagePullBackOff" || "$r" == "ErrImagePull" ]]
}

is_crash() {
  local r c
  r="$(pod_waiting_reason crash-loop)"
  c="$(pod_restarts crash-loop)"
  [[ "$r" == "CrashLoopBackOff" || "$c" -gt 0 ]]
}

unready_running_count() {
  kc get pods -n "$NS" -l app.kubernetes.io/name=web-pas-pret --no-headers 2>/dev/null \
    | awk '$2 == "0/1" && $3 == "Running" { c++ } END { print c+0 }'
}

is_probe_unready() {
  local n ips
  n="$(unready_running_count)"
  ips="$(endpoint_ips web-pas-pret)"
  [[ "$n" -ge 1 && -z "$ips" ]]
}

has_service_endpoints() {
  local ips
  ips="$(endpoint_ips web-pas-pret)"
  [[ -n "$ips" ]]
}

# ---------------------------------------------------------------------------
# 1. Symptomes
# ---------------------------------------------------------------------------
kc apply -n "$NS" \
  -f pod-image-introuvable.yaml \
  -f pod-crash.yaml \
  -f web-pas-pret.yaml >/dev/null

wait_until "ImagePullBackOff|ErrImagePull sur image-introuvable" is_image_pull_fail
ok "image-introuvable : $(pod_waiting_reason image-introuvable)"

wait_until "CrashLoopBackOff ou restartCount>0 sur crash-loop" is_crash
ok "crash-loop : reason=$(pod_waiting_reason crash-loop) restarts=$(pod_restarts crash-loop)"

logs_prev="$(kc logs -n "$NS" crash-loop --previous 2>/dev/null || true)"
logs_cur="$(kc logs -n "$NS" crash-loop 2>/dev/null || true)"
if grep -q boot <<<"${logs_prev}${logs_cur}"; then
  ok "logs crash-loop contiennent boot"
else
  fail "logs crash-loop (current/previous) sans 'boot'"
fi

wait_until "Pods web-pas-pret Running 0/1 et Service sans endpoints" is_probe_unready
ok "web-pas-pret : au moins 1 Pod Running non Ready, endpoints vides"

kc get events -n "$NS" --sort-by=.lastTimestamp >/dev/null
ok "kubectl get events --sort-by=.lastTimestamp"

# EndpointSlices : aucune adresse Ready
ready_slice="$(kc get endpointslices -n "$NS" -l kubernetes.io/service-name=web-pas-pret \
  -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses}{end}' 2>/dev/null || true)"
[[ -z "$ready_slice" ]] || fail "EndpointSlice Ready non vide avant correctif (obtenu: $ready_slice)"
ok "EndpointSlice web-pas-pret : 0 adresse Ready"

# kubectl debug non interactif (conteneur nginx du Deployment, processus vivant)
web_pod="$(kc get pod -n "$NS" -l app.kubernetes.io/name=web-pas-pret \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$web_pod" ]] || fail "aucun Pod web-pas-pret Running pour kubectl debug"
kc debug "pod/${web_pod}" -n "$NS" \
  --image=busybox:1.36 \
  --target=nginx \
  --profile=general \
  --attach=false \
  --quiet \
  -- sh -c 'echo debug-ok' >/dev/null
eph="$(kc get pod -n "$NS" "$web_pod" -o jsonpath='{.spec.ephemeralContainers[*].name}' 2>/dev/null || true)"
[[ -n "$eph" ]] || fail "aucun ephemeral container apres kubectl debug"
ok "kubectl debug ephemeral container sur $web_pod ($eph)"

if kc top nodes >/dev/null 2>&1; then
  ok "kubectl top nodes (metrics-server present)"
else
  ok "kubectl top indisponible (metrics-server absent) — normal sur kind"
fi

# ---------------------------------------------------------------------------
# 2. Correctifs + guerison
# ---------------------------------------------------------------------------
kc apply -n "$NS" -f fix/pod-image-ok.yaml -f fix/web-ok.yaml >/dev/null \
  || fail "apply des correctifs image/web"
kc delete pod crash-loop -n "$NS" --wait=true --timeout=60s >/dev/null
kc apply -n "$NS" -f fix/pod-crash-ok.yaml >/dev/null \
  || fail "apply du correctif crash-loop"

kc wait --for=condition=Ready pod/image-introuvable -n "$NS" --timeout="${TIMEOUT}s"
ok "image-introuvable Ready (image corrigee)"

kc wait --for=condition=Ready pod/crash-loop -n "$NS" --timeout="${TIMEOUT}s"
ok "crash-loop Ready (commande sans exit 1)"

kc rollout status deploy/web-pas-pret -n "$NS" --timeout="${TIMEOUT}s"
ok "web-pas-pret rollout (readinessProbe /)"

wait_until "Service web-pas-pret a des endpoints" has_service_endpoints
ips="$(endpoint_ips web-pas-pret)"
[[ -n "$ips" ]] || fail "endpoints toujours vides apres correctif"
ok "Service web-pas-pret a des endpoints ($ips)"

ok "lab06-debug termine"
exit 0
