# Lab 04 — Deployment, rolling update et Service ClusterIP

**Durée estimée :** 35 minutes

## Objectifs

- Gérer **2 réplicas** nginx via un Deployment (`apps/v1`) avec *readiness probe*.
- Suivre un rollout, **scaler**, changer d’image (`ghcr.io/doorcloud/formation/nginx:1.27-alpine` → `ghcr.io/doorcloud/formation/nginx:1.28-alpine`) puis **annuler**.
- Exposer l’application par un Service **ClusterIP** `web-svc` (port 80).
- Vérifier le DNS CoreDNS (`web-svc` et le FQDN) et les **EndpointSlices**.
- Comprendre NodePort (lecture) sans l’appliquer.

## Prérequis

- Lab 03 : vous avez un namespace `$NS`. S’il a été supprimé, recréez-le.
- Images : `ghcr.io/doorcloud/formation/nginx:1.27-alpine`, `ghcr.io/doorcloud/formation/nginx:1.28-alpine` (tag vérifié sur Docker Hub, 9 sept. 2026), `ghcr.io/doorcloud/formation/busybox:1.36`.
- Le sélecteur du Service **doit** égaler les labels des Pods (`app.kubernetes.io/name=web`). Un écart → 0 endpoint, wget timeout.

```bash
export NS=lab-<prenom>
kubectl get ns "$NS" >/dev/null || kubectl create namespace "$NS"
cd kubernetes/lab04-deployment-service
```

---

## Étape 1 — Deployment 2 réplicas + attente

```bash
kubectl apply -n "$NS" -f deployment.yaml
kubectl rollout status deploy/web -n "$NS"
kubectl get deploy,po -n "$NS" -l app.kubernetes.io/name=web
```

**Résultat attendu :** `deployment "web" successfully rolled out`, `READY 2/2`. La probe HTTP `GET /` sur le port 80 empêche le Service d’envoyer du trafic vers un nginx pas encore prêt.

---

## Étape 2 — Scale

```bash
kubectl scale deploy/web --replicas=3 -n "$NS"
kubectl rollout status deploy/web -n "$NS"
kubectl get po -n "$NS" -l app.kubernetes.io/name=web
kubectl scale deploy/web --replicas=2 -n "$NS"
kubectl rollout status deploy/web -n "$NS"
```

**Résultat attendu :** trois Pods un instant, puis retour à **2**. `scale` ne change que `spec.replicas` (le fichier YAML local reste à 2 tant que vous ne le ré-appliquez pas).

---

## Étape 3 — Rolling update et historique

Le tag `ghcr.io/doorcloud/formation/nginx:1.28-alpine` existe (manifest Docker Hub). On bascule, on observe, on revient.

```bash
kubectl set image deploy/web nginx=ghcr.io/doorcloud/formation/nginx:1.28-alpine -n "$NS"
kubectl rollout status deploy/web -n "$NS"
kubectl get po -n "$NS" -l app.kubernetes.io/name=web -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
kubectl rollout history deploy/web -n "$NS"
```

**Résultat attendu :** nouveaux Pods en `ghcr.io/doorcloud/formation/nginx:1.28-alpine`, *RollingUpdate* (pas de downtime si 2 réplicas). `history` liste les révisions.

Annuler (revenir à la révision précédente, donc `1.27-alpine`) :

```bash
kubectl rollout undo deploy/web -n "$NS"
kubectl rollout status deploy/web -n "$NS"
kubectl rollout history deploy/web -n "$NS"
```

**Résultat attendu :** image de nouveau `ghcr.io/doorcloud/formation/nginx:1.27-alpine`. Un ancien Pod peut rester `Terminating` quelques secondes : `get endpointslices` peut alors lister **3** IP le temps du drain — attendez `READY 2/2` avant de conclure. Un `kubectl apply -f deployment.yaml` remettrait aussi le manifeste git (1.27). Ne pas enchaîner `undo` deux fois « pour voir » : le second undo **repart vers 1.28**.

---

## Étape 4 — Service ClusterIP `web-svc`

```bash
kubectl apply -n "$NS" -f service.yaml
kubectl get svc web-svc -n "$NS"
kubectl get endpointslices -n "$NS"
kubectl get endpoints web-svc -n "$NS"
```

