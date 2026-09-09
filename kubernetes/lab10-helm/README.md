# Lab 10 — Déployer avec Helm 4

**Durée estimée :** 30 minutes

## Objectifs

- Distinguer chart, valeurs (`values.yaml` / `--set`) et **release**.
- Valider un chart local : `helm lint`, `helm template`.
- Installer, lister, mettre à jour, historiser, **rollback**, désinstaller.
- Lire le site via `kubectl port-forward` (pas d'Ingress NGINX : le chart SIG est **retiré** depuis mars 2026).
- Repérer ce qui change vraiment entre Helm **3** et Helm **4**.

## Prérequis

- `kubectl` configuré : `kubectl get nodes` OK.
- **Helm 4** : `helm version` affiche `v4.x` (ex. `v4.2.3`). Helm 3 installe encore ce chart (`apiVersion: v2`) mais les flags et le défaut Server-Side Apply diffèrent.
- Terminal : macOS (Terminal / iTerm, zsh ou bash), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.
- Image : `nginx:1.27-alpine` (tag figé).

Depuis la racine du dépôt cloné :

```bash
cd kubernetes/lab10-helm
export NS=lab-<prenom>
kubectl create namespace "$NS"
helm version
```

Remplacez `<prenom>` par le vôtre **en minuscules, sans accent**. Toujours `-n "$NS"` : un `helm install` sans `-n` irait dans `default`.

> **macOS / Windows WSL / Linux**  
> `helm` et `kubectl` doivent être les binaires **Linux** sous WSL (pas ceux de Git-Bash mêlés à Docker Desktop Windows, sauf si vous savez gérer le kubeconfig).  
> Kubeconfig : `export KUBECONFIG="$HOME/.kube/config"`.  
> `port-forward` bloque le terminal : ouvrez un **second** onglet/terminal pour le `curl`.

---

## Helm 4 en une minute (vs Helm 3)

Helm **4.0.0** est sorti le **12 novembre 2025** (KubeCon NA). Les charts `apiVersion: v2` (la grande majorité, dont celui-ci) **continuent de fonctionner**. Ce n'est pas le saut Helm 2 → 3 (plus de Tiller).

Changements réels, d'après les [notes Helm 4](https://helm.sh/docs/overview/) :

| Sujet | Helm 3 | Helm 4 |
|---|---|---|
| Apply Kubernetes | client-side apply | **Server-Side Apply par défaut** pour une **nouvelle** release ; une release née en Helm 3 reste en client-side au `upgrade` / `rollback` (sauf `--server-side`) |
| `--atomic` | rollback auto si l'upgrade échoue | renommé **`--rollback-on-failure`** (l'ancien flag marche encore avec un warning de dépréciation) |
| `--force` | remplace les ressources | **`--force-replace`** (même warning) |
| Post-renderer | chemin d'un exécutable | **plugin** nommé |
| `helm registry login` | URL complète parfois acceptée | **nom de domaine seul** |
| Charts v3 | — | **expérimental** (`HELM_EXPERIMENTAL_CHART_V3=1` + `helm create --chart-api-version=v3`) |
| `--wait` | pods Ready | **kstatus** (il faut le verbe RBAC `watch`) |

`helm fetch` est mort depuis longtemps : utilisez **`helm pull`**. Artifact Hub : `helm search hub`. Le dépôt **Bitnami** public n'est plus un exemple viable (catalogue Docker Hub restreint dès 2025). Le dépôt `https://kubernetes.github.io/ingress-nginx` est **retiré** (fin de maintenance mars 2026) : ne l'ajoutez pas.

---

## Étape 1 — Lire le chart fourni

