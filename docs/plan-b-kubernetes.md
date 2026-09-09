# Plan B — pas de cluster DKS personnel

Le chemin normal est le Lab 1 : le cluster DKS **de votre binôme**, créé la veille par le formateur depuis [door.cloud](https://door.cloud) (voir [dks-creer-cluster.md](dks-creer-cluster.md) et [prerequis-kubernetes.md](prerequis-kubernetes.md)). Si vous ne pouvez pas récupérer le kubeconfig, ou si `kubectl` n’atteint pas l’API, suivez **dans l’ordre** les options ci-dessous et prévenez le formateur.

## a) Cluster partagé du formateur + namespace `lab-<prenom>`

Le formateur a un cluster DKS de secours (créé la veille). Il vous remet un **kubeconfig restreint** (RBAC : votre namespace seulement — le Lab 8 explique le mécanisme).

1. Recevez le fichier (clé USB, mail interne, pas un dépôt git).
2. Placez-le sous `~/` comme dans [prerequis-kubernetes.md](prerequis-kubernetes.md) (`chmod 600`, **pas** `/mnt/c` sous WSL).

```bash
export KUBECONFIG=~/.kube/dks-partage.yaml
export NS=lab-<prenom>
kubectl get nodes
kubectl get ns "$NS"
```

`kubectl get nodes` peut être interdit par le RBAC : dans ce cas `kubectl get ns "$NS"` et `kubectl auth can-i -n "$NS" '*' '*'` suffisent pour travailler.

Limites :

- un seul cluster pour plusieurs personnes : **ne créez pas** de namespace hors `lab-<prenom>`, ne touchez pas `kube-system` / `default` ;
- pas de création / suppression de cluster (Lab 1 : suivez la démo formateur) ;
- LoadBalancer et StorageClass se comportent comme sur DKS (c’est le même produit) ;
- le kubeconfig expire : redemandez-le au formateur plutôt que de le copier depuis un voisin.

## b) kind local (Docker du Jour 1)

Si l’API DKS est injoignable (réseau, quota, compte Door en attente) et que **Docker fonctionne** (Jour 1) :

```bash
# macOS / Linux / Ubuntu WSL : Docker doit tourner
command -v kind >/dev/null || {
  # binaire kind : https://kind.sigs.k8s.io/docs/user/quick-start/#installation
  echo "Installez kind, puis relancez."
}

# 1.32.x = même mineure que DKS (digest : https://github.com/kubernetes-sigs/kind/releases) ; v1.37.0 fonctionne aussi
kind create cluster --name formation-test --image kindest/node:v1.32.11
kubectl cluster-info --context kind-formation-test
export NS=lab-<prenom>
kubectl create namespace "$NS"
```

Sous macOS Homebrew : `brew install kind`. Sous Linux / WSL : suivez l’installation officielle kind (binaire GitHub). kind s’appuie sur le **moteur Docker** déjà validé au Jour 1.

Limites **par rapport à DKS** — à avoir en tête en salle :

| Sujet | kind (CNI kindnet, défaut) | DKS |
|-------|----------------------------|-----|
| Service `LoadBalancer` | Reste souvent `Pending` (pas de cloud controller) | Adresse externe réelle |
| NetworkPolicy | Dépend de la version de kind (kindnet seul : **non appliquées** ; kind récent embarque kube-network-policies) — croyez le test `wget -T 3` | Appliquées (Cilium 1.18) |
| StorageClass | `standard` (local-path, `WaitForFirstConsumer`) | `door-ssd` (Trident, `Immediate`) — Lab 7 |
| Nœuds / quota | Un nœud local, disque de votre laptop | Quota projet Door |
| Lab 1 (console Door) | Impossible à rejouer | Objectif du lab |

Le Lab 9 (NetworkPolicy) **ne démontre pas l’isolation** sur ce kind par défaut. Le formateur a un second cluster kind + Cilium pour la démo (voir [test-kubernetes.md](test-kubernetes.md)) ; en plan B stagiaire, suivez l’écran pour le Lab 9.

Suppression :

```bash
kind delete cluster --name formation-test
```

## c) Playground dans le navigateur (dernier recours)

Pas de Docker, pas de kubeconfig DKS : environnement éphémère **dans le navigateur**. Les labs du dépôt se collent à la main ; pas de `check.sh` local, pas de kubeconfig Door.

### Killercoda (recommandé)

Vérifié le 9 septembre 2026 : [killercoda.com](https://killercoda.com) est en ligne. Playgrounds Kubernetes : [killercoda.com/playgrounds/course/kubernetes-playgrounds](https://killercoda.com/playgrounds/course/kubernetes-playgrounds) (environnements kubeadm **1.36** à cette date : 1 nœud 2 Go / 4 Go, 2 nœuds). Scénario playground : [killercoda.com/kubernetes/scenario/playground](https://killercoda.com/kubernetes/scenario/playground).

1. Compte gratuit, ouvrir un playground Kubernetes.
2. Dans le terminal du navigateur :

```bash
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
cd formation-docker-kubernetes
export NS=lab-<prenom>
kubectl get nodes
```

Limites : session courte (ordre de **1 h** en gratuit, davantage en offre payante), pas DKS, pas de console Door, NetworkPolicy / StorageClass / LoadBalancer ≠ produit Door. Suffisant pour Pods, Deployments, Services ClusterIP, ConfigMap/Secret, une partie du debug.

### Play with Kubernetes (déprécié)

Annonce **sur le site** [labs.play-with-k8s.com](https://labs.play-with-k8s.com) : *Play with Kubernetes will be unavailable starting March 1, 2026*. Au 9 septembre 2026 la page d’accueil répond encore (HTTP 200) avec cet avis. **Ne comptez pas dessus** en salle : si la session refuse de démarrer, passez à Killercoda ou au binôme.

## d) Binôme / écran formateur

Travaillez à deux sur le laptop **qui a un kubectl vers DKS ou kind**. Un seul kubeconfig (celui de la personne qui a le cluster). En tout dernier recours, suivez la démo et refaites le soir.
