# Formation Docker & Kubernetes sur Door (DKS) — Cloudoor

[![CI](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/ci.yml/badge.svg)](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/ci.yml)
[![Windows client](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/windows-client.yml/badge.svg)](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/windows-client.yml)
[![Kubernetes labs](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/k8s-labs.yml/badge.svg)](https://github.com/doorcloud/formation-docker-kubernetes/actions/workflows/k8s-labs.yml)

Matériel de la formation **Docker & Kubernetes** animée par **Cloudoor**, autour du produit **Door** et du service **DKS** (Door Kubernetes Service). Console : [door.cloud](https://door.cloud) · documentation : [docs.cloudoor.com](https://docs.cloudoor.com).

## Présentation (3 jours)

| Jour | Thème |
|------|--------|
| **J1** | Docker : concepts, images, réseau, volumes, sécurité, debug, Compose — 7 labs dans ce dépôt |
| **J2** | Kubernetes sur DKS : cluster Door, architecture, workloads, config, réseau |
| **J3** | Kubernetes sur DKS (suite) : stockage, debug, RBAC, NetworkPolicy, Helm 4 |

Index des labs Kubernetes (J2–J3) : **[kubernetes/README.md](kubernetes/README.md)**. Prérequis kubectl / Helm : **[docs/prerequis-kubernetes.md](docs/prerequis-kubernetes.md)**. Création du cluster : **[docs/dks-creer-cluster.md](docs/dks-creer-cluster.md)**.

## Prérequis : votre laptop

Vous travaillez **sur votre propre machine** (macOS, Windows 10/11 ou Linux). Aucune machine virtuelle n’est fournie aux stagiaires.

1. Suivre **[docs/prerequis-installation.md](docs/prerequis-installation.md)** (à faire **avant** le matin du Jour 1).
2. Vérifier Docker :

```bash
docker run hello-world
```

Le message `Hello from Docker!` doit s’afficher. Puis :

```bash
docker compose version
git --version
```

Si vous n’avez pas les droits administrateur sur votre poste, lisez **[docs/plan-b.md](docs/plan-b.md)** et prévenez le formateur.

## Structure du dépôt

```
docker/lab01-cli/ … lab07-compose/     Labs Docker du Jour 1
kubernetes/lab01-cluster-dks/ … lab10  Labs Kubernetes des Jours 2–3
docs/                                  Prérequis Docker et Kubernetes, plan B, tests
scripts/                               check-all, k8s-check-all, cleanup, prepull
infra/digitalocean/                    VMs de test / secours (formateur uniquement)
.github/workflows/                     CI Linux, kind (labs K8s), hygiène Windows
```

## Convention des labs

Chaque répertoire `docker/labNN-…/` contient :

- un `README.md` (objectif, durée, étapes numérotées, résultat attendu, nettoyage) ;
- les fichiers de l’exercice (Dockerfile, Compose, etc.) ;
- un `check.sh` qui **retourne 0 si le lab est réussi**, et une valeur non nulle sinon.

Les commandes des labs se tapent dans un terminal **Unix** : Terminal macOS, **Ubuntu (WSL)** ou Git Bash sous Windows, shell Linux. Pas PowerShell, pas `cmd.exe`.

Côté Kubernetes : `export NS=lab-<prenom>` puis `-n "$NS"` partout ; kubeconfig dans `~/.kube/config` ou `export KUBECONFIG=…` (sous WSL : fichier sous `~/`, pas `/mnt/c`). Détail : [kubernetes/README.md](kubernetes/README.md).

Lancer le contrôle d’un lab :

```bash
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
cd formation-docker-kubernetes
bash docker/lab01-cli/check.sh
```

Lancer tous les contrôles (depuis la racine du dépôt) :

```bash
bash scripts/check-all.sh
```

Le script affiche un tableau PASS/FAIL et se termine par un code non nul si au moins un lab échoue. Il est utilisable sur macOS comme sur Linux.

Contrôles Kubernetes (Labs 2–10, ignore le Lab 1 manuel) :

```bash
bash scripts/k8s-check-all.sh
```

## Labs Docker (Jour 1)

| Lab | Dossier | Durée | Objectif |
|-----|---------|-------|----------|
| Lab 01 — Docker CLI | `docker/lab01-cli` | 30 min | Vérifier l’installation, lancer `hello-world`, lister images et conteneurs, exposer Nginx (`nginx:1.27-alpine`) sur un port hôte, inspecter / logs, arrêter et supprimer proprement. |
| Lab 02 — Build et publication | `docker/lab02-build` | 40 min | Construire une application (image volontairement lourde puis image optimisée), comparer taille et `docker history`, publier vers un registry **local** (`registry:2`) : tag, push, `curl` sur `/v2/_catalog`. |
| Lab 03 — Réseau | `docker/lab03-networking` | 30 min | Créer deux réseaux bridge utilisateur (`app-net`, `isolated-net`), placer Redis (`redis:7-alpine`) dans l’un, vérifier le DNS interne Docker depuis un client du même réseau, constater l’isolation depuis l’autre réseau. |
| Lab 04 — Volumes | `docker/lab04-volumes` | 30 min | Créer un volume nommé `db-data`, démarrer PostgreSQL (`postgres:16`) avec ce volume, créer une base, recréer le conteneur et vérifier la persistance, puis nettoyer. |
| Lab 05 — Sécurité | `docker/lab05-security` | 40 min | Illustrer namespaces, capabilities (`--cap-drop ALL`), profil Seccomp et AppArmor `docker-default`. Sous Docker Desktop, l’étape AppArmor est **informative** (voir [différences](docs/differences-docker-desktop.md)). |
| Lab 06 — Debug | `docker/lab06-debug` | 30 min | Identifier un conteneur sain, un crash (`exit 1`) et un OOMKilled, lire les logs, `docker stats`, `inspect`, `top`, `events`. |
| Lab 07 — Compose | `docker/lab07-compose` | 40 min | Orchestrer MySQL (`mysql:8.4`), PHP (`php:8.3-fpm`) et Nginx (`nginx:1.27-alpine`) avec `docker compose` (plugin v2, sans clé `version:`), healthcheck MySQL, réseau isolé, page d’application. |

Images **toujours taguées** (jamais `:latest`, sauf l’image pédagogique `hello-world`). Les mots de passe d’exemple restent dans `.env.example` : copiez-les vers `.env` (fichier ignoré par git).

## Labs Kubernetes (Jours 2–3)

Cluster pédagogique : **DKS**, créé depuis [door.cloud](https://door.cloud) (Lab 1). Prérequis poste : **[docs/prerequis-kubernetes.md](docs/prerequis-kubernetes.md)** (`kubectl`, Helm 4, compte Door). Index détaillé (10 labs, durées, conventions `NS` / kubeconfig / `check.sh`) : **[kubernetes/README.md](kubernetes/README.md)**.

| Jour | Agenda |
|------|--------|
| **J2** | Lab 1 (console Door, kubeconfig) · intro / architecture · découverte du cluster · namespace et Pod · Deployment + Service + DNS · ConfigMap / Secret · réseau (Cilium, Services, Gateway API) |
| **J3** | Stockage (PVC, StorageClass DKS) · debug · RBAC / PSA · NetworkPolicy · Helm 4 (chart local, upgrade / rollback, `port-forward`) · suppression du cluster |

Pas de cluster DKS ou API injoignable : **[docs/plan-b-kubernetes.md](docs/plan-b-kubernetes.md)**. Comment les labs sont testés (formateur) : **[docs/test-kubernetes.md](docs/test-kubernetes.md)**.

## Docker Desktop (macOS / Windows)

Les labs sont écrits pour un moteur Linux. Sur Docker Desktop, quelques comportements diffèrent (AppArmor, `--pid=host`, `--network host`, RAM, bind mounts, port 5000 macOS). Tableau et impact par lab : **[docs/differences-docker-desktop.md](docs/differences-docker-desktop.md)**.

## Plan B (poste verrouillé)

Pas de droits admin, installation impossible, ou Docker qui refuse de démarrer : **[docs/plan-b.md](docs/plan-b.md)** (Play with Docker, binôme, VM de secours gérée par le formateur).

## Nettoyage global

En fin de journée, ou entre deux labs si l’environnement est encombré :

```bash
bash scripts/cleanup-all.sh
```

Le script supprime **uniquement** les conteneurs, réseaux et volumes **nommés** par les labs, puis fait un `docker compose down -v` sur le lab 07. Il n’exécute **jamais** `docker system prune -a`.

Namespaces Kubernetes `lab-*` (liste + confirmation ; jamais `default` ni `kube-*`) :

```bash
bash scripts/k8s-cleanup-all.sh
```

La veille, sur une bonne connexion (et après `docker login`) :

```bash
bash scripts/prepull.sh
```

## Licence

[MIT](LICENSE) — Copyright 2026 Cloudoor.

## Support

Questions sur la formation ou sur Door : **support@door.cloud**.

**Dépôt public : ne commitez jamais de secret** (mots de passe, clés SSH, fichiers `.env`, `kubeconfig`, certificats). Les valeurs d’exercice sont des exemples (`ChangeMe-lab`) ou sont générées localement.
