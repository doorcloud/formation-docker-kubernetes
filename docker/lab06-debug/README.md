# Lab 06 — Debug et troubleshooting Docker

**Durée estimée :** 25 minutes

## Objectifs

- Distinguer un conteneur sain, un conteneur qui a quitté en erreur, et un conteneur tué par le OOM killer.
- Lire les logs (`docker logs`), l’état (`docker inspect`) et les processus (`docker top`).
- Observer CPU/RAM avec `docker stats` et le flux d’événements avec `docker events`.
- Entrer dans un conteneur en cours d’exécution (`docker exec`) pour diagnostiquer.
- Comprendre une politique de redémarrage (`--restart=on-failure:N`) et le champ `RestartCount`.
- Limiter la taille des journaux (`--log-opt`) et inspecter l’espace disque Docker (`docker system df`).

## Prérequis

- Lab 01 terminé (CLI Docker).
- Docker Engine ou Docker Desktop + `curl`.
- Terminal : macOS Terminal / Linux bash / **Ubuntu WSL ou Git Bash** (pas PowerShell).
- Être dans le dossier du lab :

```bash
cd docker/lab06-debug
```

> **Sur Docker Desktop (macOS/Windows)**
> `docker stats` et `--memory` s’appliquent **à la VM Linux** de Docker Desktop, pas à la RAM brute de macOS/Windows. La démo OOM fonctionne, mais le plafond est comptabilisé dans cette VM (réglage *Settings → Resources → Memory*). `--pid=host` n’est pas utilisé ici.

---

## Étape 1 — Conteneur sain (`test-web`)

On lance Nginx, avec une rotation des logs JSON (10 Mo × 3 fichiers) pour ne pas saturer le disque.

```bash
docker run -d --name test-web \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  nginx:1.27-alpine
```

**Résultat attendu :** `docker ps` affiche `test-web` en `Up`. Aucun port n’est publié : on diagnostique **depuis** le moteur Docker, pas via le navigateur.

```bash
docker ps --filter name=test-web
docker inspect --format '{{.State.Status}} {{.State.ExitCode}} {{.State.OOMKilled}}' test-web
```

Vous devez lire `running 0 false`.

---

## Étape 2 — Conteneur qui plante tout de suite (`crash-test`)

Sans `-d`, la commande rend la main dès que le processus s’arrête. Le code de sortie du `docker run` est celui du processus (ici `1`).

```bash
docker run --name crash-test busybox:1.36 sh -c "echo 'Crash imminent'; exit 1"
```

**Résultat attendu :** le terminal affiche `Crash imminent`, puis une erreur (code 1). Le conteneur **existe encore** :

```bash
docker ps -a --filter name=crash-test
```

La colonne `STATUS` contient `Exited (1)`. C’est le cas le plus fréquent en prod : le processus a crashé, le conteneur n’a pas disparu.

```bash
docker logs crash-test
docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' crash-test
```

**Résultat attendu :** les logs contiennent `Crash imminent`. `inspect` affiche `1 false` (échec applicatif, **pas** un OOM).

---

## Étape 3 — Fuite mémoire et OOMKilled (`mem-leak`)

On impose un plafond cgroup de **128 Mo** (RAM = swap, donc pas de « soupape » swap) et on alloue volontairement plus. Le processus Python agrandit un `bytearray` jusqu’à se faire tuer.

```bash
docker run -d --name mem-leak \
  --memory=128m \
  --memory-swap=128m \
  python:3.12-slim \
  python -c 'x=[]; exec("while True: x.append(bytearray(8*1024*1024))")'
```

Attendez 5 à 15 secondes, puis :

```bash
docker ps -a --filter name=mem-leak
docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' mem-leak
```

**Résultat attendu :**

| Champ | Valeur | Signification |
|---|---|---|
| `STATUS` | `Exited (137)` | 128 + 9 = SIGKILL |
| `OOMKilled` | `true` | le killer **cgroup** a frappé |
| `ExitCode` | `137` | cohérent avec SIGKILL |

Sans `--memory-swap=128m`, Docker autorise souvent **2 × RAM** de swap : le processus met plus longtemps à mourir, voire ne meurt pas pendant le lab.

> **Sur Docker Desktop (macOS/Windows)**
> La démo **fonctionne** : le cgroup vit dans la VM Linux interne. Vérifiez que Docker Desktop a **au moins 2 Go** de RAM (*Settings → Resources*). Si `OOMKilled` reste `false`, augmentez un peu l’attente (le killer n’est pas immédiat) puis relancez `docker inspect`.

---

