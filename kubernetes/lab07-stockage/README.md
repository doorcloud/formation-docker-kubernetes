# Lab 07 — Volumes emptyDir et PVC dynamique

**Durée estimée :** 30 minutes

## Objectifs

- Partager un répertoire entre **deux conteneurs du même Pod** (`emptyDir`).
- Constater qu’`emptyDir` **meurt avec le Pod**.
- Déclarer un PVC **1 Gi**, `ReadWriteOnce`, **sans** `storageClassName` (classe **par défaut** du cluster).
- Écrire `/data/hello.txt`, supprimer le Pod, le recréer, **retrouver le fichier**.
- Lire `kubectl describe pvc`, `kubectl get pv`, la *reclaim policy* et le `volumeBindingMode` (`Immediate` sur DKS, `WaitForFirstConsumer` sur kind).

## Prérequis

- `kubectl get nodes` OK.
- Lab 03 (namespace + Pod). Terminal bash/zsh ; **Windows = WSL ou Git Bash**.
- Image : `ghcr.io/doorcloud/formation/busybox:1.36`.

```bash
cd kubernetes/lab07-stockage
export NS=lab-<prenom>
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
```

> **macOS / Linux / WSL**
> Même kubeconfig que les labs précédents (`~/.kube/config` **dans** WSL sous Windows). Collez les blocs multi-lignes d’un coup dans le terminal Unix, pas dans PowerShell.

---

## Étape 1 — Quelle StorageClass par défaut ?

```bash
kubectl get storageclass
```

**Résultat attendu :** une ligne porte le marqueur `(default)`. C’est celle-là qu’un PVC **sans** `storageClassName` utilisera.

| Cluster | Nom typique | Provisioner |
|---|---|---|
| kind (entraînement) | `standard` | `rancher.io/local-path` |
| DKS (salle) | `door-ssd` (défaut) | CSI NetApp Trident 25.02 (`ontap-san`, bloc, RWO) ; `door-file` = `ontap-nas` (fichier, RWX) |

Ne copiez **pas** le nom dans le manifeste : laissez le cluster choisir. Si plusieurs classes existent (`door-file` en NFS/RWX sur DKS, etc.), seul le `(default)` est utilisé ici.

Repérez aussi **`VOLUMEBINDINGMODE`** et **`RECLAIMPOLICY`** :

- `WaitForFirstConsumer` : le PVC reste `Pending` **tant qu’aucun Pod** ne le monte (le scheduler choisit le nœud d’abord). Ce n’est **pas** un échec.
- `Immediate` : le volume est provisionné tout de suite (sur un stockage réseau comme Trident, le nœud n’a pas d’importance).
- `Delete` : supprimer le PVC supprime (en général) le PV. `Retain` : le PV passe `Released` et garde les données.

Sur kind d’entraînement : `standard` + `WaitForFirstConsumer` + `Delete`. Sur DKS (vérifié 09/09/2026) : `door-ssd` + **`Immediate`** + `Delete`, `ALLOWVOLUMEEXPANSION true`.

---

## Étape 2 — `emptyDir` partagé (2 conteneurs)

```bash
kubectl apply -n "$NS" -f pod-emptydir.yaml
kubectl wait --for=condition=Ready pod/partage -n "$NS" --timeout=120s
kubectl exec -n "$NS" partage -c redacteur -- sh -c 'echo bonjour-emptydir > /data/hello.txt'
kubectl exec -n "$NS" partage -c lecteur -- cat /data/hello.txt
```

**Résultat attendu :** `bonjour-emptydir`. Les deux conteneurs voient le **même** répertoire `/data` (volume `emptyDir` du Pod).

Recréez le Pod :

```bash
kubectl delete pod partage -n "$NS" --wait=true
kubectl apply -n "$NS" -f pod-emptydir.yaml
kubectl wait --for=condition=Ready pod/partage -n "$NS" --timeout=120s
kubectl exec -n "$NS" partage -c lecteur -- cat /data/hello.txt
```

**Résultat attendu :** `No such file or directory`. `emptyDir` vit en RAM/disque **du nœud**, le temps du Pod uniquement. (Même idée que le `tmpfs` / volume anonyme Docker du lab 04.)

---

## Étape 3 — PVC 1 Gi RWO, puis Pod

Le manifeste `pvc.yaml` **n’a pas** de champ `storageClassName`.

```bash
kubectl apply -n "$NS" -f pvc.yaml
kubectl get pvc donnees -n "$NS"
kubectl describe pvc donnees -n "$NS"
```

**Résultat attendu sur DKS (`door-ssd`, `Immediate`) :** `Bound` en quelques secondes, un PV `pvc-…` apparaît dans `kubectl get pv`. **Sur kind (`WaitForFirstConsumer`) :** `Pending`, événement *waiting for first consumer* — normal, **n’attendez pas** Bound ici. Un PVC `Pending` **sur DKS** signale au contraire que le CSI Trident n’est pas encore prêt (cluster trop neuf : prévenez le formateur).

