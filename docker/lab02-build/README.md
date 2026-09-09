# Lab 02 — Build et publication d'images

**Durée estimée :** 35 minutes

## Objectifs

- Construire deux images Flask : une **volontairement mauvaise**, une **optimisee**.
- Mesurer l'impact des bonnes pratiques (base slim, ordre des couches, `.dockerignore`, utilisateur non-root).
- Comparer les tailles et lire `docker history`.
- Publier l'image optimisee vers un **registre local** (`registry:2`), puis la re-telecharger.
- Comprendre (en theorie) un `docker push` vers Docker Hub.

## Prérequis

- Lab 01 termine.
- Docker Desktop (macOS / Windows) ou Docker Engine (Linux).
- `curl`.
- **Windows :** terminal Ubuntu (WSL) ou Git Bash, depot clone dans `~/` (pas `/mnt/c`).

```bash
cd docker/lab02-build
```

> **Sur Docker Desktop (macOS/Windows)**
> Sous **macOS**, AirPlay Receiver ecoute souvent le **port 5000**. C'est pour cela que le registre local de ce lab utilise **5005** (et non 5000), et que Flask est publie sur **5001** (mauvaise image) et **5002** (bonne image). Si un `-p` echoue (`port is already allocated`), changez uniquement le port hote.

---

## Étape 1 — Lire les deux Dockerfiles

Ouvrez `bad/Dockerfile` puis `Dockerfile` (a la racine de ce lab).

| | Mauvaise (`bad/`) | Bonne (racine) |
|---|---|---|
| Base | `python:3.12` (~1 Go) | `python:3.12-slim` |
| Copie | `COPY .` **avant** les deps | `requirements.txt` d'abord, puis `app.py` |
| pip | sans `--no-cache-dir` | `--no-cache-dir` |
| Utilisateur | root | `USER appuser` (uid 1000) |
| `.dockerignore` | **aucun** (contexte = `bad/`) | present (exclut `README`, `check.sh`, `bad/`, bonus…) |
| Sante | aucun | `HEALTHCHECK` + `EXPOSE 5000` |
| Processus | `CMD` exec (`["python", "app.py"]`) | idem, forme exec (pas de shell wrapping) |

