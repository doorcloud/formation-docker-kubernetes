# Labs Kubernetes (Jours 2 et 3)

Parcours **Kubernetes sur DKS** (Door Kubernetes Service), dans le même dépôt que le Jour 1 Docker. Cluster pédagogique : un cluster DKS **par binôme** (`lab-binome-1` … `lab-binome-5`), créé **la veille par le formateur** depuis la console [door.cloud](https://door.cloud) ; au Lab 1 vous récupérez son kubeconfig et créez votre namespace `lab-<prenom>`. Mode d’exposition **public** : sans cela, l’API n’est pas joignable depuis un laptop.

Les commandes se tapent dans un terminal **Unix** : Terminal macOS, **Ubuntu (WSL)** ou Git Bash, shell Linux. Pas PowerShell, pas `cmd.exe`.

## Les 10 labs

| Dossier | Titre | Durée |
|---------|-------|-------|
| `lab01-cluster-dks` | Retrouver son cluster binôme dans la console Door, télécharger le kubeconfig (API **Public**), `kubectl get nodes`, créer `lab-<prenom>` | 45 min |
| `lab02-decouverte` | Découvrir le cluster : api-resources, namespaces, kube-system (lecture seule), StorageClass, CNI | 20 min |
| `lab03-namespace-pod` | Namespace `lab-<prenom>`, Pod multi-conteneurs, `exec`, `logs` | 25 min |
| `lab04-deployment-service` | Deployment 2 replicas, rolling update/rollback, Service ClusterIP, DNS CoreDNS | 35 min |
| `lab05-configmap-secret` | ConfigMap + Secret en env et en fichier monté | 25 min |
| `lab06-debug` | ImagePullBackOff, CrashLoopBackOff, `describe`, `events`, `logs --previous`, probes | 25 min |
| `lab07-stockage` | PVC dynamique sur la StorageClass par défaut DKS, persistance après recréation du Pod | 30 min |
| `lab08-rbac` | ServiceAccount, Role, RoleBinding, `kubectl auth can-i`, `--as`, SecurityContext, PSA | 30 min |
| `lab09-networkpolicy` | deny-all puis allow frontend→backend (Cilium) | 25 min |
| `lab10-helm` | Chart local, values, `install` / `upgrade` / `rollback`, `port-forward` ; Helm 4 | 30 min |

Chaque répertoire `kubernetes/labNN-…/` contient un `README.md` (source de vérité des commandes), les manifests YAML, et — sauf le Lab 1, **manuel** — un `check.sh`.

Pistes « pour aller plus loin » (pas de dossier dans ce dépôt, évoquées en cours) : StatefulSet, ResourceQuota / LimitRange, exposition externe (Service `LoadBalancer` via kube-vip / Gateway API si disponible sur DKS).

## Conventions

### Namespace

Un namespace par stagiaire, partout :

```bash
export NS=lab-<prenom>
```

Minuscules, sans accent (`lab-marie`, `lab-jean`). Passez `-n "$NS"` à `kubectl`. Ne touchez **jamais** `default`, `kube-system`, ni le namespace d’un autre stagiaire.

### Kubeconfig

Après le Lab 1, `kubectl` doit voir vos nœuds :

```bash
kubectl get nodes
```

Fichier par défaut : `~/.kube/config`. Si vous gardez le fichier téléchargé tel quel :

```bash
export KUBECONFIG=~/Downloads/dks-<cluster>.yaml
```

**Windows (WSL)** : copiez le kubeconfig sous `~/` (home Linux), **pas** sous `/mnt/c`. Puis `chmod 600` sur le fichier. Détails : [docs/prerequis-kubernetes.md](../docs/prerequis-kubernetes.md) et [docs/dks-kubeconfig.md](../docs/dks-kubeconfig.md).

### `check.sh`

À la racine d’un lab (Labs 2–10) :

```bash
export NS=lab-<prenom>
bash kubernetes/lab03-namespace-pod/check.sh
```

Le script retourne **0** si le lab est réussi. Il crée et supprime son namespace de test (variable `NS`, défaut `lab-check-$RANDOM` si vous ne l’exportez pas), respecte `KUBECONFIG` et le contexte courant, et n’est pas interactif.

Tous les labs automatisés, dans l’ordre (ignore le Lab 1) :

```bash
bash scripts/k8s-check-all.sh
```

Tableau PASS/FAIL en fin de course ; code de sortie non nul si au moins un lab échoue.

## Documentation

| Document | Contenu |
|----------|---------|
| [docs/prerequis-kubernetes.md](../docs/prerequis-kubernetes.md) | Installer kubectl et Helm 4, alias `k`, kubeconfig, k9s |
| [docs/dks-creer-cluster.md](../docs/dks-creer-cluster.md) | Créer le cluster DKS dans la console Door (Lab 1) |
| [docs/dks-kubeconfig.md](../docs/dks-kubeconfig.md) | Télécharger le kubeconfig, exposition publique, contextes |
| [docs/plan-b-kubernetes.md](../docs/plan-b-kubernetes.md) | Cluster partagé du formateur, kind local, playground navigateur |
| [docs/test-kubernetes.md](../docs/test-kubernetes.md) | Comment les labs sont testés (kind, DKS, CI) — formateur |

Pas de cluster, ou API injoignable : [plan B](../docs/plan-b-kubernetes.md) et prévenez le formateur.

## Nettoyage

En fin de Jour 3, le **formateur** (Super Admin) supprime les clusters binômes depuis la console : un **Member** ne peut pas le faire. Avant cela, nettoyez vos namespaces `lab-*` :

```bash
bash scripts/k8s-cleanup-all.sh
```

Le script **liste** les namespaces `lab-*`, demande confirmation (sauf `--yes`), et ne touche jamais `default` ni `kube-*`.
