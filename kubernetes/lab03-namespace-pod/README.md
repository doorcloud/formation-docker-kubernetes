# Lab 03 — Namespace et Pod multi-conteneurs

**Durée estimée :** 25 minutes

## Objectifs

- Créer **votre** namespace `lab-<prenom>` (isolation : objets et quota).
- Déployer un Pod à **deux conteneurs** qui partagent le réseau (localhost).
- Lire `describe`, `logs -c`, `get pod -o yaml` et filtrer par label `-l`.
- Entrer dans le sidecar (`exec -c`) et interroger nginx sur `http://localhost:80`.
- Lancer un Pod jetable avec `kubectl run` (et le détruire).

## Prérequis

- Lab 02 : `kubectl get nodes` OK, contexte courant correct.
- Images : `ghcr.io/doorcloud/formation/nginx:1.27-alpine`, `ghcr.io/doorcloud/formation/busybox:1.36` (tags figés, jamais `:latest`).
- Terminal bash / zsh / WSL Ubuntu / Git Bash (pas PowerShell).

```bash
export NS=lab-<prenom>
cd kubernetes/lab03-namespace-pod
```

Remplacez `<prenom>` par le vôtre, minuscules sans accent (`lab-amine`, `lab-fatou`).

---

## Étape 1 — Namespace

```bash
kubectl create namespace "$NS"
kubectl get ns "$NS"
```

**Résultat attendu :** `namespace/lab-<prenom> created` puis une ligne Active. Tous les `kubectl` suivants passent `-n "$NS"`. Le manifeste **n’a pas** `metadata.namespace` : c’est volontaire (vous choisissez le ns au apply).

Si le namespace existe déjà : `AlreadyExists` — continuez, ou `kubectl apply` via dry-run :

```bash
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
```

---

## Étape 2 — Appliquer le Pod

Ouvrez `pod.yaml` : deux conteneurs, labels `app.kubernetes.io/name`, `requests` / `limits` sur **chaque** conteneur (un cluster partagé peut avoir des quotas).

L’image officielle `ghcr.io/doorcloud/formation/nginx:1.27-alpine` écoute en **root** sur le port 80 : on ne met pas `runAsNonRoot` (ça casserait le bind). Le sidecar `ghcr.io/doorcloud/formation/busybox:1.36` fait `sleep 3600` (busybox n’a pas `sleep infinity`).

```bash
kubectl apply -n "$NS" -f pod.yaml
kubectl wait -n "$NS" --for=condition=Ready pod/deux-conteneurs --timeout=120s
kubectl get pod -n "$NS" -o wide
```

**Résultat attendu :** `2/2` Ready, STATUS Running, une IP de Pod. Au premier pull, attendez : depuis Abidjan, Docker Hub descend parfois à quelques dizaines de KiB/s et le kubelet télécharge les images **une par une** — c’est pour cela que les labs utilisent le miroir `ghcr.io` (voir [docs/images-registres.md](../../docs/images-registres.md)). `docker login` ne change rien ici : le pull est fait par le nœud, pas par votre laptop.

---

## Étape 3 — `describe` et labels

```bash
kubectl describe pod deux-conteneurs -n "$NS"
kubectl get pod -n "$NS" -l app.kubernetes.io/name=deux-conteneurs
```

**Résultat attendu :** Events (Scheduled, Pulled, Created, Started ×2). Le `-l` ne montre que ce Pod. Un label mal tapé → liste vide (pas une erreur).

---

## Étape 4 — Logs par conteneur

Sans `-c`, `kubectl logs` refuse s’il y a plusieurs conteneurs (ou prend le premier, selon la version) : soyez explicite.

```bash
kubectl logs deux-conteneurs -c nginx -n "$NS"
kubectl logs deux-conteneurs -c sidecar -n "$NS"
```

**Résultat attendu :** nginx annonce `start worker process`. Le sidecar (sleep) n’écrit presque rien — c’est normal.

---

## Étape 5 — `exec` : wget vers localhost

Les deux conteneurs **partagent la pile réseau** du Pod. Depuis le sidecar, nginx est `localhost:80`.

