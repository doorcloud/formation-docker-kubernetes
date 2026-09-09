# Lab 09 — Isoler le trafic avec NetworkPolicy

**Durée estimée :** 25 minutes

## Objectifs

- Comprendre que Kubernetes **stocke** les `NetworkPolicy` même si le CNI ne les **applique** pas.
- Vérifier quel CNI tourne (Cilium sur DKS ; **kindnet n'applique pas** les policies).
- Déployer un `frontend`, un `backend` (+ Service) et un pod `intrus`.
- Poser un **deny-all** Ingress, constater le timeout `wget -T 3`.
- Autoriser uniquement les pods `role=frontend` vers le backend.
- (Optionnel) Ajouter de l'egress et comprendre **pourquoi le DNS casse**.

## Prérequis

- `kubectl` configuré : `kubectl get nodes` affiche au moins un nœud `Ready`.
- Terminal : macOS (Terminal / iTerm, zsh ou bash), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.
- Images utilisées (tags figés, jamais `:latest`) : `nginx:1.27-alpine`, `registry.k8s.io/e2e-test-images/agnhost:2.53`, `busybox:1.36`.

Depuis la racine du dépôt cloné :

```bash
cd kubernetes/lab09-networkpolicy
export NS=lab-<prenom>
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
```

Remplacez `<prenom>` par le vôtre **en minuscules, sans accent** (ex. `lab-fatou`). Le namespace existe déjà si vous venez du lab 8 : la commande ci-dessus ne le recrée pas. Toutes les commandes passent `-n "$NS"`. Ne touchez jamais `default` ni `kube-system`.

> **macOS / Windows WSL / Linux**  
> Le kubeconfig est en général `~/.kube/config`. Sous WSL, installez `kubectl` **dans** Linux et copiez le kubeconfig dans le home Linux (`~/.kube/config`), pas sous `/mnt/c`.  
> Pour forcer un fichier : `export KUBECONFIG="$HOME/.kube/config"`.  
> Collez les blocs multi-lignes tels quels (bash / zsh).

---

## Étape 0 — Le CNI applique-t-il les NetworkPolicy ?

Une `NetworkPolicy` est un objet API. **Seul le CNI** (le plugin réseau des nœuds) la traduit en règles. Sans enforcement, `kubectl apply` réussit et **le trafic passe quand même**.

Sur DKS le CNI est **Cilium** (il applique les policies). Vérifiez-le :

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Résultat attendu :**

- **DKS (Cilium)** : au moins un pod `cilium-…` `Running` (DaemonSet, un par nœud). Les `wget -T 3` des étapes 2–3 **doivent** timeout / réussir selon la policy.
- **kind par défaut** : *No resources found* pour ce label — vous verrez `kindnet-…` dans `kubectl get pods -n kube-system`. Les **anciennes** kindnet ignoraient les NetworkPolicy. **Depuis kind v0.24** (2024), kindnetd embarque `kube-network-policies` et **peut** les appliquer. D'où le test empirique : si après `deny-all` le `wget` répond encore, le CNI n'enforce pas (`check.sh` affiche alors un `WARN` et sort 0).

Si votre kubeconfig stagiaire n'autorise pas `kube-system`, demandez au formateur (cluster partagé) ou croyez l'affichage Door / Lab 02 : DKS = Cilium.

---

## Étape 1 — Workloads, aucune policy

```bash
kubectl apply -n "$NS" -f frontend.yaml -f backend.yaml -f intrus.yaml
kubectl wait -n "$NS" --timeout=120s --for=condition=Available deploy/frontend deploy/backend
kubectl wait -n "$NS" --timeout=120s --for=condition=Ready pod/intrus
kubectl get -n "$NS" pods,svc
```

**Résultat attendu :** `frontend-…` et `backend-…` `1/1 Running`, pod `intrus` `Running`, Service `backend` ClusterIP port `8080`.

Le frontend est un Nginx (client `wget` inclus dans l'image Alpine). Le backend est `agnhost netexec` sur **8080**. L'`intrus` est un `busybox:1.36` qui dort. Les labels qui comptent pour la suite : `role=frontend`, `role=backend`, `role=intrus`.

Sondez **depuis** chaque source (c'est l'IP/identité du pod qui sera filtrée). Si le premier `wget` échoue alors que les pods sont Ready, attendez 5–10 s : le CNI (surtout Cilium en remplacement de kube-proxy) programme le ClusterIP avec un léger décalage.

```bash
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
kubectl -n "$NS" exec pod/intrus -- wget -q -O- -T 3 http://backend:8080
```

```bash
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
kubectl -n "$NS" exec pod/intrus -- wget -q -O- -T 3 http://backend:8080
```

**Résultat attendu :** les deux commandes affichent une page/texte (agnhost) et **exit 0**. Sans NetworkPolicy, tout le namespace peut joindre le Service.

---

## Étape 2 — `deny-all` (Ingress)

```bash
kubectl apply -n "$NS" -f deny-all.yaml
kubectl get -n "$NS" networkpolicy
```

Le manifeste sélectionne **tous** les pods du namespace (`podSelector: {}`) et déclare `policyTypes: [Ingress]` **sans** règle `ingress:` — donc **aucune** entrée n'est autorisée.

Dès qu'**au moins une** NetworkPolicy Ingress sélectionne un pod, le trafic entrant vers ce pod est **refusé par défaut**, sauf allow explicite.

```bash
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
kubectl -n "$NS" exec pod/intrus -- wget -q -O- -T 3 http://backend:8080
```

**Résultat attendu (Cilium / CNI enforceur) :** les deux `wget` **échouent** au bout de ~3 s (`wget: download timed out`). C'est le succès pédagogique.

**Résultat si le CNI n'enforce pas :** les deux `wget` **réussissent encore**. L'objet `deny-all` est bien dans l'API (`kubectl get netpol -n "$NS"`) mais le dataplane l'ignore. `./check.sh` affiche alors `WARN: CNI sans NetworkPolicy (kindnet) — assertions d'isolation ignorées`.

---

## Étape 3 — Allow : seulement `role=frontend`

Les NetworkPolicy d'un même type (Ingress) qui sélectionnent un pod sont **unies** (union des `ingress:`). On ajoute une policy qui autorise le backend à recevoir du TCP/8080 **uniquement** depuis les pods `role=frontend` du **même namespace**.

```bash
kubectl apply -n "$NS" -f allow-frontend.yaml
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
kubectl -n "$NS" exec pod/intrus -- wget -q -O- -T 3 http://backend:8080
```

**Résultat attendu (Cilium) :** frontend **OK** ; `intrus` **timeout**. L'intrus n'a pas le label `role=frontend`.

**CNI sans enforcement :** les deux réussissent encore — même `WARN` qu'à l'étape 2.

---

## Étape 4 — (Optionnel) Egress et DNS

Jusqu'ici on n'a touché que **Ingress** (qui peut entrer dans un pod). L'**egress** (qui sort d'un pod) reste ouvert : résolution DNS, internet, etc.

```bash
kubectl apply -n "$NS" -f deny-egress.yaml
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
```

**Pourquoi le DNS casse :** `deny-egress` sélectionne tous les pods et déclare `policyTypes: [Egress]` **sans** règle `egress:`. Plus aucun paquet sortant n'est autorisé, y compris vers **CoreDNS** (`kube-system`, UDP/TCP **53**). `wget http://backend:8080` ne résout plus le nom `backend` : message du type `wget: bad address 'backend'` (souvent **plus rapide** qu'un timeout TCP).

