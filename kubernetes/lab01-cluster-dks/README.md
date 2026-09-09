# Lab 01 — Se connecter au cluster DKS

**Durée estimée :** 45 minutes

## Objectifs

- Se connecter à la console Door et retrouver **votre cluster binôme** `lab-binome-N`.
- Vérifier que l’API est **Public**, télécharger le kubeconfig, configurer `kubectl`.
- Voir les nœuds et les namespaces, créer **votre** namespace `lab-<prenom>`.
- Observer `kube-system` en lecture seule (Cilium, StorageClass) — ne rien modifier.

Vous **ne créez pas** de cluster dans ce lab (quota OpenStack et rôle **Member**). La création est une démo formateur ; l’annexe « Pour aller plus loin » pointe le guide wizard.

## Prérequis

- Compte Door : invitation du formateur acceptée (rôle **Member**).
- `kubectl` installé : voir [docs/prerequis-kubernetes.md](../../docs/prerequis-kubernetes.md). `kubectl version --client` fonctionne.
- Terminal Unix : macOS (Terminal / iTerm), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.

```bash
cd kubernetes/lab01-cluster-dks
```

Le formateur vous indique **N** (1 à 5) : cluster `lab-binome-N`, partagé avec votre binôme. Chacun travaille ensuite dans `lab-<prenom>`.

```bash
export NS=lab-<prenom>
```

Minuscules, sans accent (`lab-marie`, `lab-jean`).

---

## Étape 1 — Connexion console