**Résultat attendu :** `TYPE ClusterIP`, `PORT 80`. Deux adresses Ready (une par Pod). `EndpointSlice` (`discovery.k8s.io/v1`) est la source actuelle ; `Endpoints` (`v1`) reste une vue agrégée. En 1.33+, `kubectl get endpoints` affiche un **Warning** de dépréciation : normal, on lit quand même la colonne ENDPOINTS.

VIP ClusterIP : joignable **depuis le cluster**, pas depuis votre laptop (sauf `port-forward`, hors scope).

---

## Étape 5 — DNS : nom court et FQDN

Pod de test **dans le même namespace** (les *search* CoreDNS incluent `$NS.svc.cluster.local`) :

```bash
kubectl run dns-test --rm -it --restart=Never --image=ghcr.io/doorcloud/formation/busybox:1.36 -n "$NS" -- nslookup web-svc
```

**Résultat attendu :** un bloc `Name: web-svc.$NS.svc.cluster.local` + `Address: <ClusterIP>`. busybox interroge aussi les suffixes de *search* (`web-svc.svc.cluster.local`, `web-svc.cluster.local`) et imprime des **NXDOMAIN** : ce n’est **pas** une panne. Le code de sortie peut être ≠ 0 malgré la résolution — lisez `Name:` / `Address:`, ne vous fiez pas à `$?`.

FQDN (plus « propre », y compris depuis un autre namespace) :

```bash
kubectl run dns-fqdn --rm -it --restart=Never --image=ghcr.io/doorcloud/formation/busybox:1.36 -n "$NS" -- nslookup web-svc."$NS".svc.cluster.local
```

HTTP :

```bash
kubectl run wget-test --rm -it --restart=Never --image=ghcr.io/doorcloud/formation/busybox:1.36 -n "$NS" -- wget -qO- http://web-svc
```

**Résultat attendu :** HTML nginx. Équivalent FQDN : `http://web-svc.$NS.svc.cluster.local`.

Sans `-it` (script) : omettre `-it` et `--rm`, puis `kubectl logs`.

---

## NodePort (à connaître, pas à appliquer)

| Type | Qui joint ? | Salle |
|---|---|---|
| **ClusterIP** (défaut) | Pods du cluster, via DNS | C’est ce lab |
| **NodePort** | ClusterIP **+** port haut (30000–32767) sur **chaque nœud** | Utile en bare-metal ; sur DKS/kind, firewall / mapping kind compliquent le test laptop |
| LoadBalancer | Provisionne un LB cloud | DKS a kube-vip ; coût / IP — pas dans ce lab |

Un Service NodePort *est* un ClusterIP avec un `nodePort` en plus. On n’en crée pas ici : pas d’assertion, pas de manifeste.

---

## Pièges

- **Sélecteur ≠ labels** : `app: web` vs `app.kubernetes.io/name: web` → `endpoints=0`, wget qui hang. Alignez les deux.
- **busybox nslookup** : NXDOMAIN sur les suffixes de *search* **et** code de sortie non nul, alors que `Name:` est correct. Inverse aussi possible sur d’autres builds (exit 0 + NXDOMAIN). Toujours lire `Address:`. Le FQDN `web-svc.$NS.svc.cluster.local` est plus lisible. `wget` / curl restent le vrai test métier.
- **`kubectl run` et Deployment** : `run` ≠ `create deployment`. Ici le Deployment est le YAML.
- **Undo répété** : bascule entre deux révisions. L’historique n’est pas un « undo infini ».
- **`--port` sur `create deployment`** : flag invalide (lab d’origine cassé). Le port est dans le manifeste / `containerPort`.

> **macOS / Linux / WSL**  
> `kubectl run --rm -it` exige un TTY. Sous CI ou Git Bash sans TTY : retirez `-it`.  
> **Windows WSL** : le FQDN avec `"$NS"` doit rester en bash (`web-svc.lab-amine.svc.cluster.local`).

## Nettoyage

```bash
kubectl delete -n "$NS" -f service.yaml -f deployment.yaml
# kubectl delete ns "$NS"
```

Vérification automatique (2 réplicas Ready, 2 endpoints, HTTP 200 via `ghcr.io/doorcloud/formation/curl:8.10.1`) :

```bash
./check.sh
```

## Pour aller plus loin

- `kubectl rollout pause` / `resume` : geler un canary.
- `maxUnavailable` / `maxSurge` : `kubectl explain deploy.spec.strategy.rollingUpdate`.
- Headless Service (`clusterIP: None`) : DNS vers les Pods, pas vers une VIP (StatefulSet, lab bonus).
