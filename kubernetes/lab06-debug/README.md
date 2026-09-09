# Lab 06 — Diagnostiquer un workload cassé

**Durée estimée :** 25 minutes

## Objectifs

- Distinguer **ImagePullBackOff** / **ErrImagePull**, **CrashLoopBackOff**, et un Pod **Running mais jamais Ready**.
- Lire `kubectl describe`, `kubectl get events --sort-by=.lastTimestamp`, `kubectl logs --previous`.
- Comprendre le rôle de `restartPolicy` dans la boucle de crash.
- Voir qu’une **readinessProbe** fausse laisse le processus vivant mais vide le Service (`endpoints` / EndpointSlices).
- Utiliser `kubectl debug` (conteneur éphémère) et savoir que `kubectl top` exige metrics-server.

## Prérequis

- `kubectl get nodes` OK (kubeconfig du cluster de la formation).
- Labs 03–04 faits (namespace, Pod, Deployment, Service).
- Terminal : macOS (Terminal / iTerm, zsh ou bash), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.
- Images : `nginx:1.27-alpine`, `busybox:1.36` (tags figés, jamais `:latest`).

```bash
cd kubernetes/lab06-debug
export NS=lab-<prenom>
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
```

Remplacez `<prenom>` par le vôtre, en minuscules, sans accent (`lab-amina`, `lab-jean`).

> **macOS / Linux**
> Kubeconfig par défaut : `~/.kube/config`. Si `kubectl get nodes` échoue : `echo "$KUBECONFIG"` et `kubectl config current-context`.
>
> **Windows (WSL)**
> `kubectl` et le kubeconfig vivent **dans WSL** (`~/.kube/config` du home Linux). Un fichier collé sous `C:\Users\...\.kube\config` n’est **pas** lu par Ubuntu WSL. `export KUBECONFIG=~/.kube/config` si besoin.
>
> Copier-coller multi-lignes : collez le bloc entier dans bash/zsh. Pas PowerShell.

---

## Étape 1 — Trois incidents à appliquer

```bash
kubectl apply -n "$NS" \
  -f pod-image-introuvable.yaml \
  -f pod-crash.yaml \
  -f web-pas-pret.yaml
kubectl get pods -n "$NS" -o wide
```

**Résultat attendu (après 10–30 s) :**

| Objet | Symptôme |
|---|---|
| Pod `image-introuvable` | `ErrImagePull` puis `ImagePullBackOff` |
| Pod `crash-loop` | `CrashLoopBackOff` (ou `Error` + `RESTARTS` qui augmente) |
| Pods `web-pas-pret-*` | `Running` mais `0/1` Ready |

Ne corrigez rien avant d’avoir fini le diagnostic (étapes 2–5).

---

## Étape 2 — Image inexistante (`describe` + events)

```bash
kubectl describe pod image-introuvable -n "$NS"
kubectl get events -n "$NS" --sort-by=.lastTimestamp
```

**Résultat attendu :** `Failed to pull image "nginx:1.27-alpine-doesnotexist"` ; raison `ErrImagePull` / `ImagePullBackOff`. Les events les plus récents sont en bas.

Le kubelet **n’exécute jamais** le conteneur : `kubectl logs` est vide (ou « waiting to start »). Ce n’est pas un bug applicatif.

```bash
kubectl logs image-introuvable -n "$NS" || true
```

---

## Étape 3 — Processus qui sort en erreur (`logs --previous`)

Le manifeste lance `sh -c "echo boot; exit 1"` avec `restartPolicy: Always` (défaut d’un Pod nu). Kubernetes relance → backoff → `CrashLoopBackOff`.

```bash
kubectl get pod crash-loop -n "$NS" -o yaml | grep -A2 restartPolicy
kubectl describe pod crash-loop -n "$NS"
kubectl logs crash-loop -n "$NS"
kubectl logs crash-loop -n "$NS" --previous
```

