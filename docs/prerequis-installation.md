# À faire avant mercredi 9h

Ce document s’adresse à **chaque stagiaire**, sur **votre propre laptop**. Aucune machine virtuelle n’est fournie. Comptez 20 à 40 minutes selon l’OS, plus un redémarrage sous Windows.

Objectif : le matin du Jour 1, ces trois commandes fonctionnent déjà dans un terminal Unix :

```bash
docker run hello-world
docker compose version
git --version
```

Si vous **n’avez pas les droits administrateur** sur votre poste, ne perdez pas de temps : prévenez-nous et lisez [plan-b.md](plan-b.md).

---

## a) macOS (Intel ou Apple Silicon)

### 1. Docker Desktop

1. Télécharger l’installateur adapté à **votre processeur** (pas l’autre) :
   - **Apple Silicon** (M1, M2, M3, M4) : [Docker Desktop pour Mac (Apple Silicon)](https://docs.docker.com/desktop/setup/install/mac-install/)
   - **Intel** : [Docker Desktop pour Mac (Intel)](https://docs.docker.com/desktop/setup/install/mac-install/)
2. Ouvrir le `.dmg`, glisser Docker dans Applications, lancer **Docker**.
3. Accepter les invitations (réseau, liens symboliques) : un compte administrateur macOS est demandé.
4. Licence : Docker Desktop est **gratuit** pour les organisations de **moins de 250 salariés** (et moins de 10 M$ de chiffre d’affaires). Choisissez l’usage professionnel / organisation si l’assistant le demande.
5. Dans Docker Desktop → Settings → Resources : allouer **au moins 4 Go de RAM** (8 Go si la machine le permet), puis Apply & Restart.

Attendre que l’icône de la baleine soit **stable** (moteur démarré).

### 2. Terminal et Git

Ouvrir **Terminal** (ou iTerm). Pas besoin de Linux.

```bash
git --version
```

Si macOS propose d’installer les **outils de ligne de commande Xcode**, accepter et attendre la fin. Puis :

```bash
docker version
docker compose version
docker run hello-world
```

### 3. Cloner le dépôt

```bash
cd ~
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
cd formation-docker-kubernetes
```

---

## b) Windows 10 22H2 / Windows 11

Les commandes de la formation se tapent dans un **terminal Ubuntu (WSL)** ou, à défaut, **Git Bash**. **Pas dans PowerShell, pas dans cmd.exe** : les substitutions `$(…)`, les fins de ligne `\`, `curl` et les chemins de bind mount n’y fonctionnent pas comme dans les énoncés.

### 1. Activer WSL2 (droits administrateur)

Ouvrir **PowerShell en administrateur** :

```powershell
wsl --install
```

Redémarrer lorsque Windows le demande. Après le redémarrage, terminer la création du compte **Ubuntu** (utilisateur Linux + mot de passe : ce n’est pas le mot de passe Windows).

Vérifier :

```powershell
wsl --status
```

La version par défaut doit être **2**. Si Ubuntu n’est pas installé :

```powershell
wsl --install -d Ubuntu
```

### 2. Docker Desktop (backend WSL2)

1. Installer [Docker Desktop pour Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
2. Pendant l’installation, laisser **Use WSL 2 instead of Hyper-V** coché.
3. Démarrer Docker Desktop, accepter le contrat (licence gratuite si organisation < 250 salariés).
4. Settings → General : **Use the WSL 2 based engine**.
5. Settings → Resources → WSL Integration : **activer l’intégration pour Ubuntu**, Apply & Restart.

Allouer **4 Go de RAM** (Settings → Resources) si le curseur est proposé.

### 3. Travailler dans Ubuntu (WSL), pas sous `/mnt/c`

Ouvrir **Ubuntu** depuis le menu Démarrer (ou Windows Terminal → profil Ubuntu). Toutes les commandes ci-dessous, et **toutes celles des labs**, se tapent **ici**.

```bash
git --version
```

Si `git` est absent :

```bash
sudo apt update
sudo apt install -y git
```

Configurer les fins de ligne (une seule fois) :

```bash
git config --global core.autocrlf input
```

Cloner **dans le home Linux**, pas dans `/mnt/c/...` (bind mounts et performances) :

```bash
cd ~
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
cd formation-docker-kubernetes
```

### 4. Test

Toujours dans Ubuntu (WSL) :

```bash
docker version
docker compose version
docker run hello-world
```

Si `docker` est introuvable : Settings Docker Desktop → WSL Integration → Ubuntu coché, puis fermer et rouvrir le terminal Ubuntu.

---

## c) Linux

### Ubuntu (Docker Engine, dépôt officiel, keyrings)

Ne plus utiliser `apt-key`. Commandes à coller telles quelles (droits sudo) :

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

### Debian (même méthode keyrings)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Ajouter votre utilisateur au groupe `docker` (déjà dans les blocs ci-dessus), **puis vous déconnecter et reconnecter** (ou redémarrer). Sans relogin, `docker` demandera encore `sudo`. Vérification après reconnexion :

```bash
docker version
docker compose version
docker run hello-world
```

Git :

```bash
sudo apt-get install -y git
cd ~
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
```

### Fedora

```bash
sudo dnf -y install dnf-plugins-core git
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Déconnexion / reconnexion, puis les mêmes tests `docker version`, `docker compose version`, `docker run hello-world`.

---

## d) Compte Docker Hub (obligatoire en salle)

Créez un compte **gratuit** sur [hub.docker.com](https://hub.docker.com/signup) et, dans le même terminal que les labs :

```bash
docker login
```

Sans compte, Docker Hub limite à **10 pulls par heure et par adresse IP**. Avec un compte authentifié : **100 pulls par heure**. En salle, tout le monde sort souvent **par la même IP** : sans `docker login`, le deuxième ou troisième stagiaire verra `toomanyrequests`.

La veille, sur votre Wi-Fi personnel (après `docker login`) :

```bash
cd ~/formation-docker-kubernetes
bash scripts/prepull.sh
```

---

## e) Checklist à renvoyer au formateur

Envoyez (mail ou chat) **la sortie complète** de ces deux commandes, lancées dans le terminal Unix qui servira pendant la formation :

```bash
docker version
docker compose version
```

Indiquez aussi : OS (macOS Apple Silicon / Intel, Windows 10/11 + WSL Ubuntu, Ubuntu, Fedora) et si `docker run hello-world` a réussi.

Si vous n’avez pas les droits admin sur votre poste, prévenez-nous : voir [plan-b.md](plan-b.md).
