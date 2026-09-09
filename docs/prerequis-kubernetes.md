# Prérequis Kubernetes (avant le Jour 2)

Ce document s’adresse à **chaque stagiaire**, sur **votre propre laptop**. Comptez 15 à 30 minutes. Le Jour 1 (Docker) doit déjà fonctionner.

Objectif : le matin du Jour 2, ces commandes fonctionnent dans le **même terminal Unix** que les labs Docker (Terminal macOS, **Ubuntu WSL**, shell Linux — pas PowerShell) :

```bash
kubectl version --client
helm version
```

`kubectl` doit être dans la même **mineure ± 1** que le cluster (DKS en 1.35–1.37). La version client stable au moment de la rédaction est lue ici : [https://dl.k8s.io/release/stable.txt](https://dl.k8s.io/release/stable.txt) (méthode officielle Kubernetes).

Si vous **n’avez pas les droits administrateur**, lisez [plan-b-kubernetes.md](plan-b-kubernetes.md) et prévenez le formateur.

---

## Compte Door

Créer un compte sur https://door.cloud (invitation envoyée par le formateur) — voir [docs/dks-creer-cluster.md](dks-creer-cluster.md).

Sans ce compte, le Lab 1 (création du cluster DKS) est impossible. Le formateur envoie l’invitation **avant** le Jour 2.

---

## kubectl

Documentation officielle : [Installer kubectl](https://kubernetes.io/docs/tasks/tools/). Toujours la version pointée par `https://dl.k8s.io/release/stable.txt` (ou le dépôt `pkgs.k8s.io` de la mineure courante), pas un paquet Ubuntu/Debian périmé.

**Docker Desktop** (macOS et Windows) livre déjà un binaire `kubectl`. S’il apparaît dans votre terminal Unix (`command -v kubectl`) et que `kubectl version --client` affiche une 1.35–1.37, vous pouvez le garder. Sinon, installez le binaire officiel comme ci-dessous — et, sous Windows, **dans Ubuntu WSL**, pas dans PowerShell.

### macOS (Homebrew)

```bash
brew install kubectl
kubectl version --client
```

Équivalent : `brew install kubernetes-cli`.

### macOS (curl, méthode officielle)

Apple Silicon :

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --client
```

Intel : remplacez `darwin/arm64` par `darwin/amd64`.

### Windows : uniquement dans Ubuntu (WSL)

Les labs se tapent dans **Ubuntu WSL**. N’installez pas kubectl « pour Windows » (Chocolatey, winget, `kubectl.exe` dans PowerShell) comme outil principal : chemins, kubeconfig et `port-forward` divergeraient des énoncés.

Ouvrez **Ubuntu** (menu Démarrer), puis **une** des deux méthodes.

**Dépôt apt officiel** (`pkgs.k8s.io`, mineure courante — ici v1.37, à aligner sur [stable.txt](https://dl.k8s.io/release/stable.txt) si la mineure a bougé) :

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
kubectl version --client
```

**curl** (amd64 ; `arm64` si votre WSL est ARM) :

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

Si Docker Desktop a déjà injecté `kubectl` dans WSL (intégration Ubuntu), `kubectl version --client` suffit : pas besoin de second binaire.

### Linux (apt / dnf)

**Debian / Ubuntu** : même dépôt `pkgs.k8s.io` que le bloc WSL ci-dessus, puis `sudo apt-get install -y kubectl`.

**Fedora / RHEL** (dépôt RPM officiel, mineure v1.37 à aligner sur stable.txt) :

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/repodata/repomd.xml.key
EOF
sudo dnf install -y kubectl
kubectl version --client
```

Alternative curl Linux amd64 :

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

---

## Helm 4

La formation utilise **Helm 4** (Lab 10). Vérifié le 9 septembre 2026 :

- Page officielle [Installing Helm](https://helm.sh/docs/intro/install/) : version affichée **4.2.4** ; script recommandé **`get-helm-4`** (`https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4`).
- `https://get.helm.sh/helm-latest-version` et `https://get.helm.sh/helm4-latest-version` répondent **v4.2.4**.
- Le script historique **`get-helm-3` existe toujours** mais installe **Helm 3 uniquement** (il lit `https://get.helm.sh/helm3-latest-version`, **v3.21.4** au même jour). **Ne l’utilisez pas** pour cette formation : ce n’est plus « le script qui installe la dernière Helm ».
- Homebrew `helm` : formule **4.2.4** (`formulae.brew.sh/api/formula/helm.json`).

### macOS (Homebrew)

```bash
brew install helm
helm version
```

### Script officiel `get-helm-4` (macOS, Linux, WSL)

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

Le binaire part dans `/usr/local/bin/helm` (sudo). Pour forcer une version : `./get_helm.sh --version v4.2.4`.

### Windows : uniquement dans Ubuntu (WSL)

Même script `get-helm-4` **dans le terminal Ubuntu**, pas Chocolatey / Scoop / winget sur l’hôte Windows.

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

### Linux (paquet distro)

`sudo dnf install helm` (Fedora) ou le dépôt apt communautaire documenté sur helm.sh peuvent livrer Helm 4 **ou encore Helm 3**. Après install, **vérifiez** `helm version` : la ligne doit commencer par `v4.`. En cas de v3, utilisez `get-helm-4`.

---

## Autocomplétion et alias `k`

Dans le shell des labs (bash ou zsh). Documentation : [Enable shell autocompletion](https://kubernetes.io/docs/tasks/tools/included/optional-kubectl-configs-bash-linux/).

**bash** (Linux / WSL ; sur macOS, bash 4.1+ et `bash-completion@2` sont requis — le bash 3.2 d’Apple ne suffit pas) :

```bash
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc
source ~/.bashrc
```

**zsh** (défaut macOS) :

```bash
echo 'source <(kubectl completion zsh)' >>~/.zshrc
echo 'alias k=kubectl' >>~/.zshrc
source ~/.zshrc
```

Si zsh affiche `command not found: compdef`, ajoutez **en tête** de `~/.zshrc` :

```bash
autoload -Uz compinit
compinit
```

Vérification : tapez `k get n` puis Tab → `nodes` / `namespaces`.

---

## Où va le kubeconfig

`kubectl` lit, dans l’ordre :

1. la variable **`KUBECONFIG`** si elle est définie ;
2. sinon **`~/.kube/config`**.

Après le Lab 1, vous téléchargez un YAML depuis la console Door (voir [dks-kubeconfig.md](dks-kubeconfig.md)). Deux habitudes valides :

```bash
mkdir -p ~/.kube
mv ~/Downloads/dks-<cluster>.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

ou, sans écraser un config déjà présent :

```bash
export KUBECONFIG=~/Downloads/dks-<cluster>.yaml
```

Ajoutez l’`export` dans `~/.bashrc` / `~/.zshrc` si vous le gardez ainsi. Vérification :

```bash
kubectl cluster-info
kubectl get nodes
```

### Windows / WSL : pas sous `/mnt/c`

1. Téléchargez le fichier depuis le navigateur Windows (souvent `C:\Users\<vous>\Downloads\`).
2. **Copiez-le dans le home Linux** :

```bash
mkdir -p ~/.kube
cp /mnt/c/Users/<vous>/Downloads/dks-<cluster>.yaml ~/.kube/dks.yaml
chmod 600 ~/.kube/dks.yaml
export KUBECONFIG=~/.kube/dks.yaml
```

3. Ne laissez pas `KUBECONFIG` pointer vers `/mnt/c/...` : permissions, verrous OneDrive/antivirus et lenteur. `chmod 600` sur un fichier NTFS via `/mnt/c` ne se comporte pas comme sur ext4.

Le fichier contient des **certificats et tokens**. Ne le commitez jamais, ne le collez pas dans un chat public.

---

## k9s (optionnel)

Interface terminal pour explorer le cluster. Utile, **pas exigé**.

```bash
# macOS
brew install k9s

# Linux / WSL : voir https://k9scli.io/topics/install/
```

Puis `k9s` (respecte `KUBECONFIG`). Raccourcis : `:ns` pour changer de namespace, `q` pour quitter.

---

## Checklist à renvoyer au formateur

Envoyez la sortie de :

```bash
kubectl version --client
helm version
```

Indiquez l’OS (macOS Apple Silicon / Intel, Windows + Ubuntu WSL, Ubuntu, Fedora) et si le compte Door est créé. Le `kubectl get nodes` se fait **en séance** au Lab 1, une fois le cluster prêt.
