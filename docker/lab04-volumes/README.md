# Lab 04 — Persistance avec des volumes

**Durée estimée :** 30 minutes

## Objectifs

- Distinguer volume nommé, bind mount et `tmpfs`.
- Créer un volume nommé (`db-data`) et y faire persister PostgreSQL 16.
- Vérifier la persistance : supprimer le conteneur, en relancer un autre **sur le même volume**, retrouver les données.
- Servir un site statique via un bind mount en lecture seule.
- Inspecter un volume (`docker volume inspect`) et utiliser la syntaxe `--mount`.

## Prérequis

- Docker fonctionne (`docker version`, `docker run hello-world` déjà OK).
- Terminal : macOS (Terminal / iTerm, zsh ou bash), **Windows : Ubuntu WSL ou Git Bash** (pas PowerShell), Linux : bash.
- `curl` et `openssl` (souvent déjà installés).
- Images utilisées : `postgres:16`, `nginx:1.27-alpine`, `alpine:3.20` (tag figé, jamais `:latest`).
- Compte Docker Hub + `docker login` recommandé (rate-limit de la salle).

Depuis la racine du dépôt cloné :

```bash
cd docker/lab04-volumes
```

Sous Windows, clonez le dépôt **dans le système de fichiers Linux de WSL** (`~/...`), pas sous `/mnt/c`.

---

## Étape 1 — Mot de passe et volume nommé

On ne commite **aucun** mot de passe. Générez-en un pour cette session, ou utilisez l'exemple pédagogique :

```bash
export PGPASS="$(openssl rand -base64 12)"
# alternative pédagogique (valeur d'exemple, pas un secret) :
# export PGPASS=ChangeMe-lab
echo "Mot de passe de cette session : (conservez PGPASS dans ce terminal)"
```

Liste des volumes, puis création de `db-data` :

```bash
docker volume ls
docker volume create db-data
docker volume ls
```

**Résultat attendu :** `db-data` apparaît dans `docker volume ls` (driver `local`).

---

## Étape 2 — PostgreSQL sur le volume

Le répertoire de données de l'image officielle est `/var/lib/postgresql/data`. On le branche sur le volume nommé :

```bash
docker run -d --name db \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD="$PGPASS" \
  postgres:16
```

PostgreSQL n'accepte les connexions qu'après l'init. Boucle d'attente **sans** la commande `timeout` (absente sur macOS) :

```bash
until docker exec db pg_isready -U postgres; do
  sleep 1
done
```

**Résultat attendu :** `accepting connections`. `docker ps` montre `db` en `Up`.

> **Sur Docker Desktop (macOS/Windows)**  
> Le moteur tourne dans une petite VM Linux. Le volume `db-data` est stocké **dans cette VM**, pas dans un dossier macOS/Windows visible. C'est volontaire : le volume survit au `docker rm` du conteneur, pas à `docker volume rm`.

---

## Étape 3 — Base `formation`, table et une ligne

```bash
docker exec db psql -U postgres -c "CREATE DATABASE formation;"
docker exec db psql -U postgres -d formation -c "CREATE TABLE notes (id serial PRIMARY KEY, message text NOT NULL);"
docker exec db psql -U postgres -d formation -c "INSERT INTO notes (message) VALUES ('bonjour-volume');"
docker exec db psql -U postgres -d formation -c "SELECT message FROM notes;"
```

**Résultat attendu :** `CREATE DATABASE`, `CREATE TABLE`, `INSERT 0 1`, puis une ligne `bonjour-volume`.

