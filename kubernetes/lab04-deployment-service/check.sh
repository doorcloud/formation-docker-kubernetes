#!/usr/bin/env bash
# Lab 04 — Deployment + Service ClusterIP + DNS (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

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
[[ -f deployment.yaml ]] || fail "deployment.yaml manquant"
[[ -f service.yaml ]] || fail "service.yaml manquant"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

kc apply -n "$NS" -f deployment.yaml -f service.yaml >/dev/null
kc wait -n "$NS" --for=condition=Available deploy/web --timeout=120s >/dev/null \
  || fail "deploy/web non Available en 120s"

ready="$(kc get deploy web -n "$NS" -o jsonpath='{.status.readyReplicas}')"
[[ "$ready" == "2" ]] || fail "readyReplicas attendu 2 (obtenu: ${ready:-vide})"
ok "deploy/web readyReplicas=2"

# Endpoints / EndpointSlices : 2 adresses Ready (attendre un peu si le miroir retarde)
ep_count=0
deadline=$((SECONDS + 60))
while (( SECONDS < deadline )); do
  ep_count=0
  while IFS= read -r addr; do
    [[ -z "$addr" ]] && continue
    ep_count=$((ep_count + 1))
  done < <(kc get endpointslices -n "$NS" -l kubernetes.io/service-name=web-svc \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{range .addresses[*]}{.}{"\n"}{end}{end}' 2>/dev/null || true)
  if (( ep_count == 2 )); then
    break
  fi
  # repli Endpoints v1 (toujours peuple en 1.37)
  ep_count=0
  while IFS= read -r addr; do
    [[ -z "$addr" ]] && continue
    ep_count=$((ep_count + 1))
  done < <(kc get endpoints web-svc -n "$NS" \
    -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null || true)
  if (( ep_count == 2 )); then
    break
  fi
  sleep 2
done
[[ "$ep_count" == "2" ]] || fail "endpoints Ready attendu 2 (obtenu: $ep_count)"
ok "endpoints Ready=2 (web-svc)"

# HTTP 200 via un pod curl (pas --rm / -it)
curl_pod="curl-check-${RANDOM}"
kc apply -n "$NS" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${curl_pod}
  labels:
    app.kubernetes.io/name: curl-check
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: ghcr.io/doorcloud/formation/curl:8.10.1
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
      command:
        - curl
        - -sS
        - -o
        - /dev/null
        - -w
        - "%{http_code}"
        - --max-time
        - "15"
        - http://web-svc
EOF

phase=""
curl_deadline=$((SECONDS + 120))
while (( SECONDS < curl_deadline )); do
  phase="$(kc get pod "$curl_pod" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)"
  if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
    break
  fi
  sleep 2
done
code="$(kc logs -n "$NS" "$curl_pod" 2>/dev/null || true)"
[[ "$phase" == "Succeeded" && "$code" == "200" ]] \
  || fail "HTTP via curl pod: phase=${phase} code=${code} (attendu Succeeded/200)"
ok "HTTP 200 via ghcr.io/doorcloud/formation/curl:8.10.1 -> http://web-svc"

ok "lab04-deployment-service termine"
exit 0
