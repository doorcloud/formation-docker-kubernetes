#!/usr/bin/env bash
# Pre-tire les images des labs Kubernetes sur tous les noeuds d'un cluster (formateur, la veille).
# Genere un DaemonSet a partir de kubernetes/images.txt (colonne cible, ghcr.io) et attend
# que toutes les images soient presentes sur chaque noeud.
#
# Usage : KUBECONFIG=... scripts/k8s-prepull.sh [--source]   # --source : utiliser la colonne Docker Hub
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$HERE/kubernetes/images.txt"
NS="formation-prepull"
COL=2
[ "${1:-}" = "--source" ] && COL=1

IMAGES=()
while IFS= read -r img; do IMAGES+=("$img"); done < <(grep -vE '^\s*(#|$)' "$LIST" | awk -v c="$COL" '{print $c}' | sort -u)  # bash 3.2 (macOS) : pas de mapfile
echo "Cluster : $(kubectl config current-context) — ${#IMAGES[@]} images"

# Un initContainer par image : il demarre puis sort tout de suite ; l'image reste dans le cache du noeud.
init=""
i=0
for img in "${IMAGES[@]}"; do
  i=$((i+1))
  init+="
        - name: pull-$i
          image: $img
          imagePullPolicy: IfNotPresent
          command: [\"/bin/sh\", \"-c\", \"exit 0\"]
          resources:
            requests: {cpu: 5m, memory: 8Mi}
            limits: {cpu: 50m, memory: 32Mi}"
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: prepull
  namespace: $NS
  labels:
    app.kubernetes.io/name: prepull
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: prepull
  template:
    metadata:
      labels:
        app.kubernetes.io/name: prepull
    spec:
      tolerations:
        - operator: Exists
      initContainers:$init
      containers:
        - name: sleep
          image: registry.k8s.io/pause:3.10
          resources:
            requests: {cpu: 5m, memory: 8Mi}
            limits: {cpu: 20m, memory: 16Mi}
EOF

echo "Attente (les pulls sont serialises par noeud ; compter 1-10 min selon le registre)..."
kubectl -n "$NS" rollout status ds/prepull --timeout=30m
echo "OK : images presentes sur $(kubectl get nodes --no-headers | wc -l | tr -d ' ') noeud(s)."
echo "Le DaemonSet reste en place (pause) ; pour le retirer : kubectl delete ns $NS"
