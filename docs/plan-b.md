# Plan B — laptop sans droits admin ou installation impossible

Le chemin normal est [prerequis-installation.md](prerequis-installation.md) sur **votre laptop**. Si Docker Desktop / WSL / le moteur Linux ne peuvent pas s’installer (poste verrouillé, politique d’entreprise, disque plein, VPN qui casse le moteur), suivez **dans l’ordre** les options ci-dessous et prévenez le formateur.

## 1. Play with Docker (compte Docker Hub, 4 heures)

Site : [labs.play-with-docker.com](https://labs.play-with-docker.com)

1. Créez un compte gratuit [hub.docker.com](https://hub.docker.com/signup) si ce n’est pas déjà fait.
2. Ouvrez Play with Docker, connectez-vous avec ce compte, cliquez sur **Start**.
3. Cliquez sur **+ ADD NEW INSTANCE** : un terminal Linux s’affiche dans le navigateur.
4. Clonez le dépôt **dans cette instance** :

```bash
git clone https://github.com/doorcloud/formation-docker-kubernetes.git
cd formation-docker-kubernetes
docker run hello-world
```

Limites à connaître :

- session d’environ **4 heures**, ensuite tout est perdu (re-cloner si besoin) ;
- **un seul terminal** par instance : pas d’onglets comme sur votre laptop ; ouvrez une deuxième instance seulement si le formateur le demande ;
- **pas d’AppArmor personnalisé** (lab 05 : étape AppArmor informative, comme sous Docker Desktop) ;
- les ports publiés s’ouvrent via les boutons de port de l’interface Play with Docker, pas via `localhost` de votre navigateur Windows/Mac de la même façon.

Play with Docker suffit pour les labs 01 à 07 si vous lisez les énoncés dans le README de chaque lab et collez les commandes dans ce terminal unique.

## 2. Binôme

Travaillez à deux sur le laptop **où Docker fonctionne**. Un seul `docker login` (compte Hub de la personne qui a la machine). Copiez les notes, pas les mots de passe personnels.

## 3. VM de secours DigitalOcean (formateur)

En dernier recours **opérationnel**, le formateur peut ouvrir une Ubuntu de secours (test / urgence uniquement — voir [infra/digitalocean/README.md](../infra/digitalocean/README.md)). Ce n’est **pas** le poste prévu pour tout le monde.

Connexion depuis votre laptop, une fois que le formateur vous a donné **l’adresse IP** et un fichier de **clé privée** (jamais commité dans git) :

```bash
ssh -i cle formation@IP
```

Remplacez `cle` par le chemin du fichier de clé, et `IP` par l’IPv4 indiquée.

### Windows : droits trop ouverts sur la clé (4 lignes)

OpenSSH sous Windows refuse une clé privée lisible par tout le monde. Dans **PowerShell**, dans le dossier qui contient le fichier `cle` :

```powershell
icacls cle /inheritance:r
icacls cle /grant:r "$($env:USERNAME):(R)"
icacls cle
ssh -i cle formation@IP
```

La troisième ligne doit montrer votre compte Windows en lecture seule, sans `Everyone`. Ensuite seulement la commande `ssh`.

Depuis **Terminal macOS** ou Ubuntu : `chmod 600 cle` puis `ssh -i cle formation@IP`.

Une fois connecté, les labs se déroulent comme sous Linux natif (`git clone` déjà fait par cloud-init, ou recloner le dépôt public).

## 4. Suivre sur l’écran du formateur

Si aucune des options précédentes n’est disponible, suivez la démonstration sur l’écran du formateur, prenez des notes, et refaites les labs le soir sur un poste où Docker s’installe (ou sur Play with Docker). Ce n’est pas équivalent à la pratique, mais vous gardez le fil du Jour 1.
