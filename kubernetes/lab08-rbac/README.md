# Lab 08 — RBAC, SecurityContext et Pod Security Admission

**Durée estimée :** 30 minutes

## Objectifs

- Créer un **ServiceAccount** `lecteur`, un **Role** `pod-reader` (get/list/watch `pods`) et un **RoleBinding**.
- Vérifier les droits avec `kubectl auth can-i` et `--as=system:serviceaccount:$NS:lecteur`.
- Émettre un jeton (`kubectl create token`) et appeler l’API **depuis un Pod** avec le token monté (`curl` + `ca.crt`) : **GET 200**, **DELETE 403**.
- Ajouter un **second Role** (`delete`) et retester : DELETE autorisé.
- Voir `runAsNonRoot` échouer sur `nginx:1.27-alpine` (root) et réussir avec `nginxinc/nginx-unprivileged:1.27-alpine`.
- Poser `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem` là où c’est possible.
- Labelliser le namespace `pod-security.kubernetes.io/enforce=restricted` et constater le **rejet** d’un Pod privileged.

## Prérequis

- `kubectl get nodes` OK. Lab 03 (namespace).
- Terminal bash/zsh ; **Windows = WSL ou Git Bash**.
- Images : `curlimages/curl:8.10.1`, `registry.k8s.io/pause:3.10`, `nginx:1.27-alpine`, `nginxinc/nginx-unprivileged:1.27-alpine`.

```bash
cd kubernetes/lab08-rbac
export NS=lab-<prenom>
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
```

> **macOS / Linux**
> Kubeconfig : `~/.kube/config`. `kubectl create token` nécessite un client **1.24+** (le kubectl recommandé pour DKS, 1.31–1.33, convient ; vérifiez avec `kubectl version`).
>
> **Windows (WSL)**
> Toutes les commandes dans Ubuntu WSL. Le JWT affiché est un **exemple pédagogique** : ne le collez pas dans un chat, un ticket ou un mail.

---

## Étape 1 — ServiceAccount, Role, RoleBinding

```bash
kubectl apply -n "$NS" -f sa.yaml -f role-pod-reader.yaml -f rolebinding-lecteur.yaml
kubectl get sa,role,rolebinding -n "$NS"
```

**Résultat attendu :** `lecteur`, Role `pod-reader` (verbes `get`, `list`, `watch` sur `pods`), binding `lecteur-pod-reader`.

Les manifests **n’ont pas** `metadata.namespace` : c’est `-n "$NS"` qui le pose. Sur un cluster partagé, le RBAC du formateur vous empêche d’écrire ailleurs que dans `lab-<prenom>`.

---

## Étape 2 — `can-i` (impersonation)

```bash
kubectl auth can-i list pods --as="system:serviceaccount:${NS}:lecteur" -n "$NS"
kubectl auth can-i delete pods --as="system:serviceaccount:${NS}:lecteur" -n "$NS"
kubectl auth can-i list pods --as="system:serviceaccount:${NS}:lecteur" -n kube-system
```

**Résultat attendu :** `yes` ; `no` ; `no` (le Role est **namespacé** : pas de lecture de `kube-system`).

`can-i` sans `--as` teste **votre** utilisateur kubeconfig (souvent `yes` partout dans le namespace stagiaire). `--as=` simule le SA.

---

## Étape 3 — Token et appel HTTP depuis un Pod

```bash
kubectl create token lecteur -n "$NS"
```

**Résultat attendu :** un JWT (trois segments séparés par `.`). C’est le même **sujet** RBAC que le fichier monté dans le Pod ; la durée de vie du token `create token` est courte (défaut 1 h).

```bash
kubectl apply -n "$NS" -f pod-curl.yaml -f pod-cible.yaml
kubectl wait --for=condition=Ready pod/curl-api pod/cible -n "$NS" --timeout=120s
```

Le Pod `curl-api` utilise `serviceAccountName: lecteur`. Le kubelet monte :

- `/var/run/secrets/kubernetes.io/serviceaccount/token`
- `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
- `/var/run/secrets/kubernetes.io/serviceaccount/namespace`

```bash
kubectl exec -n "$NS" curl-api -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NS_FILE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
curl -sS -o /tmp/body -w "HTTP %{http_code}\n" --max-time 15 \
  --cacert "$CACERT" \
  -H "Authorization: Bearer $TOKEN" \
  "https://kubernetes.default.svc/api/v1/namespaces/${NS_FILE}/pods"
'
```

**Résultat attendu :** `HTTP 200` et un JSON `PodList`.

```bash
kubectl exec -n "$NS" curl-api -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NS_FILE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
curl -sS -o /tmp/body -w "HTTP %{http_code}\n" --max-time 15 \
  --cacert "$CACERT" \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "https://kubernetes.default.svc/api/v1/namespaces/${NS_FILE}/pods/cible"
cat /tmp/body; echo
'
```

**Résultat attendu :** `HTTP 403` (Forbidden). Le verbe `delete` n’est pas dans `pod-reader`.

Le Pod `cible` **existe toujours** :

```bash
kubectl get pod cible -n "$NS"
```

> **`delete` ≠ `deletecollection`**
> `DELETE /api/v1/namespaces/$NS/pods` (sans nom) exige le verbe `deletecollection`. Ici on cible **un** Pod : `DELETE .../pods/cible` → verbe `delete`.

> **macOS / WSL**
> `curl` du **laptop** vers `https://kubernetes.default.svc` échoue (DNS interne cluster). L’appel se fait **dans** le Pod. Pour l’API depuis le laptop : `kubectl get pods` (votre kubeconfig), pas ce hostname.

