# Kubeconfig DKS

Comment récupérer le fichier d’accès au cluster Door Kubernetes Service et le brancher sur `kubectl` depuis **votre laptop**. Console en anglais.

---

## Télécharger le fichier

1. Console [door.cloud](https://door.cloud) → **Clusters** → ouvrez **votre** cluster binôme (`lab-binome-N`).
2. Onglet **Access & kubeconfig**.
3. Carte **Cluster Access** : le toggle doit être sur **Public** (pas **Private**). Si ce n’est pas le cas, **demandez au formateur** (ne basculez pas vous-même en séance : le changement est asynchrone et il faut **re-télécharger** le fichier ensuite).
4. Carte **Static kubeconfig (for CI)** → bouton **Download kubeconfig** (libellé exact, pas « Télécharger le kubeconfig »). Pendant l’attente : **Preparing download…**. Fichier typique : `{nom}-kubeconfig.yaml`.

![Onglet Access & kubeconfig : Public et Download kubeconfig](img/dks/09-access-kubeconfig.png)

Il existe aussi un bloc **Recommended: door CLI** (badge **Auto-rotating**) et **Install the CLI**. Pour les labs, le **kubeconfig statique** suffit.

L’API peut répondre d’abord **202** (*kubeconfig fetch requested*) puis le YAML : l’UI poll jusqu’au fichier. Disponible dès que le control plane est prêt, pas seulement à la fin du provisioning.

---

## Pourquoi **Public** est obligatoire sur un laptop

**Public** : l’entrée `server:` du kubeconfig pointe un nom `*.clusters.dks.door.africa` (TLS 443), joignable depuis Internet (salle, Wi‑Fi, 4G).

**Private** : le `server:` pointe une adresse **interne** au réseau Cloudoor. Depuis macOS, WSL ou Linux en salle, `kubectl` **timeout**.

Le toggle **Internet** / **Internal (VPN)** de l’étape **Review & Create** concerne les **applications** (dataplane), pas `kubectl`. Pour les labs, laissez **Internet** à la création ; l’accès API se règle ensuite sur **Access & kubeconfig**.

---

## Où ranger le fichier

Ne commitez **jamais** un kubeconfig. Le dépôt ignore déjà `kubeconfig*` (voir `.gitignore`).

### macOS / Linux

```bash
mkdir -p ~/.kube
mv ~/Downloads/<fichier>-kubeconfig.yaml ~/.kube/dks-lab.yaml
chmod 600 ~/.kube/dks-lab.yaml
```

### Windows (WSL)

Le navigateur Windows enregistre dans `C:\Users\<vous>\Downloads`. Dans **Ubuntu WSL** :

```bash
mkdir -p ~/.kube
mv /mnt/c/Users/<vous>/Downloads/<fichier>-kubeconfig.yaml ~/.kube/dks-lab.yaml
chmod 600 ~/.kube/dks-lab.yaml
```

Remplacez `<vous>` par votre profil Windows. Travaillez dans le home Linux (`~/`), pas sous `/mnt/c`.

### Droits

`chmod 600` : lecture/écriture pour vous seul. `kubectl` refuse parfois un fichier trop permissif (`warning: … is group/world-readable`).

---

## `KUBECONFIG` isolé vs fusion dans `~/.kube/config`

### Option A — fichier dédié (recommandé en formation)

```bash
export KUBECONFIG=~/.kube/dks-lab.yaml
kubectl config current-context
```

Mettez l’`export` dans `~/.bashrc` / `~/.zshrc` **uniquement** si vous n’avez pas d’autre cluster. Sinon, exportez-le dans le terminal de la formation seulement.

### Option B — fusionner dans `~/.kube/config`

```bash
KUBECONFIG=~/.kube/config:~/.kube/dks-lab.yaml kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config
chmod 600 ~/.kube/config
```

Sous Windows natif le séparateur serait `;` : **n’utilisez pas PowerShell** pour les labs ; dans WSL le séparateur reste `:`.

Puis :

```bash
kubectl config get-contexts
kubectl config use-context <nom-du-contexte-dks>
```

Le nom du contexte est celui du fichier téléchargé (souvent le nom du cluster). Vérifiez avec `get-contexts` plutôt que de l’inventer.

### Namespace par défaut dans le contexte

Après `kubectl create ns lab-<prenom>` (Lab 1) :

```bash
kubectl config set-context --current --namespace=lab-<prenom>
```

Les commandes suivantes sans `-n` ciblent votre namespace. `kube-system` exige toujours `-n kube-system`.

---

## Vérifier

```bash
kubectl cluster-info
kubectl get nodes
kubectl version
```

**Résultat attendu :**

- `cluster-info` : *control plane* joignable (URL publique DKS, pas un timeout).
- `get nodes` : au moins une ligne **Ready**.
- `version` : un bloc client et un bloc **Server**. Sur **DKS**, le serveur est en **v1.32.x**. (Un cluster kind local peut afficher une autre mineure, par ex. 1.37.)

Ne plus utiliser `kubectl version --short` (flag retiré).

---

## Dépannage

| Symptôme | Cause probable | Que faire |
|---|---|---|
| Timeout / hanging `cluster-info` | Cluster en **Private**, ou mauvais réseau | Formateur : **Public**, puis **re-télécharger** le kubeconfig |
| `x509: certificate signed by unknown authority` / `x509` | Mauvais fichier, fichier tronqué, ou `KUBECONFIG` qui pointe ailleurs | Vérifier `echo $KUBECONFIG` ; re-télécharger ; `chmod 600` |
| `Unauthorized` / `You must be logged in` | Jeton du fichier périmé ou fichier d’un autre cluster | **Download kubeconfig** à nouveau ; ne pas mélanger deux YAML |
| `The connection to the server … was refused` | Contexte kind/minikube éteint, ou `use-context` oublié | `kubectl config get-contexts` ; allumer kind **ou** repasser sur le contexte DKS |
| `Unable to connect to the server` juste après **Create Cluster** | Control plane pas encore prêt | Attendre **Control plane ready** / phase **Provisioned** (souvent 3–9 min) |

---

## Rotation et sécurité

- Le kubeconfig statique est un **secret** (certificats / jeton). Pas de Slack, pas de Git, pas de copier-coller dans un ticket.
- `.gitignore` du dépôt contient déjà `kubeconfig*`.
- Après un passage **Private** → **Public** (ou l’inverse), **re-téléchargez** : l’ancien `server:` est faux.
- En fin de formation, le formateur **supprime** les clusters : les fichiers locaux ne serviront plus. Vous pouvez `rm ~/.kube/dks-lab.yaml`.
- Pour un usage quotidien hors lab, le **door CLI** (auto-rotating) est préférable au fichier statique ; ce n’est pas exigé en salle.
