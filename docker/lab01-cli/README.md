# Lab 01 — Docker CLI

**Durée estimée :** 20 minutes

## Objectifs

- Verifier que Docker fonctionne sur votre laptop (version client + moteur).
- Lancer un premier conteneur (`hello-world`) puis explorer images et conteneurs.
- Publier un service web Nginx sur le port hote **8080**.
- Diagnostiquer avec `inspect --format`, `logs` et `exec`.
- Arreter et supprimer proprement le conteneur.

## Prérequis

- Docker Desktop (macOS / Windows) ou Docker Engine (Linux).
- Le test `docker run hello-world` a reussi (voir `docs/prerequis-installation.md`).
- `curl` (present sur macOS, Linux, WSL et Git Bash).
- **Windows :** tapez toutes les commandes dans un terminal **Ubuntu (WSL)** ou **Git Bash**, jamais dans PowerShell / cmd. Clonez ce depot dans le systeme de fichiers WSL (`~/`), pas sous `/mnt/c`.

```bash
cd docker/lab01-cli
```

---

## Étape 1 — Verifier l'installation

```bash
docker version
docker info
```

**Résultat attendu :** un bloc *Client* et un bloc *Server*. Si seul le client apparait, le moteur n'est pas demarre (lancez Docker Desktop, ou `sudo systemctl start docker` sous Linux).

> **Sur Docker Desktop (macOS/Windows)**
> `docker info` affiche les CPU / la RAM **alloues a la VM Linux** interne, pas ceux de votre Mac ou PC. Pour donner plus de RAM : icone Docker Desktop → Settings → Resources.

---

## Étape 2 — Premier conteneur : `hello-world`

```bash
docker run --name hello hello-world
```

**Résultat attendu :** un message qui commence par `Hello from Docker!`. L'image `hello-world` est telechargee au premier lancement (pas de tag figé : c'est le seul cas du cours ou `:latest` implicite est accepte).

---

## Étape 3 — Images locales

```bash
docker images
```

**Résultat attendu :** au moins `hello-world` dans la liste (colonnes REPOSITORY, TAG, IMAGE ID, SIZE).

---

## Étape 4 — Conteneurs, y compris arretes

```bash
docker ps -a
```

**Résultat attendu :** le conteneur `hello` est **Exited (0)**. Sans `--rm`, un conteneur reste visible apres son arret : c'est normal.

---

## Étape 5 — Supprimer le conteneur arrete

```bash
docker rm hello
docker ps -a
```

**Résultat attendu :** `hello` a disparu. L'image `hello-world` reste (une image n'est pas un conteneur).

---

## Étape 6 — Un service web en arriere-plan

```bash
docker run -d --name web -p 8080:80 nginx:1.27-alpine
docker ps
```

**Résultat attendu :** `web` est `Up`, avec `0.0.0.0:8080->80/tcp` (parfois aussi `[::]:8080`).

> **Sur Docker Desktop (macOS/Windows)**
> Si le port 8080 est deja pris (`port is already allocated`), changez le port **hote** uniquement : `-p 8088:80`. Le 80 a droite est le port **dans** le conteneur (Nginx), il ne change pas.
> Sous macOS, AirPlay Receiver occupe souvent le port **5000** (sans rapport avec ce lab, mais retenez-le pour le Lab 02).

---

## Étape 7 — Verifier Nginx

Depuis le terminal :

```bash
curl http://127.0.0.1:8080
```

**Résultat attendu :** le HTML de la page d'accueil Nginx (`Welcome to nginx!`).