---

## Étape 4 — Second Role : autoriser `delete`

On **ajoute** un Role, on n’écrase pas `pod-reader` (RBAC additif : l’union des Roles liés au SA).

```bash
kubectl apply -n "$NS" -f role-pod-deleter.yaml -f rolebinding-deleter.yaml
kubectl auth can-i delete pods --as="system:serviceaccount:${NS}:lecteur" -n "$NS"
```

**Résultat attendu :** `yes`.

```bash
kubectl exec -n "$NS" curl-api -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NS_FILE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
curl -sS -o /tmp/body -w "HTTP %{http_code}\n" --max-time 15 \
  --cacert "$CACERT" \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "https://kubernetes.default.svc/api/v1/namespaces/${NS_FILE}/pods/cible"
'
kubectl get pod cible -n "$NS"
```

**Résultat attendu :** `HTTP 200` puis `NotFound` pour `cible`.

---

## Étape 5 — SecurityContext : root vs non-root

L’image officielle `nginx:1.27-alpine` s’exécute en **uid 0**. `runAsNonRoot: true` sans `runAsUser` non-root est rejeté **par le kubelet** (pas par RBAC).

```bash
kubectl apply -n "$NS" -f pod-nginx-root.yaml
kubectl get pod nginx-root-interdit -n "$NS" -w
```

Ctrl+C après avoir vu l’état. Puis :

```bash
kubectl describe pod nginx-root-interdit -n "$NS" | grep -A4 'State:'
```

**Résultat attendu :** `CreateContainerConfigError` ; message du type *container has runAsNonRoot and image will run as root*.

```bash
kubectl apply -n "$NS" -f pod-nginx-unprivileged.yaml
kubectl wait --for=condition=Ready pod/nginx-unprivileged -n "$NS" --timeout=120s
kubectl get pod nginx-unprivileged -n "$NS" -o jsonpath='{.spec.containers[0].securityContext}' ; echo
```

**Résultat attendu :** Pod `Ready`. Image `nginxinc/nginx-unprivileged:1.27-alpine` (uid 101, port **8080**). Le manifeste pose `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true` + `emptyDir` sur `/tmp`, `/var/cache/nginx`, `/var/run` (Nginx doit écrire son pid/cache).

C’est le profil **minimal** attendu en salle : l’image officielle Nginx **ne** permet **pas** `runAsNonRoot` sans casser le démarrage.

---

## Étape 6 — Pod Security Admission (`restricted`)

Les *PodSecurityPolicies* ont disparu en 1.25. À la place : labels sur le **namespace**.

```bash
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl apply -n "$NS" -f pod-privilegie.yaml
```

**Résultat attendu :** `kubectl apply` **échoue** (code ≠ 0). Le message contient `violates PodSecurity` (privileged interdit au niveau `restricted`).

Les Pods **déjà créés** ne sont pas expulsés : PSA agit à **l’admission**. `nginx-root-interdit` peut rester `CreateContainerConfigError`.

```bash
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce- --overwrite
```

(retrait du label — optionnel ; en fin de lab le nettoyage ciblé suffit.)

> **DKS**
> Le namespace tenant peut **déjà** être en `enforce=restricted` (ou `baseline`). Dans ce cas l’étape 6 est déjà « faite » par la plateforme : le Pod privileged est refusé **sans** que vous posiez le label. Posez-le quand même (idempotent). Si `nginx:1.27-alpine` **sans** SecurityContext restricted est rejeté plus tôt, c’est la même admission — notez le message et continuez avec `nginx-unprivileged`.

---

## Pièges

- **Role vs ClusterRole** : un Role ne sort pas du namespace. Pas de `kubectl get pods -A` avec `lecteur`.
- **`--as` oublié** : vous testez *votre* compte, pas le SA.
- **DELETE sur la collection** `/pods` : 403 même après l’étape 4 si vous n’avez pas `deletecollection`. Utilisez `/pods/cible`.
- **Token dans le README / Discord** : ne le faites pas. `create token` est pour *voir* le format.
- **`kubectl edit` du Role** : possible, mais le lab fournit `role-pod-deleter.yaml` pour rester additif et rejouable.
- **PSA `warn` / `audit`** : n’empêchent pas la création. Seul **`enforce`** refuse.
- **kind vs DKS** : kind n’impose en général **aucun** PSA par défaut ; DKS peut imposer `restricted` sur `lab-*`. Le SecurityContext des Pods « qui doivent tourner » (`curl-api`, `cible`, `nginx-unprivileged`) est déjà compatible `restricted`.

## Nettoyage

```bash
kubectl delete pod curl-api cible nginx-root-interdit nginx-unprivileged privilegie-interdit -n "$NS" --ignore-not-found
kubectl delete rolebinding lecteur-pod-reader lecteur-pod-deleter -n "$NS" --ignore-not-found
kubectl delete role pod-reader pod-deleter -n "$NS" --ignore-not-found
kubectl delete sa lecteur -n "$NS" --ignore-not-found
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce- --overwrite 2>/dev/null || true
```

Vérification automatique :

```bash
./check.sh
```

## Pour aller plus loin

- `kubectl auth can-i --list --as=system:serviceaccount:${NS}:lecteur -n "$NS"`
- ClusterRole `view` (lecture cluster) vs Role métier — trop large pour un SA d’application.
- `seccompProfile.type: RuntimeDefault` (déjà dans les Pods « sains » de ce lab) est exigé par PSA `restricted`.
