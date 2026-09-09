#!/usr/bin/env bash
# Lab 07 — emptyDir partage + PVC 1Gi RWO (classe par defaut), persistance (non interactif).
# shellcheck disable=SC2329
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NS="${NS:-lab-check-$RANDOM}"
TIMEOUT="${TIMEOUT:-120}"

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
  kc get pods,pvc -n "$NS" -o wide >&2 || true
  fail "timeout ${TIMEOUT}s : $desc"
}

pod_absent() {
  ! kc get pod "$1" -n "$NS" >/dev/null 2>&1
}

delete_pod_gone() {
  local name="$1"
  if kc get pod "$name" -n "$NS" >/dev/null 2>&1; then
    kc delete pod "$name" -n "$NS" --wait=true --timeout=90s --grace-period=1 >/dev/null 2>&1 || true
  fi
  wait_until "pod $name absent de l'API" pod_absent "$name"
}

# ---------------------------------------------------------------------------
# 1. emptyDir : deux conteneurs, meme repertoire
# ---------------------------------------------------------------------------
kc apply -n "$NS" -f pod-emptydir.yaml >/dev/null
kc wait --for=condition=Ready pod/partage -n "$NS" --timeout="${TIMEOUT}s"
ok "pod partage Ready (emptyDir)"

kc exec -n "$NS" partage -c redacteur -- sh -c 'echo bonjour-emptydir > /data/hello.txt'
shared="$(kc exec -n "$NS" partage -c lecteur -- cat /data/hello.txt)"
[[ "$shared" == "bonjour-emptydir" ]] || fail "emptyDir non partage (lecteur a lu: [$shared])"
ok "emptyDir : redacteur et lecteur voient /data/hello.txt"

delete_pod_gone partage
kc apply -n "$NS" -f pod-emptydir.yaml >/dev/null
kc wait --for=condition=Ready pod/partage -n "$NS" --timeout="${TIMEOUT}s"
if kc exec -n "$NS" partage -c lecteur -- cat /data/hello.txt >/dev/null 2>&1; then
  fail "emptyDir n'aurait pas du survivre a la recreation du Pod"
fi
ok "emptyDir : fichier absent apres recreation du Pod (attendu)"

# ---------------------------------------------------------------------------
# 2. PVC sans storageClassName (classe par defaut du cluster)
# ---------------------------------------------------------------------------
default_sc="$(kc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{" "}{.volumeBindingMode}{" "}{.reclaimPolicy}{end}' 2>/dev/null || true)"
if [[ -n "$default_sc" ]]; then
  ok "StorageClass par defaut : $default_sc"
else
  ok "aucune StorageClass annotee default — on tente le PVC sans storageClassName"
fi

kc apply -n "$NS" -f pvc.yaml -f pod-pvc.yaml >/dev/null
kc wait --for=condition=Ready pod/persistant -n "$NS" --timeout="${TIMEOUT}s"
ok "pod persistant Ready"

pvc_phase="$(kc get pvc donnees -n "$NS" -o jsonpath='{.status.phase}')"
[[ "$pvc_phase" == "Bound" ]] || fail "PVC donnees phase=$pvc_phase (Bound attendu)"
ok "PVC donnees Bound"

pv_name="$(kc get pvc donnees -n "$NS" -o jsonpath='{.spec.volumeName}')"
[[ -n "$pv_name" ]] || fail "PVC Bound sans spec.volumeName"
pv_phase="$(kc get pv "$pv_name" -o jsonpath='{.status.phase}')"
[[ "$pv_phase" == "Bound" ]] || fail "PV $pv_name phase=$pv_phase"
ok "PV $pv_name Bound (kubectl get pv)"

kc exec -n "$NS" persistant -c writer -- sh -c 'echo bonjour-pvc > /data/hello.txt'
first="$(kc exec -n "$NS" persistant -c writer -- cat /data/hello.txt)"
[[ "$first" == "bonjour-pvc" ]] || fail "ecriture PVC echouee (lu: [$first])"
ok "ecriture /data/hello.txt sur le PVC"

delete_pod_gone persistant
kc apply -n "$NS" -f pod-pvc.yaml >/dev/null
kc wait --for=condition=Ready pod/persistant -n "$NS" --timeout="${TIMEOUT}s"
second="$(kc exec -n "$NS" persistant -c writer -- cat /data/hello.txt)"
[[ "$second" == "bonjour-pvc" ]] || fail "persistance cassee apres recreation (lu: [$second])"
ok "fichier present apres delete+recreate du Pod"

# ---------------------------------------------------------------------------
# 3. Reclaim : supprimer le claim, PV Released ou Deleted
# ---------------------------------------------------------------------------
reclaim="$(kc get pv "$pv_name" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')"
ok "reclaimPolicy du PV : ${reclaim:-inconnu}"

delete_pod_gone persistant
kc delete pvc donnees -n "$NS" --wait=true --timeout=90s >/dev/null
ok "PVC donnees supprime"

is_pv_gone_or_released() {
  local phase
  if ! kc get pv "$pv_name" >/dev/null 2>&1; then
    return 0
  fi
  phase="$(kc get pv "$pv_name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Released" || "$phase" == "Failed" ]]
}

wait_until "PV $pv_name Released ou supprime" is_pv_gone_or_released
if kc get pv "$pv_name" >/dev/null 2>&1; then
  ok "PV $pv_name encore visible (phase $(kc get pv "$pv_name" -o jsonpath='{.status.phase}'))"
else
  ok "PV $pv_name supprime (reclaim Delete)"
fi

ok "lab07-stockage termine"
exit 0