**Résultat attendu :** la ligne `boot` apparaît. `--previous` lit le **dernier** conteneur mort (utile quand le courant n’a pas encore réécrit stdout).

Si `restartPolicy` valait `Never`, le Pod passerait `Failed` **sans** boucle : pas de `CrashLoopBackOff`. Ne changez pas encore le manifeste.

---

## Étape 4 — Probe de readiness et Service sans endpoints

Les Pods Nginx **tournent** (le processus écoute sur `:80`) mais la probe HTTP tape `/sante-introuvable` (404). Un Pod non Ready n’entre pas dans le Service.

```bash
kubectl get pods -n "$NS" -l app.kubernetes.io/name=web-pas-pret
kubectl describe pod -n "$NS" -l app.kubernetes.io/name=web-pas-pret | grep -A6 'Readiness probe'
kubectl get endpoints web-pas-pret -n "$NS"
kubectl get endpointslices -n "$NS" -l kubernetes.io/service-name=web-pas-pret
```

**Résultat attendu :** Ready `False` ; probe `statuscode: 404`. `ENDPOINTS` vide (ou pas d’adresse Ready). L’EndpointSlice existe souvent, mais **sans** adresse `Ready=True`.

> **Endpoints vs EndpointSlice**
> L’objet `Endpoints` (v1) reste lisible (`kubectl get endpoints`). La source moderne est `discovery.k8s.io/v1` EndpointSlice. Les deux doivent être vides côté trafic tant qu’aucun Pod n’est Ready.

---

## Étape 5 — `kubectl debug` (conteneur éphémère) et `kubectl top`

Le Pod `web-pas-pret-*` est Running : on peut y attacher un conteneur **éphémère** (même namespaces réseau, et processus si `--target=nginx`) **sans** reconstruire l’image.

```bash
POD=$(kubectl get pod -n "$NS" -l app.kubernetes.io/name=web-pas-pret \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
echo "Pod cible : $POD"
kubectl debug -it "pod/${POD}" -n "$NS" \
  --image=busybox:1.36 \
  --target=nginx \
  --profile=general
```

Dans le shell debug (invite `command prompt` / `#`) :

```sh
wget -qO- http://127.0.0.1/ | head
exit
```

**Résultat attendu :** la page d’accueil Nginx. L’application **va bien** ; seule la probe est fausse. `exit` quitte le debug (le Pod applicatif reste).

> **macOS / Linux / WSL**
> `-it` exige un vrai TTY. Dans un script CI, on omet `-it` et on passe `--attach=false` (voir `check.sh`). Ne collez pas `-it` dans un pipeline non interactif.

```bash
kubectl top nodes
kubectl top pods -n "$NS"
```

**Résultat attendu :** sur DKS, un tableau CPU/RAM (metrics-server `door-metrics-server` est fourni par la plateforme) ; sur kind, `Metrics API not available`. **Les deux sont valides.** `kubectl top` parle à **metrics-server**. Sur kind d’entraînement il est souvent **absent** ; sur un cluster DKS il peut être installé. Ce n’est pas un échec du lab.

---

## Étape 6 — Corriger

Trois techniques, une par incident.

**a) Image — le champ `image` d’un Pod est mutable.** Appliquez le manifeste corrigé (ou `kubectl edit pod image-introuvable -n "$NS"` et remplacez le tag) :

```bash
kubectl apply -n "$NS" -f fix/pod-image-ok.yaml
```

**b) Commande — `command` est immuable.** Il faut recréer le Pod :

```bash
kubectl delete pod crash-loop -n "$NS" --wait=true
kubectl apply -n "$NS" -f fix/pod-crash-ok.yaml
```

**c) Probe — un Deployment accepte le patch.** Au choix :

```bash
# sans éditeur interactif (recommandé sous WSL si vi vous gêne)
kubectl apply -n "$NS" -f fix/web-ok.yaml
```

