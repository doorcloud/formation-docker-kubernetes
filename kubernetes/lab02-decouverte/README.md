# Lab 02 — Découvrir le cluster

**Durée estimée :** 20 minutes

## Objectifs

- Vérifier le contexte `kubectl` (kubeconfig) et l’accès à l’API.
- Lister les nœuds, la version client/serveur, les namespaces et les *api-resources*.
- Observer `kube-system` en **lecture seule** : CoreDNS et le CNI (ne rien modifier).
- Identifier la StorageClass par défaut.
- Lire le schéma d’un Pod via `kubectl explain` (sans YAML à écrire encore).

## Prérequis

- Lab 01 terminé : `kubectl get nodes` répond (au moins un nœud **Ready**).
- Terminal : macOS (Terminal / iTerm, zsh ou bash), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.
- `export NS=lab-<prenom>` (minuscules, sans accent). Ce lab est surtout cluster-wide : vous **n’appliquez rien** dans `kube-system` ni dans `default`.

```bash
export NS=lab-<prenom>
kubectl get nodes
```

Depuis la racine du dépôt cloné :

```bash
cd kubernetes/lab02-decouverte
```

> **macOS / Linux**  
> Kubeconfig par défaut : `~/.kube/config`. Si le fichier téléchargé au lab 1 est ailleurs : `export KUBECONFIG=/chemin/vers/votre-kubeconfig.yaml`. Vérifiez avec `kubectl config current-context`.

> **Windows (WSL)**  
> Lancez `kubectl` **dans WSL**, pas dans PowerShell. Placez le kubeconfig dans le système de fichiers Linux (`~/.kube/config`), pas sous `/mnt/c` si possible. Même variable : `export KUBECONFIG=$HOME/.kube/config`.

---

## Étape 1 — Contexte et cluster-info

```bash
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
```

**Résultat attendu :** un contexte marqué `*` (le courant). `cluster-info` affiche l’URL du *control plane* et le service CoreDNS (proxy API). L’URL dépend du cluster (kind en local ≠ API publique DKS) : ne la copiez pas dans un chat / un ticket.

---

## Étape 2 — Nœuds et version

```bash
kubectl get nodes -o wide
kubectl version
```

**Résultat attendu :** au moins une ligne **Ready**. `-o wide` ajoute INTERNAL-IP, OS-IMAGE, KERNEL-VERSION, CONTAINER-RUNTIME (souvent `containerd`).

`kubectl version` montre le client **et** le serveur. Ne plus utiliser `--short` (flag retiré). L’écart client/serveur autorisé est d’**une mineure** : sur DKS (serveur **v1.32.4**) visez un client 1.31–1.33 ; un client plus récent (1.37) fonctionne pour les labs mais affiche un avertissement de skew.

---

## Étape 3 — Ressources nommées ou non

Une ressource *namespaced* vit dans un namespace (Pod, Deployment, Secret). Une ressource cluster-wide n’en a pas (Node, Namespace, PersistentVolume, StorageClass).

```bash
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

**Résultat attendu :** `pods` dans la première liste ; `nodes`, `namespaces`, `persistentvolumes`, `storageclasses` dans la seconde. `endpointslices` est namespaced (vue des backends d’un Service, lab 4).

---

## Étape 4 — Namespaces

```bash
kubectl get ns
```

**Résultat attendu :** au minimum `default`, `kube-system`, `kube-public`, `kube-node-lease`. Ne créez pas encore `$NS` : ce sera le lab 3. Ne travaillez **jamais** dans `kube-system` ni dans un namespace qui n’est pas le vôtre.

---

## Étape 5 — `kube-system` en lecture seule (CNI + CoreDNS)

```bash
kubectl get pods -n kube-system
```

**Résultat attendu :** des pods **Running**, dont :

| Vous voyez… | Signification |
|---|---|
| `coredns-…` | DNS du cluster (lab 4 : `web-svc.$NS.svc.cluster.local`) |
| `kindnet-…` | CNI de **kind** (lab local) |
| `cilium-…` / `cilium-operator-…` | CNI de **DKS** (eBPF). Hubble peut être présent |
| `kube-proxy-…` | Present sur kind. Sur DKS, Cilium **remplace** souvent kube-proxy : l’absence n’est pas une panne |

Regardez, ne `delete` / `edit` / `scale` **rien** ici. Un faux pas casse le DNS ou le réseau de tout le cluster (surtout en salle partagée).

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

**Résultat attendu :** les pods CoreDNS `1/1 Running`.

---

## Étape 6 — StorageClass par défaut

```bash
kubectl get sc
```

**Résultat attendu :** une classe marquée `(default)`.

- **kind** (ce lab testé ainsi) : souvent `standard`, provisioner `rancher.io/local-path`.
- **DKS** : `door-ssd` (RWO, iSCSI) en défaut ; `door-file` (RWX, NFS) peut coexister. Un PVC **sans** `storageClassName` prend le défaut (lab 7).

S’il n’y a **aucune** classe par défaut, notez-le : les PVC dynamiques attendront. Ce n’est pas bloquant pour les labs 3–5 (pas de disque).

---

## Étape 7 — `explain` : le schéma d’un Pod

```bash
kubectl explain pod.spec
kubectl explain pod.spec.containers
```

**Résultat attendu :** de la documentation générée depuis l’API du **serveur** (pas un wiki figé). Repérez `containers`, `volumes`, `restartPolicy`, `nodeSelector`. Au lab 3 vous écrirez un vrai Pod.

---

## Pièges

- **Mauvais contexte** : `current-context` pointe vers un autre cluster. Toujours `get-contexts` avant un `apply`. Pour forcer : `kubectl --context <nom> …`.
- **`--short`** sur `kubectl version` : erreur « unknown flag ». Utilisez `kubectl version` ou `kubectl version --client`.
- **`kube-system`** : lecture seule. Pas de `kubectl delete pod -n kube-system …` « pour voir ».
- **NetworkPolicy** : n’appliquez pas de politique réseau dans ce lab (et pas sur kind « vanilla » : kindnet **n’applique pas** les NetworkPolicy). Cilium / lab 9.
- **Windows** : PowerShell casse les quotes et les heredocs. WSL Ubuntu ou Git Bash.

> **macOS / Linux / WSL**  
> Copier-coller multi-lignes : une commande par bloc `bash`, pas de `\` final oublié. Si `KUBECONFIG` contient plusieurs fichiers séparés par `:` (macOS/Linux) ou `;` (Windows natif), le **premier** gagne pour le contexte courant.

## Nettoyage

Rien à supprimer : vous n’avez rien créé. Le namespace `$NS` arrive au lab 3.

```bash
# pas de delete
```

Vérification automatique (non interactif, crée un namespace jetable puis le supprime) :

```bash
./check.sh
```

## Pour aller plus loin

- `kubectl api-versions` : groupes/versions servis (`apps/v1`, `discovery.k8s.io/v1`, …).
- `kubectl explain pod.spec --recursive | less` : arbre complet des champs.
- Label `storageclass.kubernetes.io/is-default-class=true` : c’est une **annotation**, pas un champ `spec`.