```bash
kubectl exec -n "$NS" deux-conteneurs -c sidecar -- wget -qO- http://localhost:80
```

**Résultat attendu :** le HTML « Welcome to nginx ». Pas de `-it` ici : `wget` n’est pas un shell.

`exec` sans `-c sidecar` cible souvent le **premier** conteneur (`nginx`), qui n’a pas `wget` → `executable file not found`.

---

## Étape 6 — Lire le YAML vivant

```bash
kubectl get pod deux-conteneurs -n "$NS" -o yaml
```

Repérez (cherchez dans le pager / l’éditeur) :

- `spec.containers` : deux entrées `nginx` et `sidecar`
- `status.phase: Running`
- `status.podIP`
- `status.containerStatuses` : `ready: true` pour les deux, `imageID` (digest)

Ce YAML est **l’état actuel** (status inclus), pas seulement le fichier `pod.yaml`.

---

## Étape 7 — Pod jetable : `kubectl run`

`kubectl run` crée un Pod (plus un Deployment depuis Kubernetes 1.18). Pour un essai d’une commande :

```bash
kubectl run tmp --rm -it --restart=Never --image=ghcr.io/doorcloud/formation/busybox:1.36 -n "$NS" -- echo "pod jetable OK"
```

**Résultat attendu :** `pod jetable OK`, puis le Pod est **supprimé** (`--rm`). `--restart=Never` = un Job d’une fois, pas un redémarrage infini. `-it` = terminal interactif (TTY) : à utiliser dans **votre** shell, pas dans un script.

Équivalent non interactif (CI / `check.sh`) : omettre `-it` (pas de TTY). `--rm --attach` sans TTY peut afficher `couldn't attach … falling back to streaming logs` puis quand même imprimer la sortie : normal. Préférez `kubectl logs` + `delete` dans un script.

---

## Pièges

- **Namespace oublié** : `kubectl apply -f pod.yaml` sans `-n` envoie dans `default` (souvent interdit en salle). Prenez l’habitude de `-n "$NS"`.
- **`sleep infinity`** : rejeté par busybox. Utilisez `sleep 3600` (ou un nombre).
- **`kubectl run --replicas`** : n’existe plus (ne crée plus de Deployment). Lab 4 = `Deployment`.
- **`--rm -it` dans un script** : bloque / échoue sans TTY. Réservé au README. Sans TTY, `--attach` peut se rabattre sur `logs` avec un warning.
- **Windows** : collez les commandes dans WSL. `export NS=...` ne survit pas à la fermeture du terminal.
- **`serviceaccount "default" not found`** juste après `create namespace` : le ServiceAccount `default` est créé par un contrôleur, une seconde plus tard. Relancez simplement le `kubectl apply`. (Observé sur DKS.)
- **`ContainerCreating` qui dure** : le nœud télécharge l’image ; les téléchargements sont **sérialisés** par nœud, une image lente retarde les autres. `kubectl describe pod` → événement `Pulling`. Patientez, ou voyez [docs/images-registres.md](../../docs/images-registres.md).

> **macOS / Linux / WSL**  
> `kubectl exec -it … -- sh` ouvre un shell : tapez `exit` pour rendre la main. Le sidecar `sleep` continue.

## Nettoyage

```bash
kubectl delete pod deux-conteneurs -n "$NS"
kubectl delete pod tmp -n "$NS" --ignore-not-found
# plus tard, en fin de journée (ou maintenant si vous changez de machine) :
# kubectl delete ns "$NS"
```

Gardez `$NS` si vous enchaînez le lab 4 dans le même namespace ; sinon :

```bash
kubectl delete ns "$NS"
```

Vérification automatique (namespace jetable, sans `-it`) :

```bash
./check.sh
```

## Pour aller plus loin

- Init container : tourne **avant** les conteneurs applicatifs (`kubectl explain pod.spec.initContainers`).
- `shareProcessNamespace: true` : les PID deviennent visibles entre conteneurs du même Pod (rare en intro).
- Pourquoi 2 conteneurs et pas 2 Pods : sidecar de logs/agent, **même IP**, même cycle de vie.