```bash
kubectl apply -n "$NS" -f pod-pvc.yaml
kubectl wait --for=condition=Ready pod/persistant -n "$NS" --timeout=120s
kubectl get pvc donnees -n "$NS"
kubectl get pv
kubectl describe pvc donnees -n "$NS"
```

**Résultat attendu :** PVC `Bound` ; un PV `pvc-<uuid>` apparaît, `CLAIM` = `$NS/donnees`. `describe` montre la classe choisie (ex. `standard` ou `door-ssd`), le mode `RWO`, la taille `1Gi`.

> **Sur kind (un nœud)**
> `ReadWriteOnce` suffit : un seul nœud peut monter le volume. Un `nodePort` / un second nœud n’est pas nécessaire.
>
> **Sur DKS**
> Le provisionnement CSI peut prendre **1–3 minutes** après le premier consommateur. Gardez `--timeout=120s` ; si ça dépasse, relancez `describe pvc` et attendez les events `ProvisioningSucceeded`.

---

## Étape 4 — Écrire, détruire le Pod, relire

```bash
kubectl exec -n "$NS" persistant -- sh -c 'echo bonjour-pvc > /data/hello.txt'
kubectl exec -n "$NS" persistant -- cat /data/hello.txt
kubectl delete pod persistant -n "$NS" --wait=true
kubectl apply -n "$NS" -f pod-pvc.yaml
kubectl wait --for=condition=Ready pod/persistant -n "$NS" --timeout=120s
kubectl exec -n "$NS" persistant -- cat /data/hello.txt
```

**Résultat attendu :** `bonjour-pvc` **toujours là**. Le PVC (et le PV derrière) ont survécu au `delete` du Pod. C’est la différence avec `emptyDir`.

---

## Étape 5 — Reclaim : supprimer le PVC

Notez d’abord le nom du PV :

```bash
PV=$(kubectl get pvc donnees -n "$NS" -o jsonpath='{.spec.volumeName}')
echo "PV=$PV"
kubectl get pv "$PV" -o yaml | grep -E 'reclaimPolicy|phase|storageClassName'
kubectl delete pod persistant -n "$NS" --wait=true
kubectl delete pvc donnees -n "$NS"
kubectl get pv "$PV"
```

**Résultat attendu :**

- reclaim `Delete` : le PV **disparaît** (ou passe brièvement par `Failed` / suppression).
- reclaim `Retain` : le PV reste `Released` ; les données ne sont pas effacées automatiquement (récupération manuelle hors scope).

kind `standard` → `Delete`. Vérifiez sur DKS avec `kubectl get sc` / `kubectl get pv`.

---

## Pièges

- **PVC `Pending` sans Pod** avec `WaitForFirstConsumer` (kind) : comportement **normal**, pas une StorageClass cassée. Avec `Immediate` (DKS) : `Pending` = CSI pas prêt, lisez `kubectl describe pvc`.
- **Forcer `storageClassName: standard`** dans le YAML casse le lab sur DKS (la classe ne s’appelle pas `standard`). Laissez le champ absent.
- **`hostPath`** : hors sujet ici, et souvent **interdit** (PSA / politiques cluster). Ne l’utilisez pas en salle.
- **RWO vs RWX** : un volume RWO n’est pas partageable entre deux nœuds. Deux Pods sur le même nœud peuvent parfois le monter ; ne comptez pas dessus. Un seul Pod dans ce lab.
- **Quota** : un PVC 20 Gi (ancien lab WordPress) peut être refusé. Ici **1 Gi**.
- **`readOnlyRootFilesystem`** : l’écriture se fait sur le **volume** `/data`, pas sur la racine du conteneur.
- **`Permission denied` sur `/data` en non-root** : `fsGroup` n’est appliqué par le kubelet que si le pilote CSI le permet (`fsGroupPolicy`) **et** que le PV déclare un `fsType`. Sur DKS (`door-ssd`, Trident, PV sans `fsType`) ce n’est pas le cas : le volume arrive `root:root`. D’où l’`initContainer` **root** `chown-data` dans `pod-pvc.yaml`, qui donne le dossier à l’utilisateur 65534 avant le conteneur principal. Sur kind (`local-path`, dossier 0777) il ne sert à rien, mais ne gêne pas.

## Nettoyage

```bash
kubectl delete pod partage persistant -n "$NS" --ignore-not-found
kubectl delete pvc donnees -n "$NS" --ignore-not-found
```

Le PV associé part tout seul si la reclaim policy est `Delete`.

Vérification automatique :

```bash
./check.sh
```

## Pour aller plus loin

- `emptyDir.medium: Memory` : emptyDir en tmpfs (RAM du nœud).
- StatefulSet + `volumeClaimTemplates` : un PVC **par** replica (piste bonus, pas de lab dans ce dépôt).
- `kubectl get sc -o yaml` : `allowVolumeExpansion`, `mountOptions`, paramètres CSI (noms variables selon le cloud — lisez le cluster, ne mémorisez pas GKE/EBS).
