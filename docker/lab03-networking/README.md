# Lab 03 — Reseaux Docker

**Durée estimée :** 25 minutes

## Objectifs

- Lister les reseaux par defaut et creer deux reseaux bridge utilisateur.
- Faire communiquer un client et Redis **par nom DNS** (`redis`) sur le meme reseau.
- Constater l'isolation : un client sur `isolated-net` ne resout pas `redis`.
- Relier un conteneur a un second reseau avec `docker network connect`.
- Observer `--network host` et `--network none`.

## Prérequis

- Lab 01 termine.
- Docker Desktop (macOS / Windows) ou Docker Engine (Linux).
- **Windows :** terminal Ubuntu (WSL) ou Git Bash, depot clone dans `~/`.

```bash
cd docker/lab03-networking
```

---

## Étape 1 — Reseaux par defaut

```bash
docker network ls
```

**Résultat attendu :** au moins `bridge`, `host` et `none`. Le `bridge` par defaut n'offre **pas** de DNS automatique entre conteneurs (il faut l'IP). Les reseaux **utilisateur** (etapes suivantes) oui.

---

## Étape 2 — Creer deux reseaux

```bash
docker network create app-net
docker network create isolated-net
docker network ls
docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' app-net
docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' isolated-net
```

**Résultat attendu :** deux subnets distincts (souvent `172.18.0.0/16` et `172.19.0.0/16`, les numeros varient).

Equivalent avec `grep` :

```bash
docker network inspect app-net | grep Subnet
```

---

## Étape 3 — Redis sur `app-net`

```bash
docker run -d --name redis --network app-net redis:7-alpine
```

**Résultat attendu :** `docker ps` montre `redis` en `Up`. Le nom `redis` devient un nom DNS **sur ce reseau uniquement**.

Attendre une seconde que Redis accepte les connexions.

---

## Étape 4 — Client Alpine sur le meme reseau

Forme interactive (vrai terminal) :

```bash
docker run --rm -it --network app-net alpine:3.20 sh
```

Dans le conteneur :

```bash
apk add --no-cache redis
redis-cli -h redis ping
exit
```

**Résultat attendu :** `PONG`.

Sans TTY (une ligne, utile en script) :

```bash
docker run --rm --network app-net redis:7-alpine redis-cli -h redis -t 5 ping
```

**Résultat attendu :** `PONG`.

---

## Étape 5 — Client sur `isolated-net` : DNS echoue

```bash
docker run --rm -it --network isolated-net alpine:3.20 sh
```

Dans le conteneur :

```bash
apk add --no-cache redis
redis-cli -h redis -t 3 ping
exit
```

**Résultat attendu :** erreur du type `Could not connect to Redis at redis:6379` (nom `redis` inconnu sur ce reseau). Tapez `exit` pour quitter.

Hors interactif :

```bash
docker run --rm --network isolated-net redis:7-alpine redis-cli -h redis -t 3 ping
```

La commande **echoue** (code != 0) : c'est le resultat voulu.

---

## Étape 6 — `docker network connect`

On rattache un client deja lance a `app-net` **sans le recreer** :

```bash
docker run -d --name client --network isolated-net redis:7-alpine sleep 300
docker exec client redis-cli -h redis -t 3 ping
```

**Résultat attendu :** echec (meme isolation qu'a l'etape 5).

```bash
docker network connect app-net client
docker exec client redis-cli -h redis -t 5 ping
```

**Résultat attendu :** `PONG`. Le resolveur embarque (127.0.0.11) est mis a jour a chaud : pas besoin de redemarrer le client.

```bash
docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' client
```

**Résultat attendu :** `app-net` et `isolated-net`.

---

## Étape 7 — `--network host` (rapide)

```bash
docker run --rm --network host alpine:3.20 ls /sys/class/net
```

**Résultat attendu (Linux / Docker Engine) :** les interfaces de **l'hote** (`lo`, `eth0`, `ens3`, `docker0`…). Le conteneur n'a pas de pile reseau isolee.

> **Sur Docker Desktop (macOS/Windows)**
> `--network host` s'attache a la **VM Linux** de Docker Desktop, pas a macOS ou Windows. Vous verrez les interfaces de cette VM. Un service qui ecoute sur le "host" n'apparait pas automatiquement comme `localhost` sur le Mac / PC (sauf option Desktop "Enable host networking", comportement different du Linux natif). Pour exposer un port vers le navigateur, preferez `-p` (Lab 01).
>
> `docker inspect --format '{{.HostConfig.NetworkMode}}'` vaut quand meme `host` : le moteur a bien applique le mode.

---

## Étape 8 — `--network none`

```bash
docker run --rm --network none alpine:3.20 ls /sys/class/net
```

**Résultat attendu :** uniquement `lo`. Pas d'Ethernet, pas de DNS, pas d'acces reseau. Utile pour un job 100 % local.

---

## Pour aller plus loin

- `docker network inspect app-net` : liste des conteneurs connectes (`Containers`).
- `docker network disconnect isolated-net client` puis retester `redis-cli` (le PONG continue via `app-net`).
- Overlay / macvlan : hors programme Jour 1 ; le bridge utilisateur suffit pour le compose du Lab 07.
- Ne pas publier Redis sur l'hote (`-p 6379:6379`) dans ce lab : le but est le DNS interne, pas l'acces depuis votre laptop.

## Nettoyage

```bash
docker rm -f redis client
docker network rm app-net isolated-net
```

Les images `redis:7-alpine` et `alpine:3.20` peuvent rester.

Verification automatique (non interactive, moins de 5 min) :

```bash
./check.sh
```