Ouvrez [https://door.cloud](https://door.cloud) (redirection **Door Authentication**).

Titre **Connect to Door**. Saisissez e-mail + mot de passe, bouton **Continue**.

![Connexion](../../docs/img/dks/01-login.png)

**Résultat attendu :** tableau de bord **Welcome to Door**. Sidebar **Clusters** (sous **INFRASTRUCTURE**) et **IAM** (sous **SECURITY**).

![Accueil console](../../docs/img/dks/02-console-home.png)

---

## Étape 2 — Trouver `lab-binome-N`

Sidebar **Clusters** (`/dks/clusters`). Titre **Clusters**, sous-titre **Manage and monitor your Kubernetes clusters**.

![Liste des clusters](../../docs/img/dks/03-clusters-list.png)

Cliquez le **nom** de **votre** cluster `lab-binome-N` (pas **New Cluster**, pas le menu **…** / **Delete**). Statut attendu : **Ready** (ou attendez si **Provisioning** : 7–9 min).

Onglet **Overview** : version **v1.32.x**, zone **abidjan**.

![Overview](../../docs/img/dks/07-cluster-detail-overview.png)

Onglet **Nodes** : un pool, **1 replicas** et **c5.xlarge**. Ne touchez pas **+ Add node pool**.

![Nodes](../../docs/img/dks/08-cluster-nodes.png)

---

## Étape 3 — **Access & kubeconfig**

Onglet **Access & kubeconfig**.

1. Carte **Cluster Access** : toggle sur **Public** (pas **Private**). Si vous voyez **Private**, **appelez le formateur** — ne cliquez pas le toggle.
2. Carte **Static kubeconfig (for CI)** → **Download kubeconfig**. N’utilisez pas **Install the CLI** pour ce lab.
3. Ne cliquez pas **Delete** (onglet **Settings** / **Danger zone**).

![Public et Download kubeconfig](../../docs/img/dks/09-access-kubeconfig.png)

**Résultat attendu :** un fichier YAML `{nom}-kubeconfig.yaml` dans Téléchargements.

---

## Étape 4 — Configurer `kubectl`

Détails : [docs/dks-kubeconfig.md](../../docs/dks-kubeconfig.md).

> **macOS / Linux**
>
> ```bash
> mkdir -p ~/.kube
> mv ~/Downloads/*-kubeconfig.yaml ~/.kube/dks-lab.yaml
> chmod 600 ~/.kube/dks-lab.yaml
> export KUBECONFIG=~/.kube/dks-lab.yaml
> ```
>
> Adaptez le `mv` si le fichier n’est pas dans `~/Downloads`.

> **Windows (WSL)**
>
> Dans **Ubuntu**, pas PowerShell. Le téléchargement Windows est sous `/mnt/c/Users/<vous>/Downloads` :
>
> ```bash
> mkdir -p ~/.kube
> mv /mnt/c/Users/<vous>/Downloads/*-kubeconfig.yaml ~/.kube/dks-lab.yaml
> chmod 600 ~/.kube/dks-lab.yaml
> export KUBECONFIG=~/.kube/dks-lab.yaml
> ```
>
> Remplacez `<vous>` par votre profil Windows. Clonez ce dépôt dans `~/` (Linux), pas sous `/mnt/c`.

Vérifier le contexte :

```bash
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
kubectl version
```

**Résultat attendu :** `cluster-info` répond (pas de timeout). Au moins un nœud **Ready**. `kubectl version` : **Server Version: v1.32.x** sur DKS.

Si ça timeout : cluster **Private** ou mauvais fichier → [dks-kubeconfig.md](../../docs/dks-kubeconfig.md) § Dépannage.

---

## Étape 5 — Namespaces et le vôtre

```bash
kubectl get ns
kubectl create ns "$NS"
kubectl config set-context --current --namespace="$NS"
kubectl config view --minify | grep namespace
```

**Résultat attendu :** `kubectl create ns` affiche `namespace/lab-<prenom> created` (ou `AlreadyExists` si vous recommencez). Le contexte courant a `namespace: lab-<prenom>`.

Ne créez pas de namespace dans `kube-system`. Ne supprimez pas `default`.

---

## Étape 6 — `kube-system` en lecture seule

```bash
kubectl get pods -n kube-system
```

Regardez, **ne `delete` / `edit` / `scale` rien**.

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Résultat attendu (DKS) :** des pods **cilium-…** (CNI **Cilium**). L’absence de `kube-proxy` est normale si Cilium le remplace.

Sur un kind local (plan B), vous verrez **kindnet**, pas Cilium : ce n’est pas le cluster de salle.

---

## Étape 7 — StorageClass

```bash
kubectl get sc
```

**Résultat attendu (DKS) :** **`door-ssd`** marquée **`(default)`**. **`door-file`** peut apparaître (RWX). Un PVC sans classe prendra `door-ssd` (lab stockage). Les classes peuvent arriver **1–3 minutes** après le cluster **Ready**.

---

## Pièges

- **Create Cluster** / **New Cluster** : réservé au formateur (rôle **Super Admin** + quota). Un **Member** ne peut pas créer.
- **Private** : `kubectl` depuis le Wi‑Fi de la salle ne joindra pas l’API.
- **Mauvais cluster** : `lab-binome-3` au lieu du vôtre. Vérifiez le nom dans **Overview**.
- **`KUBECONFIG` oublié** : nouveau terminal → `export` à refaire, ou fusionnez dans `~/.kube/config` (voir le doc kubeconfig).
- **x509** : mauvais YAML ou fichier incomplet ; re-télécharger, `chmod 600`.
- **Unauthorized** : re-télécharger **Download kubeconfig**.
- **PowerShell** : chemins et quotes cassés. WSL Ubuntu ou Git Bash.
- **Settings → Danger zone → Delete** : détruit le cluster du binôme. Interdit.

![Danger zone — ne pas cliquer Delete](../../docs/img/dks/10-settings-danger-zone.png)

---

## Nettoyage

Rien à détruire sur le cluster partagé. Gardez `$NS` pour les labs suivants.

Le kubeconfig reste sur **votre** disque (`chmod 600`). Ne le commitez pas (`kubeconfig*` est dans `.gitignore`).

Vérification automatique (non interactif) :

```bash
export NS=lab-<prenom>
./check.sh
```

`check.sh` utilise le **contexte kubectl courant** (et `KUBECONFIG` s’il est exporté). Il crée `$NS` s’il n’existe pas encore.

---

## Pour aller plus loin

Créer **votre** cluster (après la formation, ou si le formateur vous y autorise) : suivez [docs/dks-creer-cluster.md](../../docs/dks-creer-cluster.md).

Règles de taille **non négociables** tant que le quota de salle est tendu :

- **Replicas** = **1**
- **Machine type** = **c5.xlarge** (*Recommended*) — 1 seul worker
- **Zone** = **Abidjan**
- API **Public**
- **Au plus 4** créations en même temps ; compter **7–9 min**
- Rôle **Super Admin** obligatoire pour **Create Cluster**

Sans ça, la création échoue ou sature les instances. En séance, restez sur `lab-binome-N`.
