# Lab 07 — Docker Compose (nginx + PHP-FPM + MySQL)

**Durée estimée :** 35 minutes

## Objectifs

- Orchestrer plusieurs services avec **Docker Compose v2** (`docker compose`, pas `docker-compose`).
- Déployer MySQL 8.4 avec volume nommé, healthcheck, et une application PHP 8.3-FPM derrière Nginx.
- Vérifier la communication DNS interne (nom de service = hostname).
- Mettre à l’échelle le service `php` (`--scale php=2`) sans `container_name`.
- Distinguer `docker compose down` (volume conservé) et `docker compose down -v` (données perdues).

## Prérequis

- Labs 01 à 04 (CLI, images, réseau, volumes) recommandés.
- Docker Engine **ou** Docker Desktop, plugin Compose v2 (`docker compose version`).
- Terminal : macOS Terminal / Linux bash / **Ubuntu WSL ou Git Bash** (pas PowerShell).
- Port **8080** libre sur votre machine : le conteneur `web` du lab 01 l'utilise aussi — `docker rm -f web` s'il tourne encore (ou `bash scripts/cleanup-all.sh` depuis la racine du repo).

```bash
cd docker/lab07-compose
cp .env.example .env
```

Le fichier `.env` n’est **pas** commité (voir `.gitignore`). Les mots de passe sont des **exemples pédagogiques** (`ChangeMe-root` / `ChangeMe-app`), pas des secrets de production.

> **Sur Docker Desktop (macOS/Windows)**
> Clonez le dépôt **dans le système de fichiers Linux** (WSL : `~/…`, pas `/mnt/c/…`) pour que le bind mount `./php-app` soit fiable et rapide. Éditez `.env` dans WSL/VS Code : des fins de ligne CRLF (Notepad) cassent parfois les valeurs. Le fichier `.gitattributes` du dépôt force le LF au clone.

---

## Étape 1 — Relire le plan Compose

```bash
docker compose config
```

**Résultat attendu :** YAML « rendu » (variables `.env` interpolées), **sans** clé `version:`. Trois services : `mysql`, `php`, `nginx`. Aucun `container_name` (sinon `--scale` serait impossible).

---

## Étape 2 — Construire et démarrer

```bash
docker compose up -d --build
```

Le service `php` attend que MySQL soit **healthy** (`depends_on: condition: service_healthy`). Le premier `up` compile l’extension `pdo_mysql` dans l’image PHP : comptez 1 à 2 minutes.

**Résultat attendu :**

```bash
docker compose ps
```

`mysql` affiche `(healthy)`, `php` et `nginx` sont `Up`. Nginx publie `8080:80`.

---

## Étape 3 — Tester l’application

Navigateur : <http://localhost:8080> — ou :

```bash
curl -s localhost:8080
```

**Résultat attendu :** le HTML contient **Connexion MySQL réussie**, l’heure (PHP et MySQL) et le **hostname** du conteneur PHP.

Si MySQL est injoignable, la page répond **HTTP 500** avec un message d’erreur (essayez après `docker compose stop mysql` puis `curl -sI localhost:8080` — remettez MySQL avec `docker compose start mysql`).

---

## Étape 4 — Journaux de la pile

```bash
docker compose logs
docker compose logs mysql --tail 20
```

**Résultat attendu :** MySQL mentionne qu’il est prêt à accepter des connexions ; php-fpm et nginx démarrent sans boucle d’erreur.

`docker compose logs -f` suit le flux (Ctrl+C pour quitter) — à éviter dans un script.

---

## Étape 5 — Client MySQL dans le service

```bash
docker compose exec mysql mysql -uappuser -p"$MYSQL_PASSWORD" -e 'SHOW DATABASES;'
```

Si `$MYSQL_PASSWORD` est vide dans votre shell, chargez `.env` :

```bash
set -a
# shellcheck source=/dev/null
. ./.env
set +a
docker compose exec mysql mysql -uappuser -p"$MYSQL_PASSWORD" -e 'SHOW DATABASES;'
```

**Résultat attendu :** la liste contient `appdb`. Un avertissement *Using a password on the command line* est normal en lab.