```bash
# équivalent : éditer le live
# export KUBE_EDITOR=nano   # macOS / WSL / Linux, si vous préférez nano à vi
kubectl edit deploy web-pas-pret -n "$NS"
# readinessProbe.httpGet.path: /sante-introuvable  →  /
```

> **macOS / Linux / WSL**
> `kubectl edit` ouvre `$KUBE_EDITOR` ou `$EDITOR`, sinon vi. `nano` : `export KUBE_EDITOR=nano`. Sous Windows, restez dans WSL ; n’utilisez pas le Bloc-notes sur le manifeste live.

Attendre la guérison :

```bash
kubectl wait --for=condition=Ready pod/image-introuvable -n "$NS" --timeout=120s
kubectl wait --for=condition=Ready pod/crash-loop -n "$NS" --timeout=120s
kubectl rollout status deploy/web-pas-pret -n "$NS" --timeout=120s
kubectl get endpoints web-pas-pret -n "$NS"
kubectl get endpointslices -n "$NS" -l kubernetes.io/service-name=web-pas-pret
```

**Résultat attendu :** les trois workloads `Ready` ; le Service a des IPs.

---

## Pièges

- **Logs vides** sur `image-introuvable` : normal, l’image n’a jamais démarré. Regardez `describe` / events, pas `logs`.
- **`CrashLoopBackOff` n’est pas immédiat** : le kubelet attend un backoff. `RESTARTS > 0` suffit pour confirmer la boucle.
- **`restartPolicy: Never`** : pas de CrashLoop, juste `Failed`. Les Jobs s’en servent ; un Pod long-running presque toujours `Always`.
- **Liveness ≠ readiness.** Une liveness fausse *tuerait* Nginx. Ici seule la readiness est fausse : le processus vit, le Service le masque.
- **Docker Hub rate-limit** : un `ErrImagePull` avec `429` n’est pas un mauvais tag. Le lab utilise un tag qui n’existe vraiment pas (`…-doesnotexist`).
- **`kubectl debug` sur ImagePullBackOff** : le conteneur cible n’existe pas encore ; déboguez un Pod **Running** (`web-pas-pret` ou, après correctif, les autres).
- **Warning `v1 Endpoints is deprecated`** (Kubernetes 1.33+) : `kubectl get endpoints` marche encore ; préférez `kubectl get endpointslices` comme dans l’étape 4. Ce n’est pas un échec du lab.

> **DKS**
> Si `kubectl get ns "$NS" --show-labels` contient `pod-security.kubernetes.io/enforce=restricted`, les Pods **Nginx officiels** (root) de ce lab peuvent être **refusés à l’admission** (`violates PodSecurity`) au lieu d’`ImagePullBackOff` / `0/1 Ready`. Notez le message. Le Pod `crash-loop` (busybox non-root) reste valable. Pour la démo probe, le formateur peut substituer `nginxinc/nginx-unprivileged:1.27-alpine` (écoute **8080**). `kubectl top` peut fonctionner si metrics-server est installé (contrairement à kind).

## Nettoyage

Ciblé (gardez `$NS` pour les labs suivants) :

```bash
kubectl delete pod image-introuvable crash-loop -n "$NS" --ignore-not-found
kubectl delete deploy,svc web-pas-pret -n "$NS" --ignore-not-found
```

En fin de journée seulement :

```bash
kubectl delete namespace "$NS"
```

Vérification automatique (namespace aléatoire, non interactif, idempotent) :

```bash
./check.sh
```

## Pour aller plus loin

- `kubectl get events --watch` pendant un `apply` pour voir l’ordre Failed → BackOff.
- `kubectl get pod -o jsonpath='{.status.containerStatuses[0].state}'` pour scripter le diagnostic.
- Éphémère : `kubectl debug` vs sidecar permanent dans le manifeste (le sidecar survit, l’éphémère non).