Le fichier `bad/secrets.env` (`MOT_DE_PASSE=ChangeMe-lab`, valeur d'exemple) est copie dans l'image mauvaise : c'est exactement ce qu'un `.dockerignore` evite.

> **Apple Silicon (M1 / M2 / M3)**
> Les images `python:3.12`, `python:3.12-slim`, `nginx:1.27-alpine` et `registry:2` sont **multi-arch**. Docker Desktop tire `linux/arm64` tout seul. Pour forcer l'architecture de production (`linux/amd64`, emulation plus lente) : `docker build --platform linux/amd64 …`. Inutile pour ce lab.

---

## Étape 2 — Construire la mauvaise image

Le contexte de build est le dossier `bad/` (pas de `.dockerignore`) :

```bash
docker build -t flask-bad:1.0.0 bad/
```

**Résultat attendu :** un build plus long (grosse base + `apt-get` vim/curl). Notez l'heure de fin.

---

## Étape 3 — Lancer la mauvaise image (port hote 5001)

```bash
docker run -d --name flask-bad -p 5001:5000 flask-bad:1.0.0
curl http://127.0.0.1:5001
```

**Résultat attendu :** `Hello from Docker!`

Navigateur : [http://localhost:5001](http://localhost:5001).

Le processus tourne en **root** :

```bash
docker exec flask-bad id
```

**Résultat attendu :** `uid=0(root)`.

---

## Étape 4 — Construire la bonne image

```bash
docker build -t flask-good:1.0.0 .
```

**Résultat attendu :** build plus rapide au deuxieme essai si vous ne touchez qu'a `app.py` : la couche `pip install` est en cache. C'est tout l'interet de copier `requirements.txt` **avant** le code.

---

## Étape 5 — Lancer la bonne image (port hote 5002)

```bash
docker run -d --name flask-good -p 5002:5000 flask-good:1.0.0
curl http://127.0.0.1:5002
curl http://127.0.0.1:5002/health
docker exec flask-good id
```

**Résultat attendu :** `Hello from Docker!`, `ok`, et `uid=1000(appuser)`.

L'etat de sante (attendre ~10 s, intervalle du HEALTHCHECK = 5 s) :

```bash
docker inspect --format '{{.State.Health.Status}}' flask-good
```

**Résultat attendu :** `healthy` (parfois `starting` pendant quelques secondes, relancez la commande).

---

## Étape 6 — Comparer les tailles

```bash
docker images flask-bad:1.0.0
docker images flask-good:1.0.0
```

**Résultat attendu :** `flask-good` est **nettement plus petite** (base slim, pas de vim/curl, pas de cache pip). Les chiffres exacts varient, l'ecart se compte en centaines de Mo.

---

## Étape 7 — `docker history` : qui pese ?

```bash
docker history flask-bad:1.0.0
docker history flask-good:1.0.0
```

**Résultat attendu :** chaque instruction du Dockerfile = une couche. Sur la mauvaise image, `FROM python:3.12` et `apt-get` dominent. Sur la bonne, vous voyez `USER`, `EXPOSE`, `HEALTHCHECK`.

---

## Étape 8 — Registre local sur le port 5005

```bash
docker run -d --name registry -p 5005:5000 registry:2
curl http://127.0.0.1:5005/v2/
```

**Résultat attendu :** `{}` (API v2 vivante). Docker considere `localhost` comme registre **non-TLS autorise** : aucun `insecure-registries` a ajouter pour cette adresse.

> **Sur Docker Desktop (macOS/Windows)**
> N'utilisez **pas** le port hote 5000 : sous macOS, AirPlay le prend souvent. Ici : `-p 5005:5000` (5000 a droite = port **dans** le conteneur `registry:2`, ne pas le changer).
> `localhost:5005` depuis **votre** terminal fonctionne. Depuis **un autre conteneur**, `localhost` designe ce conteneur-la, pas le registre.

---

## Étape 9 — Tag, push, catalogue

```bash
docker tag flask-good:1.0.0 localhost:5005/flask-good:1.0.0
docker push localhost:5005/flask-good:1.0.0
curl http://127.0.0.1:5005/v2/_catalog
```

**Résultat attendu :** `{"repositories":["flask-good"]}`. Anatomie du nom : `registre/namespace/image:tag` — ici le "namespace" est absent, le registre est `localhost:5005`.

---

## Étape 10 — Supprimer en local puis re-tirer

Arretez le conteneur qui utilise encore l'image, puis :

```bash
docker rm -f flask-good
docker rmi flask-good:1.0.0 localhost:5005/flask-good:1.0.0
docker pull localhost:5005/flask-good:1.0.0
docker images localhost:5005/flask-good
```

**Résultat attendu :** le `rmi` retire les **tags** locaux ; le `pull` ramene l'image depuis le registre. Preuve que la publication a fonctionne.

---

## Étape 11 — Docker Hub (theorie, ne pas executer)

Pour publier sur le Hub (compte gratuit : 200 pulls / 6 h par compte une fois `docker login` fait — utile en salle derriere une seule IP NAT) :

1. `docker login` (identifiants Docker Hub).
2. `docker tag flask-good:1.0.0 <votre-compte>/flask-good:1.0.0`
3. `docker push <votre-compte>/flask-good:1.0.0`

Sans compte, le rate-limit anonyme (100 pulls / 6 h, partage par toute la salle derriere la meme IP) est vite atteint avec 8-10 stagiaires. Ne poussez **pas** d'image de lab vers un depot public pendant la formation.

---

## Pour aller plus loin — bonus multi-stage (hors `check.sh`)

Un build **multi-stage** compile avec Node 22 puis ne garde que Nginx :

```bash
docker build -t hello-web:1.0.0 bonus-multistage/
docker run --rm -p 5003:80 hello-web:1.0.0
```

Dans un autre terminal : `curl http://127.0.0.1:5003` puis Ctrl+C sur le `run` (ou `docker rm -f` si vous avez ajoute `--name`).

En production, l'etape `build` ferait `npm ci && npm run build` ; le runtime ne contient **pas** `node_modules` ni le compilateur.

## Nettoyage

```bash
docker rm -f flask-bad flask-good registry
docker rmi flask-bad:1.0.0 flask-good:1.0.0 localhost:5005/flask-good:1.0.0 hello-web:1.0.0
```

Les images de base (`python:3.12`, `python:3.12-slim`, `registry:2`) peuvent rester.

Verification automatique (non interactive, moins de 5 min si les images de base sont deja tirees) :

```bash
./check.sh
```