---

## Étape 6 — Mettre à l’échelle PHP (`--scale php=2`)

Nginx proxyifie vers le **nom de service** `php` (résolution DNS Docker à chaque requête, voir `nginx/default.conf`). Sans `container_name`, Compose peut lancer deux réplicas.

```bash
docker compose up -d --scale php=2
docker compose ps
curl -s localhost:8080 | grep -i hostname
curl -s localhost:8080 | grep -i hostname
```

**Résultat attendu :** deux conteneurs `php`. Les `curl` peuvent afficher **deux hostnames différents** (round-robin DNS). Un `502` très bref est possible pendant le scale-down : le DNS Docker ne retire pas instantanément un réplica arrêté. Revenez à un réplica :

```bash
docker compose up -d --scale php=1
```

---

## Étape 7 — Persistance du volume

```bash
docker compose exec mysql mysql -uappuser -p"$MYSQL_PASSWORD" -D appdb -e \
  'CREATE TABLE lab_persist (id INT PRIMARY KEY); INSERT INTO lab_persist VALUES (1); SELECT * FROM lab_persist;'
```

Arrêt **sans** supprimer les volumes :

```bash
docker compose down
docker compose up -d
```

Attendez que MySQL redevienne `healthy`, puis :

```bash
docker compose exec mysql mysql -uappuser -p"$MYSQL_PASSWORD" -D appdb -e 'SELECT * FROM lab_persist;'
```

**Résultat attendu :** la table et la ligne `1` sont **toujours là**.

Suppression des volumes :

```bash
docker compose down -v
docker compose up -d
```

Après healthy :

```bash
docker compose exec mysql mysql -uappuser -p"$MYSQL_PASSWORD" -D appdb -e 'SHOW TABLES;'
```

**Résultat attendu :** `lab_persist` a **disparu** (volume `db-data` recréé vide).

---

## Compose avancé (court)

### `docker compose config`

Déjà utilisé à l’étape 1. Utile pour déboguer une interpolation `.env` (« pourquoi le mot de passe est vide ? »).

### Profiles

Le service `debug` (image `alpine:3.20`) a `profiles: ["debug"]` : **il ne démarre pas** avec un `up` normal.

```bash
docker compose --profile debug up -d
docker compose exec debug ping -c 1 mysql
docker compose --profile debug down
```

**Résultat attendu :** `ping` résout `mysql` sur le réseau Compose. Sans `--profile debug`, `docker compose ps` ne liste pas `debug`.

### `docker compose watch`

Compose peut resynchroniser des fichiers et/ou reconstruire une image quand vous éditez le code (`develop.watch` dans le fichier Compose, commande `docker compose watch`). Ici, le **bind mount** `./php-app:/var/www/html` recharge déjà `index.php` sans rebuild : ouvrez le fichier, changez le titre, `curl` à nouveau.

`watch` devient intéressant le jour où vous **copiez** le code dans l’image (plus de bind mount) et voulez un cycle « save → sync/rebuild » sans `up --build` manuel. Compose v2.22+ / Docker Desktop récent l’inclut (`docker compose watch --help`).

---

## Pour aller plus loin

- Santé applicative : ajouter un `healthcheck` sur `php` (ex. `cgi-fcgi -b 127.0.0.1:9000`) et `depends_on` nginx → php `service_healthy`.
- Ne plus binder le code : `COPY` dans le Dockerfile PHP, puis `docker compose watch` ou un rebuild CI.
- Secrets : `docker compose` `secrets:` plutôt qu’un `.env` en clair (hors périmètre de ce lab).
- `docker compose run --rm php php -v` pour un one-shot sans TTY de service.

## Nettoyage

```bash
docker compose --profile debug down -v --remove-orphans
```

(`--profile debug` retire aussi le sidecar Alpine s’il a été démarré à l’étape « profiles ».)

Les images (`mysql:8.4`, `php:8.3-fpm`, `nginx:1.27-alpine`, `alpine:3.20`) peuvent rester en cache.

Vérification automatique (non interactif) :

```bash
./check.sh
```