## Étape 4 — Ressources : `stats` et `top`

`docker stats` sans option est un tableau **vivant** (Ctrl+C pour quitter). En script ou pour une capture :

```bash
docker stats --no-stream test-web
docker top test-web
```

**Résultat attendu :** `stats` montre CPU et MEM pour `test-web`. `top` liste au moins un processus `nginx`.

> **Sur Docker Desktop (macOS/Windows)**
> Les pourcentages MEM sont relatifs à la RAM **allouée à la VM Docker**, pas à celle affichée par le Moniteur d’activité / Gestionnaire des tâches de l’hôte.

---

## Étape 5 — Événements (forme non bloquante)

`docker events` sans `--until` reste ouvert. Pour un instantané (Docker 29+ n’accepte plus le mot `now`) :

```bash
docker events --since 5m --until 0s
```

**Résultat attendu :** des lignes `container create / start / die / oom` correspondant aux essais précédents.

---

## Étape 6 — Diagnostic live : `exec` et logs filtrés

Depuis un vrai terminal (TTY) :

```bash
docker exec -it test-web sh
```

Dans le shell du conteneur :

```bash
ls /usr/share/nginx/html
head /etc/nginx/nginx.conf
exit
```

Sans TTY (CI, script), on **ôte** `-it` :

```bash
docker exec test-web nginx -t
```

Logs récents seulement :

```bash
docker logs --tail 20 test-web
docker logs --since 5m crash-test
```

**Résultat attendu :** `nginx -t` affiche `syntax is ok`. Les logs de `crash-test` montrent encore `Crash imminent`.

---

## Étape 7 — Politique de redémarrage

`crash-test` s’est arrêté **une** fois. On recrée un jumeau qui a le droit à 3 relances :

```bash
docker run -d --name crash-restart --restart=on-failure:3 \
  busybox:1.36 sh -c "echo 'Crash imminent'; exit 1"
```

Attendez ~8 secondes (le délai entre relances double à chaque essai) :

```bash
docker inspect --format '{{.RestartCount}} {{.State.Status}} {{.State.ExitCode}}' crash-restart
docker ps -a --filter name=crash-restart
```

**Résultat attendu :** `RestartCount` vaut **3**, puis le moteur **arrête** de relancer (`on-failure:3` = maximum 3 redémarrages). Le statut final est `Exited (1)`.

Autres politiques (à connaître, pas à lancer ici) : `no` (défaut), `always`, `unless-stopped`.

---

## Étape 8 — Espace disque Docker

```bash
docker system df
```

**Résultat attendu :** un tableau *Images / Containers / Local Volumes / Build Cache* avec tailles. Utile quand le disque se remplit (layers, volumes oubliés).

---

## Aide-mémoire — symptôme → commande

| Symptôme | Commande |
|---|---|
| « Il ne tourne plus » | `docker ps -a` — regarder `STATUS` (`Exited (N)`, `Restarting`) |
| Code de sortie / OOM | `docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' NOM` |
| Pourquoi il est mort | `docker logs NOM` puis `docker logs --tail 50 --since 10m NOM` |
| Il redémarre en boucle | `docker inspect --format '{{.RestartCount}} {{.HostConfig.RestartPolicy.Name}}' NOM` |
| Trop de CPU / RAM | `docker stats --no-stream` |
| Quel processus dans le conteneur | `docker top NOM` |
| Timeline (create, die, oom) | `docker events --since 5m --until 0s` |
| Shell dans un conteneur **Up** | `docker exec -it NOM sh` |
| Disque Docker plein | `docker system df` puis `docker system prune` (attention : destructif) |

On n’utilise **pas** cAdvisor dans ce lab : les commandes Docker ci-dessus suffisent pour le diagnostic de base.

---

## Pour aller plus loin

- `docker inspect NOM` sans `--format` : JSON complet (réseau, mounts, `LogPath`).
- `jq` : `docker inspect test-web | jq '.[].State'`.
- Driver de logs `journald` (systemd, Linux natif) vs `json-file` (fichiers sous `/var/lib/docker/containers/…` — chemin **dans la VM** sous Docker Desktop).
- En production : plafonds `--memory` / `--cpus` **et** une sonde (healthcheck) plutôt que de découvrir l’OOM dans les tickets.

## Nettoyage

```bash
docker rm -f test-web crash-test mem-leak crash-restart
```

Les images (`nginx:1.27-alpine`, `busybox:1.36`, `python:3.12-slim`) peuvent rester en local pour les labs suivants.

Vérification automatique (non interactif) :

```bash
./check.sh
```
