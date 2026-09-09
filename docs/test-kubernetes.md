# Tests Kubernetes — ce que CI prouve (et ce qu’elle ne prouve pas)

Document **formateur**. Les stagiaires suivent [prerequis-kubernetes.md](prerequis-kubernetes.md) et [kubernetes/README.md](../kubernetes/README.md).

Quatre chemins, complémentaires :

| Chemin | Quoi | Qui |
|--------|------|-----|
| kind 1.37 sur le Mac du formateur | Labs génériques 02–08, 10 (`check.sh`) | Formateur, la veille |
| Second kind + Cilium | Lab 9 NetworkPolicy **appliquée** | Formateur (kindnet n’applique pas les NetPol) |
| Cluster DKS réel | Lab 1, StorageClass/PVC, LoadBalancer/Gateway, passe `scripts/k8s-check-all.sh` | Formateur, quota Door |
| GitHub Actions `k8s-labs.yml` | Lint + kind 1.37 + `k8s-check-all.sh` | Chaque push/PR qui touche `kubernetes/**` ou `scripts/k8s-*` |

Le job Windows (`.github/workflows/windows-client.yml`) **ne lance aucun** lab Kubernetes. Hygiène CRLF / copier-coller seulement.

---

## 1. kind 1.37 sur le Mac du formateur

Image nœud alignée sur kind **v0.33.0** (release GitHub `kubernetes-sigs/kind`, 26 août 2026) : `kindest/node:v1.37.0` (digest `sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5`). Kubernetes **1.37** = `stable.txt` au 9 septembre 2026.

```bash
kind create cluster --name formation-test --image kindest/node:v1.37.0
kubectl --context kind-formation-test get nodes
cd /chemin/vers/formation-docker-kubernetes
bash scripts/k8s-check-all.sh
```

`k8s-check-all.sh` ignore le Lab 1 (manuel), pose un `NS` unique par lab, exécute chaque `kubernetes/lab*/check.sh` présent. Relancer une deuxième fois (idempotence).

CNI par défaut : **kindnet**. StorageClass : **`standard`**. Pas de LoadBalancer cloud.

Nettoyage namespaces de test :

```bash
bash scripts/k8s-cleanup-all.sh --yes
kind delete cluster --name formation-test
```

---

## 2. Second cluster kind + Cilium (NetworkPolicy)

kindnet seul **n’applique pas** les `NetworkPolicy` (les kind récents embarquent `kube-network-policies`, qui peut les appliquer : testez plutôt que de supposer). Pour une démo Lab 9 garantie, un cluster **sans CNI par défaut**, puis Cilium (Helm 4). Le fichier `kind-netpol.yaml` et les values Cilium **ne sont pas dans le dépôt** : le formateur les garde en local (schéma ci-dessous).

Schéma :

```bash
# kind-netpol.yaml (local, hors dépôt) :
#   kind: Cluster
#   apiVersion: kind.x-k8s.io/v1alpha4
#   networking: { disableDefaultCNI: true, kubeProxyMode: none }
kind create cluster --name formation-netpol --config kind-netpol.yaml --image kindest/node:v1.32.11
helm repo add cilium https://helm.cilium.io && helm repo update
helm install cilium cilium/cilium --version 1.18.4 -n kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=formation-netpol-control-plane --set k8sServicePort=6443
kubectl --context kind-formation-netpol -n kube-system get pods
bash kubernetes/lab09-networkpolicy/check.sh
kind delete cluster --name formation-netpol
```

Ne mélangez pas ce contexte avec `kind-formation-test` : un `kubectl` sans `--context` ciblerait le dernier cluster courant.

---

## 3. Passe cluster DKS réel

À faire au moins une fois avant la salle, avec un cluster DKS **public** (sinon l’API n’est pas joignable hors réseau interne) :

1. Lab 1 : console Door → kubeconfig → `kubectl get nodes`.
2. Labs 2–10 via README (replay manuel) **et** `bash scripts/k8s-check-all.sh`.
3. Points **invisibles sur kind** : StorageClass / provisioner DKS (Lab 7), Service LoadBalancer ou Gateway (bonus), quotas projet, délai de création du cluster.
4. Supprimer le cluster de test formateur en fin de passe (coût / quota).

Les `check.sh` respectent `KUBECONFIG`. Ne pointez pas un kubeconfig de production.

### Résultat de la passe du 09/09/2026 (cluster `formation-test`, 1 × c5.large, v1.32.4, Abidjan)

`scripts/k8s-check-all.sh` : **9/9 labs PASS** (lab 1 manuel : OK depuis un Mac hors réseau Door). Ce que kind n'avait pas montré, corrigé dans les labs :

