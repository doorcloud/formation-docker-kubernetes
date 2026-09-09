#!/usr/bin/env bash
# Lab 08 — SA/Role/can-i, curl API 200/403, SecurityContext, PSA (non interactif).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
TIMEOUT="${TIMEOUT:-120}"
AS_LECTEUR="system:serviceaccount:${NS}:lecteur"

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

http_code() {
  local method="$1"
  local url="$2"
  local code
  code="$(kc exec -n "$NS" curl-api -c curl -- sh -c \
    'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
     curl -sS -o /dev/null -w "%{http_code}" --max-time 15 \
       --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
       -X '"$method"' \
       -H "Authorization: Bearer $TOKEN" \
       "'"$url"'"')"
  tr -d '\r\n' <<<"$code"
}

# ---------------------------------------------------------------------------
# 1. RBAC lecture seule
# ---------------------------------------------------------------------------
kc apply -n "$NS" \
  -f sa.yaml \
  -f role-pod-reader.yaml \
  -f rolebinding-lecteur.yaml >/dev/null
ok "SA lecteur + Role pod-reader + RoleBinding"

list_can="$(kc auth can-i list pods --as="$AS_LECTEUR" -n "$NS")"
[[ "$list_can" == "yes" ]] || fail "can-i list pods attendu yes (obtenu: $list_can)"
ok "can-i list pods --as=$AS_LECTEUR → yes"

if del_can="$(kc auth can-i delete pods --as="$AS_LECTEUR" -n "$NS")"; then
  fail "can-i delete pods aurait du etre no (obtenu: $del_can)"
else
  [[ "${del_can:-no}" == "no" ]] || fail "can-i delete pods attendu no (obtenu: $del_can)"
  ok "can-i delete pods --as=$AS_LECTEUR → no"
fi

token="$(kc create token lecteur -n "$NS")"
[[ "$(awk -F. '{print NF}' <<<"$token")" -eq 3 ]] || fail "kubectl create token lecteur n'a pas renvoye un JWT"
ok "kubectl create token lecteur (JWT 3 segments)"

kc apply -n "$NS" -f pod-curl.yaml -f pod-cible.yaml >/dev/null
kc wait --for=condition=Ready pod/curl-api -n "$NS" --timeout="${TIMEOUT}s"
kc wait --for=condition=Ready pod/cible -n "$NS" --timeout="${TIMEOUT}s"
ok "pods curl-api et cible Ready"

get_url="https://kubernetes.default.svc/api/v1/namespaces/${NS}/pods"
del_url="https://kubernetes.default.svc/api/v1/namespaces/${NS}/pods/cible"

code_get="$(http_code GET "$get_url")"
[[ "$code_get" == "200" ]] || fail "GET pods HTTP $code_get (200 attendu)"
ok "GET .../pods via token monte → 200"

code_del="$(http_code DELETE "$del_url")"
[[ "$code_del" == "403" ]] || fail "DELETE cible HTTP $code_del (403 attendu)"
ok "DELETE .../pods/cible via token monte → 403"

# ---------------------------------------------------------------------------
# 2. Second Role : delete
# ---------------------------------------------------------------------------
kc apply -n "$NS" -f role-pod-deleter.yaml -f rolebinding-deleter.yaml >/dev/null

can_delete_yes() {
  local ans
  ans="$(kc auth can-i delete pods --as="$AS_LECTEUR" -n "$NS" 2>/dev/null || true)"
  [[ "$ans" == "yes" ]]
}
wait_until "can-i delete pods → yes" can_delete_yes
ok "can-i delete pods → yes (Role pod-deleter)"

code_del2=""
del_deadline=$((SECONDS + 30))
while (( SECONDS < del_deadline )); do
  code_del2="$(http_code DELETE "$del_url")"
  if [[ "$code_del2" == "200" ]]; then
    break
  fi
  if [[ "$code_del2" == "404" ]]; then
    fail "DELETE cible → 404 (pod deja absent, 200 attendu)"
  fi
  sleep 2
done
[[ "$code_del2" == "200" ]] || fail "DELETE cible HTTP $code_del2 (200 attendu apres Role delete)"
ok "DELETE .../pods/cible → 200"

# ---------------------------------------------------------------------------
# 3. SecurityContext : nginx root vs unprivileged
# ---------------------------------------------------------------------------
kc apply -n "$NS" -f pod-nginx-root.yaml >/dev/null

is_root_denied() {
  local r
  r="$(kc get pod nginx-root-interdit -n "$NS" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
  [[ "$r" == "CreateContainerConfigError" ]]
}
wait_until "nginx-root-interdit CreateContainerConfigError" is_root_denied
ok "nginx:1.27-alpine + runAsNonRoot → CreateContainerConfigError"

kc apply -n "$NS" -f pod-nginx-unprivileged.yaml >/dev/null
kc wait --for=condition=Ready pod/nginx-unprivileged -n "$NS" --timeout="${TIMEOUT}s"
ok "nginxinc/nginx-unprivileged:1.27-alpine Ready (runAsNonRoot + drop ALL + readOnlyRootFilesystem)"

# ---------------------------------------------------------------------------
# 4. PSA restricted : pod privileged refuse a l'admission
# ---------------------------------------------------------------------------
kc label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
ok "namespace labelle pod-security.kubernetes.io/enforce=restricted"

set +e
psa_out="$(kc apply -n "$NS" -f pod-privilegie.yaml 2>&1)"
psa_rc=$?
set -e
[[ "$psa_rc" -ne 0 ]] || fail "pod privilegie-interdit aurait du etre refuse (exit 0)"
grep -q "violates PodSecurity" <<<"$psa_out" || fail "message PSA inattendu: $psa_out"
ok "apply privilegie-interdit refuse (violates PodSecurity)"

ok "lab08-rbac termine"
exit 0