Sans nom, pas de connexion au Service. Même un allow Ingress côté backend ne suffit pas si le client ne résout plus.

Ré-autoriser DNS (pods `k8s-app=kube-dns` dans `kube-system`) **et** le TCP vers le backend :

```bash
kubectl apply -n "$NS" -f allow-egress-dns.yaml
kubectl -n "$NS" exec deploy/frontend -- wget -q -O- -T 3 http://backend:8080
```

**Résultat attendu (Cilium) :** le frontend rejoint à nouveau `http://backend:8080` (union des règles egress). L'`intrus` reste bloqué en **ingress** sur le backend (étape 3).

---

## Pièges

- **CNI ≠ API.** `kubectl apply` d'une NetworkPolicy ne prouve pas l'isolation. Vérifiez Cilium (étape 0) ou un `wget -T 3` qui timeout.
- **CNI.** DKS : Cilium (kube-proxy souvent remplacé). kind : kindnet ; selon la version, l'isolation marche ou non — croyez le `wget -T 3`, pas le nom du CNI. Ne pas installer Calico « en plus » sur le cluster de formation.
- **Namespace.** Une NetworkPolicy ne s'applique qu'à **son** namespace. `podSelector: {}` = tous les pods de `$NS`, pas du cluster.
- **Identité = labels du Pod**, pas le nom du Deployment. Un `kubectl run` sans `role=frontend` est un intrus.
- **Ingress vs Egress.** Deny Ingress : on n'entre plus. Deny Egress : on ne sort plus, **donc plus de DNS**.
- **`wget -T 3`** est l'option timeout de **BusyBox** (Alpine / `busybox:1.36`). Ce n'est pas GNU wget. Sur macOS l'hôte n'a souvent pas `timeout(1)` : on n'en a pas besoin, `wget` tourne **dans** le pod.
- Ne jamais poser une NetworkPolicy sur `default` ou `kube-system` (le lab d'origine le faisait — à ne pas reproduire).
- `metadata.namespace` est **absent** des YAML : on passe toujours `-n "$NS"`.

## Nettoyage

```bash
kubectl delete namespace "$NS"
```

Les images peuvent rester en cache nœud pour la suite.

Vérification automatique (crée un namespace éphémère, le supprime à la fin). Si le CNI n'applique pas les policies, elle affiche le `WARN` et sort 0 après avoir appliqué les manifests ; sinon elle asserte deny/allow :

```bash
./check.sh
```

## Pour aller plus loin

- `CiliumNetworkPolicy` (CRD) : filtres L7 (HTTP path, DNS FQDN). Hors scope de ce lab : on reste sur `networking.k8s.io/v1`.
- Hubble (observabilité L3/L4/L7) est souvent déployé sur DKS ; `hubble observe` montre les drops `Policy denied`.
- Une policy `from.namespaceSelector` autorise un autre namespace (ex. ingress controller) — utile en prod, dangereux si le sélecteur est trop large.