| Constat sur DKS | Effet | Correctif |
|---|---|---|
| Le ServiceAccount `default` apparaît ~1 s après `create ns` | premier `apply` refusé (`serviceaccount "default" not found`) | attente du SA dans tous les `check.sh` ; en salle, relancer la commande |
| PV Trident (`door-ssd`, ontap-san) sans `fsType` → `fsGroup` non appliqué | `Permission denied` sur `/data` en non-root (lab 7) | `initContainer` root `chown-data` dans `pod-pvc.yaml` |
| Docker Hub à 16 KiB/s – 1 MiB/s depuis les nœuds (ghcr.io : 5 MiB/s) | `ContainerCreating` pendant des minutes, `ImagePullBackOff` | miroir `ghcr.io/doorcloud/formation/*` + pré-pull la veille, voir [images-registres.md](images-registres.md) |
| Pulls sérialisés par nœud (`serializeImagePulls`) ; plateforme Door encore en cours d'installation 60–90 min après `Provisioned` | même une image introuvable met 2 min à passer en `ErrImagePull` (lab 6) | timeout lab 6 porté à 240 s ; créer les clusters **la veille** |
| c5.large : ~50 % de la mémoire déjà réservée par la plateforme Door | Pending possibles avec plusieurs labs actifs | **c5.xlarge** × 1 par cluster binôme |

Vérifié conforme : Cilium 1.18 (NetworkPolicy lab 9 appliquées), `door-ssd` par défaut (`Immediate`, `Delete`), PSA non restreint par défaut sur les namespaces tenant (lab 8 : `nginx` root démarre, `privileged` refusé seulement après le label `restricted`), Helm 4 (lab 10) OK.

---

## 4. GitHub Actions — job `kind`

Fichier : `.github/workflows/k8s-labs.yml`.

- Déclenchement : `push` / `pull_request` sur `main` si `kubernetes/**` ou `scripts/k8s-*` (ou le workflow lui-même) changent ; `workflow_dispatch`.
- Job `lint` : shellcheck des `kubernetes/**/*.sh` et `scripts/k8s-*.sh`, yamllint, `helm lint` sur les charts, scan des chaînes interdites (même motif que `ci.yml`). Pas de `kubectl --dry-run=client -f` : pas de cluster dans ce job.
- Job `kind` (`ubuntu-latest`, timeout **25 min**) : `helm/kind-action` + image nœud 1.37, Helm 4, puis `scripts/k8s-check-all.sh`.

Ce job **ne prouve pas** : console Door, kubeconfig stagiaire, LoadBalancer DKS, enforcement Cilium, laptop Windows. D’où la checklist WSL ci-dessous.

---

## Checklist manuelle Windows / WSL

À cocher sur un **vrai laptop Windows** (Docker Desktop + Ubuntu WSL), en tant que stagiaire.

1. **kubectl et Helm dans Ubuntu WSL**, pas dans PowerShell :

   ```bash
   command -v kubectl helm
   kubectl version --client
   helm version
   ```

   Si `kubectl` n’existe que comme `kubectl.exe` sous `/mnt/c/...`, réinstallez selon [prerequis-kubernetes.md](prerequis-kubernetes.md).

2. **Kubeconfig sous `~/`**, pas `/mnt/c` :

   ```bash
   mkdir -p ~/.kube
   # copier le YAML Door depuis Downloads Windows vers ~/.kube/dks.yaml
   chmod 600 ~/.kube/dks.yaml
   export KUBECONFIG=~/.kube/dks.yaml
   kubectl get nodes
   ```

   `ls -l ~/.kube/dks.yaml` doit montrer des droits restreints. Un chemin `/mnt/c/Users/.../Downloads/...` est un échec pédagogique (permissions, OneDrive).

3. **`port-forward` joignable depuis le navigateur Windows** via `localhost` (Lab 10, et tout `kubectl port-forward … 8080:80`) :

   ```bash
   kubectl -n "$NS" port-forward svc/<service> 8080:80
   ```

   Laisser le processus tourner. Sur Windows, ouvrir `http://localhost:8080` dans Chrome/Edge. WSL2 relaie `localhost` vers la distro. Si la page ne vient pas : vérifier que le forward écoute bien sur le port 8080 **dans WSL** (`ss -lntp | grep 8080` ou `curl -sS http://localhost:8080`), firewall, VPN. Ne pas tester uniquement `curl` dans WSL en oubliant le navigateur hôte : c’est le geste stagiaire.

4. **kind optionnel sous WSL** (plan B) : `docker info` OK dans Ubuntu, puis `kind create cluster` comme dans [plan-b-kubernetes.md](plan-b-kubernetes.md). Le forward `localhost` se comporte comme ci-dessus.

Si un point échoue sur le laptop formateur, il échouera en salle. Corriger la doc **avant** 08h00, ou prévoir le plan B (cluster partagé / Killercoda / binôme).