Vous pouvez aussi ouvrir un navigateur : [http://localhost:8080](http://localhost:8080) (pratique sous Windows / macOS).

> **Sur Docker Desktop (macOS/Windows)**
> `localhost:8080` fonctionne grace au **port mapping** (`-p`). L'adresse IP interne du conteneur (`172.x.x.x`) n'est **pas** joignable depuis le Mac / Windows : elle vit dans la VM Linux. Utilisez toujours `localhost` + le port publie.

---

## Étape 8 — Inspecter avec `--format`

`docker inspect web` dump un JSON long. Pour extraire un champ :

```bash
docker inspect --format '{{.State.Status}}' web
docker inspect --format '{{.Config.Image}}' web
docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web
```

**Résultat attendu :** `running`, puis `nginx:1.27-alpine`, puis une IPv4 (`172.…`). Le modele entre `{{ }}` est du Go text/template.

---

## Étape 9 — Journaux

```bash
docker logs web
```

**Résultat attendu :** des lignes Nginx du type `start worker processes`. Apres le `curl` de l'etape 7, une ligne d'acces HTTP apparait aussi.

Sans `-f` : la commande rend la main. Avec `-f` (follow), Ctrl+C pour quitter — ne bloquez pas votre terminal pendant le lab.

---

## Étape 10 — Executer une commande dans le conteneur

Sans TTY (scripts, CI, Git Bash) :

```bash
docker exec web cat /usr/share/nginx/html/index.html
docker exec web nginx -t
```

**Résultat attendu :** le HTML de la page d'accueil, puis `syntax is ok` / `test is successful`.

Depuis un vrai terminal interactif (optionnel) :

```bash
docker exec -it web sh
```

Dans le shell du conteneur : `ls /usr/share/nginx/html` puis `exit`.

> **Sur Docker Desktop (macOS/Windows)**
> N'utilisez `-it` que dans un terminal interactif. Sous Git Bash, si `-it` echoue (TTY), relancez **sans** `-it`, ou prefixez par `winpty` : `winpty docker exec -it web sh`.

---

## Étape 11 — Arret et suppression

```bash
docker stop web
docker rm web
docker ps -a
```

Equivalent en une commande : `docker rm -f web` (envoie un SIGKILL si besoin).

**Résultat attendu :** plus aucun conteneur `web`. L'image `nginx:1.27-alpine` reste en local pour la suite du cours.

---

## Aide-memoire — drapeaux de `docker run`

| Drapeau | Role | Exemple |
|---|---|---|
| `-d` | Detache (arriere-plan) | `docker run -d nginx:1.27-alpine` |
| `--name` | Nom stable (sinon un nom aleatoire) | `--name web` |
| `-p hote:conteneur` | Publier un port | `-p 8080:80` |
| `--rm` | Supprimer le conteneur a l'arret | `docker run --rm alpine:3.20 echo ok` |
| `-it` | STDIN + TTY (shell interactif) | `docker run -it alpine:3.20 sh` |
| `-e` | Variable d'environnement | `-e MODE=lab` |
| `-v` | Volume / bind mount | `-v "$(pwd)/data:/data"` |
| `--network` | Reseau (Lab 03) | `--network app-net` |
| `--restart` | Politique de relance | `--restart unless-stopped` |
| `--memory` | Plafond RAM cgroup | `--memory 128m` |
| `--user` | UID:GID dans le conteneur | `--user 1000:1000` |
| `--platform` | Architecture (Lab 02, Apple Silicon) | `--platform linux/amd64` |

Toujours ecrire `$(pwd)` (et pas `$PWD`) dans un bind mount : plus previsibles sous bash, zsh, WSL et Git Bash. Sous Git Bash, si un chemin de conteneur (`/data`) est reecrit en `C:\Program Files\Git\...`, prefixez la commande par `MSYS_NO_PATHCONV=1`.

---

## Pour aller plus loin

- `docker ps --filter name=web --format '{{.Names}} {{.Status}} {{.Ports}}'`
- `docker inspect --format '{{.HostConfig.PortBindings}}' web`
- `docker system df` : espace disque utilise par images, conteneurs, volumes, cache de build.
- Difference `docker stop` (SIGTERM, puis SIGKILL apres 10 s) vs `docker kill` (SIGKILL immediat).

## Nettoyage

```bash
docker rm -f hello web
```

Les images `hello-world` et `nginx:1.27-alpine` peuvent rester.

Verification automatique (non interactive, moins de 5 min) :

```bash
./check.sh
```