Le dossier `charts/webapp` a été généré avec `helm create` puis **épuré** : Deployment + Service + ConfigMap (plus d'Ingress, HPA, tests `busybox` non tagué, ni ServiceAccount dédié).

```bash
ls charts/webapp charts/webapp/templates
cat charts/webapp/Chart.yaml
cat charts/webapp/values.yaml
```

**Résultat attendu :** `apiVersion: v2`, `appVersion: "1.27"`, `image.repository: nginx`, `image.tag: 1.27-alpine`, `replicaCount: 1`, `service.type: ClusterIP`, `message: "Bonjour"`. Le ConfigMap rend `message` dans `index.html`.

---

## Étape 2 — `lint` et `template`

```bash
helm lint ./charts/webapp
helm template webapp ./charts/webapp -n "$NS"
```

**Résultat attendu :** `helm lint` termine `0 chart(s) failed`. `helm template` imprime un Deployment, un Service `webapp`, un ConfigMap dont le HTML contient `Bonjour`. Rien n'est encore créé dans le cluster.

Pour envoyer le YAML dans un fichier (relecture, `kubectl diff`) :

```bash
helm template webapp ./charts/webapp -n "$NS" > /tmp/webapp-rendu.yaml
```

> **macOS / Linux / WSL**  
> `/tmp/webapp-rendu.yaml` est correct. Évitez un chemin Windows `C:\…` depuis bash WSL.

---

## Étape 3 — Installer la release

Le **nom de release** (`webapp`) n'est pas le namespace. Ici le chart s'appelle aussi `webapp` : le helper `fullname` produit le Service `webapp`.

```bash
helm install webapp ./charts/webapp -n "$NS"
helm list -n "$NS"
kubectl -n "$NS" get deploy,svc,cm,pods
```

**Résultat attendu :** `helm list` montre `webapp` / `deployed` / chart `webapp-0.1.0`. Un pod `webapp-…` `1/1 Running`. `helm install` a affiché les NOTES (port-forward).

Attendez le Deployment :

```bash
kubectl -n "$NS" wait --timeout=120s --for=condition=Available deploy/webapp
```

---

## Étape 4 — Lire la page : `port-forward` + `curl`

Dans **ce** terminal (reste ouvert) :

```bash
kubectl -n "$NS" port-forward svc/webapp 8080:80
```

**Résultat attendu :** `Forwarding from 127.0.0.1:8080 -> 80`.

Dans un **second** terminal :

```bash
export NS=lab-<prenom>
curl -s http://127.0.0.1:8080
```

**Résultat attendu :** HTML avec `<h1>Bonjour</h1>`.

Arrêtez le port-forward avec `Ctrl+C` dans le premier terminal quand vous avez vu la page.

Sans second terminal, un pod `curl` dans le namespace (comme `check.sh`) :

```bash
kubectl -n "$NS" run curl-lab --rm -q -i --restart=Never \
  --image=curlimages/curl:8.10.1 --command -- \
  curl -sf "http://webapp.${NS}.svc"
```

(`-i` sans `-t` : pas de TTY, acceptable sous Git Bash / WSL.)

---

## Étape 5 — `upgrade`, `history`, `get values`

```bash
helm upgrade webapp ./charts/webapp -n "$NS" \
  --set replicaCount=2 \
  --set message='Bonjour Helm'
kubectl -n "$NS" rollout status deploy/webapp --timeout=120s
kubectl -n "$NS" get deploy webapp
helm history webapp -n "$NS"
helm get values webapp -n "$NS"
```

**Résultat attendu :** `READY 2/2`. `helm history` : révision **1** (install) puis **2** (upgrade). `helm get values` montre `replicaCount: 2` et le nouveau `message`. Relancez le `port-forward` + `curl` : le `<h1>` contient `Bonjour Helm` (annotation `checksum/config` : Helm a recréé les pods).

En Helm 4, un échec d'upgrade peut se corriger avec `--rollback-on-failure` (ex-`--atomic`).

---

## Étape 6 — Rollback vers la révision 1

```bash
helm rollback webapp 1 -n "$NS"
kubectl -n "$NS" rollout status deploy/webapp --timeout=120s
kubectl -n "$NS" get deploy webapp
helm history webapp -n "$NS"
```

**Résultat attendu :** `READY 1/1`. Une **révision 3** apparaît (le rollback **ajoute** une révision, il n'efface pas la 2). `curl` revoit `Bonjour`.

---

## Étape 7 — Dépôt public (lecture seule) — pas Bitnami, pas ingress-nginx

Exemple qui répond encore en 2026 : **cert-manager** (Jetstack), en repo HTTP **ou** OCI.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm search repo jetstack/cert-manager
```

**Résultat attendu :** une ligne `jetstack/cert-manager` avec un `CHART VERSION` (ex. `v1.21.1`). **N'installez pas** ce chart sur le cluster de formation.

Équivalent OCI (Helm 3.8+ / Helm 4, pas besoin de `helm repo add`) :

```bash
helm show chart oci://quay.io/jetstack/charts/cert-manager --version v1.21.1
```

Syntaxe générique OCI : `oci://registry-1.docker.io/<org>/<chart>` — encore faut-il un chart **public et maintenu** (évitez Bitnami sur Docker Hub).

---

## Étape 8 — Uninstall

```bash
helm uninstall webapp -n "$NS"
helm list -n "$NS"
kubectl -n "$NS" get deploy,svc
```

**Résultat attendu :** plus de release `webapp`. Deployment / Service / ConfigMap du chart disparus. Le **namespace** `$NS` existe encore (Helm ne le supprime pas).

---

## Pièges

- **Oublier `-n "$NS"`** : release dans `default`, collision avec un voisin, RBAC refusé sur cluster partagé.
- **`--set` vs `values.yaml`.** `--set` gagne pour cette commande ; `helm get values` sans `--all` ne montre que les overrides. `helm get values -a` affiche aussi les défauts du chart.
- **`helm upgrade` n'est pas `kubectl scale`.** Si vous scalez à la main, le prochain `upgrade` ramène `replicaCount` du chart / `--set`.
- **Ingress NGINX SIG** : ne plus `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`. Pour exposer : `port-forward` (ce lab), Service `LoadBalancer` sur DKS, ou Gateway API si le formateur le démontre.
- **Bitnami** : ne plus `helm repo add bitnami https://charts.bitnami.com/bitnami` comme dans l'ancien cours.
- **Helm 4 `--wait`** : si un compte de service CI n'a pas `watch`, `--wait` échoue tout de suite. Ici on utilise plutôt `kubectl wait` / `rollout status`.
- Image `nginx:1.27-alpine` : processus **root** (port 80). `runAsNonRoot` casserait le conteneur ; d'où `allowPrivilegeEscalation: false` seulement.

## Nettoyage

```bash
helm uninstall webapp -n "$NS" 2>/dev/null || true
kubectl delete namespace "$NS"
```

Vérification automatique (namespace éphémère, lint → install → curl interne → upgrade 2 replicas → rollback → uninstall) :

```bash
./check.sh
```

## Pour aller plus loin

- `helm create monchart` puis supprimer Ingress / HPA comme ici.
- `helm pull oci://quay.io/jetstack/charts/cert-manager --version v1.21.1` (inspecter un chart sans l'installer).
- Dépendances : dossier `charts/` + `Chart.yaml` `dependencies:` ; `helm dependency update`.
- `helm rollback webapp 0` n'existe pas : il faut le **numéro** vu dans `helm history`.
