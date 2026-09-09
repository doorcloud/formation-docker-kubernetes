# Lab 05 — ConfigMap et Secret

**Durée estimée :** 25 minutes

## Objectifs

- Externaliser la conf Redis : ConfigMap **littérale** + **fichier** `redis.conf`.
- Créer un Secret Opaque (`DB_PASSWORD=ChangeMe-lab`) et voir que le **base64 n’est pas un chiffrement**.
- Monter le ConfigMap en fichier et le Secret en variable d’environnement dans `ghcr.io/doorcloud/formation/redis:7-alpine`.
- Vérifier avec `exec` : `env`, `cat` du fichier monté, `redis-cli ping` → `PONG`.
- Générer du YAML sans l’envoyer : `kubectl create … --dry-run=client -o yaml`.

## Prérequis

- Labs 03–04 : namespace `$NS` existant (sinon créez-le).
- Image : `ghcr.io/doorcloud/formation/redis:7-alpine` (tag figé). Mot de passe d’exemple **uniquement pédagogique** : `ChangeMe-lab` (jamais un vrai secret dans git).

```bash
export NS=lab-<prenom>
kubectl get ns "$NS" >/dev/null || kubectl create namespace "$NS"
cd kubernetes/lab05-configmap-secret
```

---

## Étape 1 — Dry-run : voir le YAML avant d’appliquer

`--from-literal` (clé/valeur) **et** `--from-file=redis.conf` (le nom du fichier devient la clé) :

```bash
kubectl create configmap redis-config \
  --from-literal=REDIS_MAXMEMORY=2mb \
  --from-file=redis.conf \
  --dry-run=client -o yaml
```

**Résultat attendu :** un manifeste `kind: ConfigMap` avec `data.REDIS_MAXMEMORY: 2mb` et `data.redis.conf: |` suivi du contenu. Rien n’est créé sur le cluster (`--dry-run=client`).

Les fichiers `configmap.yaml` / `secret.yaml` du dossier sont l’équivalent versionné. On les applique ensuite (idempotent, contrairement à un `kubectl create` nu qui échoue au 2e essai).

---

## Étape 2 — Appliquer ConfigMap, Secret, Pod

```bash
kubectl apply -n "$NS" -f configmap.yaml -f secret.yaml -f pod.yaml
kubectl wait -n "$NS" --for=condition=Ready pod/redis --timeout=120s
kubectl get cm,secret,pod -n "$NS" -l app.kubernetes.io/name=redis
```

**Résultat attendu :** Pod `1/1 Running`. Le Secret s’affiche `Opaque` sans montrer le mot de passe.

Le Pod :

- lance `redis-server /usr/local/etc/redis/redis.conf` (volume ConfigMap, mode `0644` — l’UID redis **999** doit pouvoir lire) ;
- injecte `DB_PASSWORD` depuis `secretKeyRef` ;
- écrit ses dumps dans `/data` (`emptyDir` + `fsGroup: 999`). Un ConfigMap est **toujours en lecture seule** : ne pas y mettre `dir`.

---

## Étape 3 — Secret : base64 ≠ chiffrement

```bash
kubectl get secret redis-secret -n "$NS" -o jsonpath='{.data.DB_PASSWORD}{"\n"}'
printf '%s' 'ChangeMe-lab' | base64
```

Les deux lignes doivent **correspondre** (un `echo` sans `-n` ajoute un saut de ligne → base64 différent : piège classique).

Décoder :

```bash
# Linux / WSL (GNU coreutils) :
kubectl get secret redis-secret -n "$NS" -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

```bash
# macOS (BSD base64) :
kubectl get secret redis-secret -n "$NS" -o jsonpath='{.data.DB_PASSWORD}' | base64 -D
echo
```

**Résultat attendu :** `ChangeMe-lab`. N’importe qui avec `get secrets` dans le namespace peut le relire. etcd stocke ça en clair **encodé**, pas chiffré, sauf si le cluster a une *EncryptionConfiguration* (hors scope ; DKS managé peut l’avoir côté control plane, ça ne change pas `kubectl get secret`).

Le YAML du repo utilise `stringData` (texte en clair dans le fichier) : Kubernetes le convertit en `data:` base64. Pratique pour un lab ; en prod on injecte depuis un coffre, on ne commite pas de vrais mots de passe.

Création impérative équivalente (si vous n’utilisez pas le YAML) :

```bash
kubectl create secret generic redis-secret \
  --from-literal=DB_PASSWORD=ChangeMe-lab \
  -n "$NS" \
  --dry-run=client -o yaml
```

---

## Étape 4 — `exec` : env, fichier, ping

```bash
kubectl exec -n "$NS" redis -- env | grep DB_
kubectl exec -n "$NS" redis -- cat /usr/local/etc/redis/redis.conf
kubectl exec -n "$NS" redis -- redis-cli ping
```

**Résultat attendu :**

- `DB_PASSWORD=ChangeMe-lab`
- le contenu de `redis.conf` (`maxmemory 2mb`, `dir /data`, `daemonize no`)
- `PONG`

`DB_PASSWORD` est dans l’environnement du process : Redis **n’utilise pas** ce mot de passe pour AUTH (`requirepass` absent exprès). Le Secret sert à montrer l’injection ; un vrai Redis en prod aurait `requirepass` + Secret, ou ACL.

---

## Pièges

- **`kubectl create` deux fois** : `AlreadyExists`. Préférez `apply` ou `create … --dry-run=client -o yaml | kubectl apply -f -`.
- **`defaultMode: 0400`** : seul root lit le fichier → redis UID 999 crash (`Permission denied` sur `redis.conf`).
- **`dir` pointé sur le montage ConfigMap** : volume read-only → Redis meurt au premier `SAVE`. D’où `dir /data` + `emptyDir`.
- **`daemonize yes`** : le process se détache, Kubernetes croit que le conteneur est mort (CrashLoop).
- **`echo ChangeMe-lab | base64`** : newline encodée. Utilisez `printf '%s' 'ChangeMe-lab' | base64`.
- Image **Bitnami** / `redis:latest` : hors programme (catalogue public restreint / tag flottant).

> **macOS**  
> `base64 -D` pour décoder (`-d` est GNU).  
> **Linux / WSL**  
> `base64 -d` ou `base64 --decode`.  
> **Windows**  
> Restez sous WSL : le `base64` d’Ubuntu est GNU.

## Nettoyage

```bash
kubectl delete -n "$NS" -f pod.yaml -f secret.yaml -f configmap.yaml
# kubectl delete ns "$NS"
```

Vérification automatique (`DB_PASSWORD` + `PONG`) :

```bash
./check.sh
```

## Pour aller plus loin

- `envFrom.configMapRef` / `secretRef` : importer **toutes** les clés en env.
- Projection `subPath` : monter **un** fichier sans cacher le reste du répertoire (ici on monte le dossier `/usr/local/etc/redis` avec `items:` pour n’exposer que `redis.conf`).
- Rotation : changer un Secret **ne relance pas** le Pod ; il faut un rollout (annotation checksum, ou recréer le Pod).
