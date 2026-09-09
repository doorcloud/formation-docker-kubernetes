#!/usr/bin/env bash
# Lab 10 — Helm 4 : lint, install, curl, upgrade, rollback, uninstall (non interactif).
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
RELEASE=webapp
CHART=./charts/webapp

kc() { kubectl --request-timeout=30s "$@"; }

# shellcheck disable=SC2329 # invoquee via trap EXIT
cleanup() {
  helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
  kc delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v kubectl >/dev/null 2>&1 || fail "kubectl introuvable dans PATH"
command -v helm >/dev/null 2>&1 || fail "helm introuvable dans PATH"
[[ -d "$CHART" ]] || fail "chart $CHART manquant"
helm version --template '{{.Version}}' | grep -q '^v4\.' \
  || echo "WARN: Helm 4 attendu (trouve : $(helm version --template '{{.Version}}'))"

helm lint "$CHART"
ok "helm lint $CHART"

helm template "$RELEASE" "$CHART" >/dev/null
ok "helm template $RELEASE"

kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
ok "namespace $NS cree"
# Le ServiceAccount "default" est cree de facon asynchrone : sans attente, le premier Pod peut etre refuse
# ("serviceaccount default not found"). Observe sur DKS (~1 s).
for _ in $(seq 1 30); do kc get sa default -n "$NS" >/dev/null 2>&1 && break; sleep 1; done
ok "serviceaccount default present"

helm install "$RELEASE" "$CHART" -n "$NS" >/dev/null
ok "helm install $RELEASE"

kc wait -n "$NS" --for=condition=Available deploy/"$RELEASE" --timeout=120s >/dev/null
ok "deployment $RELEASE Available"

ready="$(kc get -n "$NS" deploy/"$RELEASE" -o jsonpath='{.status.readyReplicas}')"
[[ "$ready" == "1" ]] || fail "readyReplicas attendu 1 (obtenu: $ready)"
ok "1 replica Ready"

# curl depuis un pod (pas de port-forward : deterministe en CI / kind)
curl_once() {
  local url="$1"
  local name="curl-check-${RANDOM}"
  local deadline phase body
  kc apply -n "$NS" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  labels:
    app.kubernetes.io/name: curl-check
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      imagePullPolicy: IfNotPresent
      command: ["curl", "-sf", "--max-time", "10", "${url}"]
      resources:
        requests:
          cpu: 25m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 100
EOF
  deadline=$((SECONDS + 120))
  phase=""
  while (( SECONDS < deadline )); do
    phase="$(kc get pod "$name" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo Missing)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
      break
    fi
    sleep 2
  done
  body="$(kc logs -n "$NS" "$name" -c curl 2>/dev/null || true)"
  if [[ "$phase" != "Succeeded" ]]; then
    kc get pod "$name" -n "$NS" -o yaml >&2 || true
    echo "curl logs: [$body]" >&2
    kc delete -n "$NS" pod "$name" --wait=false >/dev/null 2>&1 || true
    return 1
  fi
  kc delete -n "$NS" pod "$name" --wait=false >/dev/null 2>&1 || true
  printf '%s' "$body"
}

curl_retry() {
  local url="$1"
  local attempt body
  for attempt in 1 2 3 4 5; do
    if body="$(curl_once "$url")"; then
      printf '%s' "$body"
      return 0
    fi
    echo "WARN: curl essai ${attempt}/5 echoue, nouvel essai" >&2
    sleep 3
  done
  fail "curl vers ${url} n'a pas reussi apres 5 essais"
}

svc_url="http://${RELEASE}.${NS}.svc"
body="$(curl_retry "$svc_url")"
echo "$body" | grep -q "Bonjour" || fail "page initiale sans Bonjour: [$body]"
ok "curl $svc_url contient Bonjour"

helm list -n "$NS" -q | grep -qx "$RELEASE" || fail "helm list ne montre pas $RELEASE"
ok "helm list : $RELEASE"

helm upgrade "$RELEASE" "$CHART" -n "$NS" --set replicaCount=2 --set message=Bonjour-v2 >/dev/null
ok "helm upgrade replicaCount=2 message=Bonjour-v2"

kc wait -n "$NS" --for=jsonpath='{.spec.replicas}'=2 deploy/"$RELEASE" --timeout=120s >/dev/null
kc rollout status -n "$NS" deploy/"$RELEASE" --timeout=120s >/dev/null
ready2="$(kc get -n "$NS" deploy/"$RELEASE" -o jsonpath='{.status.readyReplicas}')"
[[ "$ready2" == "2" ]] || fail "readyReplicas attendu 2 apres upgrade (obtenu: $ready2)"
ok "2 replicas Ready"

body2="$(curl_retry "$svc_url")"
echo "$body2" | grep -q "Bonjour-v2" || fail "page upgrade sans Bonjour-v2: [$body2]"
ok "curl apres upgrade contient Bonjour-v2"

helm rollback "$RELEASE" 1 -n "$NS" >/dev/null
ok "helm rollback 1"

kc wait -n "$NS" --for=jsonpath='{.spec.replicas}'=1 deploy/"$RELEASE" --timeout=120s >/dev/null
kc rollout status -n "$NS" deploy/"$RELEASE" --timeout=120s >/dev/null
ready1="$(kc get -n "$NS" deploy/"$RELEASE" -o jsonpath='{.status.readyReplicas}')"
[[ "$ready1" == "1" ]] || fail "readyReplicas attendu 1 apres rollback (obtenu: $ready1)"
ok "1 replica Ready apres rollback"

body3="$(curl_retry "$svc_url")"
echo "$body3" | grep -q "Bonjour" || fail "page rollback sans Bonjour: [$body3]"
echo "$body3" | grep -q "Bonjour-v2" && fail "page rollback encore Bonjour-v2"
ok "curl apres rollback contient Bonjour (revision 1)"

helm uninstall "$RELEASE" -n "$NS" >/dev/null
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  fail "release $RELEASE encore presente apres uninstall"
fi
ok "helm uninstall : release absente"

ok "lab10-helm termine"
exit 0