(Pas besoin de `-it` ici : `psql -c` n'est pas interactif.)

---

## Étape 4 — Inspecter le volume

```bash
docker volume inspect db-data
```

Repérez `Name`, `Driver` (`local`) et `Mountpoint`.

> **Sur Docker Desktop (macOS/Windows)**  
> Le `Mountpoint` ressemble à `/var/lib/docker/volumes/db-data/_data`. Ce chemin est **celui de la VM Desktop**, pas de votre Mac ou PC. Vous ne pouvez pas l'ouvrir dans le Finder ou l'Explorateur. Pour voir les fichiers, montez le volume dans un conteneur (étape 8).

**Résultat attendu :** JSON avec `"Name": "db-data"` et un `Mountpoint` non vide.

---

## Étape 5 — Supprimer `db`, relancer `db2` sur le même volume

Le mot de passe a déjà été écrit dans le volume au premier démarrage. On le repasse quand même pour rester explicite.

```bash
docker rm -f db
docker run -d --name db2 \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD="$PGPASS" \
  postgres:16
```

```bash
until docker exec db2 pg_isready -U postgres; do
  sleep 1
done
docker exec db2 psql -U postgres -d formation -c "SELECT message FROM notes;"
```

**Résultat attendu :** la ligne `bonjour-volume` est **toujours là**. Le volume a survécu au `docker rm -f db`. Le nouveau conteneur `db2` n'a fait que **réattacher** les mêmes fichiers.

Si `CREATE DATABASE` avait été refait ici, PostgreSQL dirait que `formation` existe déjà — preuve supplémentaire que ce n'est pas une instance vide.

---

## Étape 6 — Bind mount : Nginx sert `html/`

Le dossier `html/` de ce lab contient une page statique. On la monte en **lecture seule** dans Nginx. `$(pwd)` (et pas un chemin figé) reste correct sur macOS, Linux et WSL :

```bash
docker run -d --name web-bind \
  -p 8084:80 \
  -v "$(pwd)/html:/usr/share/nginx/html:ro" \
  nginx:1.27-alpine
```

```bash
curl -s http://127.0.0.1:8084
```

**Résultat attendu :** le HTML contient `Hello depuis un bind mount`.

Modifiez `html/index.html` (un mot dans le `<h1>`), puis `curl` à nouveau : la page change **sans** rebuild d'image. C'est tout l'intérêt du bind mount pour le développement.

Tentative d'écriture depuis le conteneur (doit échouer, drapeau `:ro`) :

```bash
docker exec web-bind touch /usr/share/nginx/html/interdit.txt || echo "écriture refusée (attendu)"
```

> **Sur Docker Desktop (macOS/Windows)**  
> Les bind mounts passent par la couche de partage de fichiers de Desktop (plus lents qu'un volume nommé).  
> **macOS :** Docker Desktop → Settings → Resources → File sharing : le dossier du dépôt doit être dans la liste (le home l'est en général).  
> **Windows :** travaillez dans WSL (`~/...`). Un clone sous `/mnt/c/...` rend le bind mount lent, voire vide.  
> Si `curl` montre la page par défaut Nginx (« Welcome to nginx ») au lieu de `Hello depuis un bind mount`, le montage n'a pas pris : vérifiez `$(pwd)/html` et le file sharing.

---

## Étape 7 — `tmpfs` : disque qui meurt avec le conteneur

`tmpfs` est un système de fichiers **en RAM**, dans le namespace de montage du conteneur. Rien n'est écrit sur l'hôte.

```bash
docker run --rm --tmpfs /scratch alpine:3.20 sh -c 'echo volatile > /scratch/x && cat /scratch/x && mount | grep /scratch'
```

**Résultat attendu :** `volatile`, et une ligne `tmpfs on /scratch`. Relancez la même commande : `/scratch/x` n'existe plus (nouveau conteneur = nouveau tmpfs vide).

Utile pour secrets éphémères, caches, `--read-only` (lab 05).

---

## Étape 8 — Syntaxe `--mount` (équivalent moderne de `-v`)

`-v` est court. `--mount` est plus explicite (type, source, target, `readonly`).

Lister les fichiers **du volume** sans relancer Postgres :

```bash
docker run --rm \
  --mount type=volume,src=db-data,dst=/data \
  alpine:3.20 ls /data
```

**Résultat attendu :** entre autres `PG_VERSION` (contenu `16`) et les répertoires PostgreSQL. Vous « voyez » le volume sans passer par le `Mountpoint` hôte.

Équivalent bind (lecture seule) :

```bash
docker run --rm --name web-mount \
  -p 8085:80 \
  --mount type=bind,src="$(pwd)/html",dst=/usr/share/nginx/html,readonly \
  nginx:1.27-alpine
```

```bash
curl -s http://127.0.0.1:8085
docker rm -f web-mount
```

**Résultat attendu :** même page que l'étape 6.

Rappel des trois types :

| Type | `--mount` | Survit au `docker rm` ? | Visible sur l'hôte ? |
|---|---|---|---|
| Volume nommé | `type=volume,src=NOM,dst=...` | oui, jusqu'à `docker volume rm` | via un conteneur ; pas le Finder sous Desktop |
| Bind | `type=bind,src=$(pwd)/dir,dst=...` | ce sont vos fichiers | oui, le dossier du projet |
| tmpfs | `type=tmpfs,dst=/scratch` | non | non (RAM du conteneur) |

---

## Pour aller plus loin

- Volume **anonyme** : `docker run -v /var/lib/postgresql/data ...` sans nom — Docker crée un volume au hash illisible ; évitez-le en formation et en prod.
- `docker volume prune` : supprime les volumes **non** utilisés par un conteneur. Dangereux si vous avez arrêté Postgres sans le supprimer.
- Compose : clé `volumes:` au niveau service + volume nommé en bas de fichier (lab 07).
- Drivers : `local` suffit ici ; NFS / cloud sont des plugins (hors scope Jour 1).

## Nettoyage

```bash
docker rm -f db db2 web-bind web-mount 2>/dev/null
docker volume rm db-data
docker volume ls
```

Les images (`postgres:16`, `nginx:1.27-alpine`, `alpine:3.20`) peuvent rester en local pour la suite.

Vérification automatique (non interactif, idempotent) :

```bash
./check.sh
```
