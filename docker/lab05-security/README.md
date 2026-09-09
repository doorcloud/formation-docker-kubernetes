# Lab 05 — Sécurité des conteneurs

**Durée estimée :** 40 minutes

## Objectifs

- Voir l'isolation **PID** : un conteneur n'a que ses processus ; `--pid=host` partage ceux de l'hôte (ou de la VM Desktop).
- Mesurer l'effet des **capabilities** Linux : `chown` avec / sans `CAP_CHOWN` ; `date -s` sans `SYS_TIME`.
- Appliquer un profil **seccomp** qui refuse `mkdir` tout en laissant `touch` fonctionner.
- Lire le profil **AppArmor** `docker-default` (étape informative sous Docker Desktop).
- Lancer un conteneur **non-root** et un système de fichiers **en lecture seule**.
- Lire les plafonds `--memory` / `--cpus` via `docker inspect --format`.

## Prérequis

- Docker fonctionne. Terminal : macOS, **Windows = WSL Ubuntu ou Git Bash**, Linux bash.
- Image : `alpine:3.20` (tag figé).
- Fichier `no-mkdir.json` dans ce dossier (profil seccomp).
- `docker login` recommandé.

Depuis la racine du dépôt cloné :

```bash
cd docker/lab05-security
```

---

## Étape 1 — Namespace PID : `ns-a` vs `--pid=host`

Par défaut, un conteneur a son propre arbre de processus : le processus principal est **PID 1**.

```bash
docker run -d --name ns-a alpine:3.20 sleep 3600
docker exec ns-a ps
```

**Résultat attendu :** deux ou trois lignes seulement (`sleep` en PID 1, et `ps`). Vous ne voyez **pas** les processus de votre laptop (`dockerd`, navigateur, etc.).

Même image, mais le namespace PID de l'hôte :

```bash
docker run -d --name ns-host --pid=host alpine:3.20 sleep 3600
docker exec ns-host ps
```

**Résultat attendu :** beaucoup plus de lignes (dizaines ou centaines) : `containerd`, `dockerd`, éventuellement `systemd`… Le `kill` d'un PID vu ici viserait un processus **hors** du conteneur. Ne tuez rien.

```bash
docker rm -f ns-a ns-host
```

> **Sur Docker Desktop (macOS/Windows)**  
> `--pid=host` montre les processus de la **VM Linux de Docker Desktop**, pas ceux de macOS ou de Windows. Vous ne verrez pas Safari ni `explorer.exe`. L'isolation vis-à-vis de l'OS hôte reste réelle ; l'isolation vis-à-vis du moteur Docker, elle, est relâchée.

---

## Étape 2 — Capabilities : `CHOWN` et `SYS_TIME`

Le « root » d'un conteneur n'a pas tous les pouvoirs du root hôte : Docker retire la plupart des capabilities. `CAP_CHOWN` fait partie du jeu **par défaut** ; `CAP_SYS_TIME` **non**.

`chown` réussit par défaut :

```bash
docker run --rm alpine:3.20 sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f && echo chown-ok'
```

**Résultat attendu :** `chown-ok`.

On retire **toutes** les capabilities : `chown` échoue.

```bash
docker run --rm --cap-drop ALL alpine:3.20 sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f && echo chown-ok'
```

**Résultat attendu :** `Operation not permitted` (code de sortie non nul). `touch` dans `/tmp` peut encore marcher (`/tmp` est world-writable).

On restitue uniquement `CHOWN` :

```bash
docker run --rm --cap-drop ALL --cap-add CHOWN alpine:3.20 sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f && echo chown-ok'
```

**Résultat attendu :** `chown-ok` à nouveau.

`date -s` demande `SYS_TIME`, **absente** du profil par défaut. On constate **uniquement** l'échec (on n'ajoute pas `SYS_TIME` : changer l'horloge de la VM n'est pas un objectif du lab) :

```bash
docker run --rm alpine:3.20 date -s '2020-01-01 00:00:00'
```

**Résultat attendu :** `date: can't set date: Operation not permitted`. BusyBox peut quand même **afficher** l'heure demandée et sortir avec le code 0 : c'est le message d'erreur qui compte. Vérifiez que `date` (sans `-s`) montre toujours l'année courante, pas 2020.

> **Sur Docker Desktop (macOS/Windows)**  
> Capabilities et seccomp s'appliquent **dans la VM Linux**. Le comportement de cette étape est le même que sur un Ubuntu natif.

---

## Étape 3 — Seccomp : interdire `mkdir`, autoriser `touch`

Le fichier `no-mkdir.json` est un profil **permissif** (`SCMP_ACT_ALLOW` par défaut) qui refuse les syscalls `mkdir` et `mkdirat` (`SCMP_ACT_ERRNO`). Le champ `architectures` couvre amd64 et ARM (Apple Silicon, Raspberry, etc.).

```bash
docker run --rm \
  --security-opt "seccomp=$(pwd)/no-mkdir.json" \
  alpine:3.20 touch /tmp/ok-touch
echo "touch: $?"
```

```bash
docker run --rm \
  --security-opt "seccomp=$(pwd)/no-mkdir.json" \
  alpine:3.20 mkdir /tmp/interdit || echo "mkdir refuse (attendu)"
```

**Résultat attendu :** `touch` code 0 ; `mkdir` échoue (errno, souvent `Operation not permitted`).

Sans `--security-opt seccomp=...`, `mkdir /tmp/interdit` réussit (contrôle).

> **Sur Docker Desktop (macOS/Windows)**  
> Seccomp fonctionne. Utilisez `$(pwd)/no-mkdir.json` (chemin hôte vu par le moteur). Dans WSL, lancez la commande **depuis** le dossier du lab.

---

## Étape 4 — AppArmor (`docker-default`)

Sur un **Linux hôte** avec AppArmor actif (Ubuntu/Debian typiques), chaque conteneur est confiné par le profil `docker-default` :

```bash
docker run --rm alpine:3.20 cat /proc/1/attr/current
```

**Résultat attendu (Linux + AppArmor) :** une ligne du type `docker-default (enforce)`.

```bash
# optionnel, sur Linux seulement
sudo aa-status | head
```

> **Docker Desktop : AppArmor indisponible, étape informative**  
> AppArmor est un LSM du noyau Linux de **l'hôte**. Docker Desktop (macOS/Windows) n'expose pas `aa-status` ni le profil `docker-default` comme sur Ubuntu. Dans le conteneur, `/proc/1/attr/current` affiche souvent `unconfined`. Ce n'est pas un échec du lab : passez à l'étape 5. Seccomp et les capabilities restent vos leviers portables.

---

## Étape 5 — Utilisateur non-root et rootfs en lecture seule

Par défaut le processus est `root` **dans** le conteneur (uid 0). On force uid/gid 1000 :

```bash
docker run --rm --user 1000:1000 alpine:3.20 id
```

**Résultat attendu :** `uid=1000 gid=1000`. Ce uid n'a en général **pas** de compte dans `/etc/passwd` de l'image : c'est normal.

```bash
docker run --rm --user 1000:1000 alpine:3.20 touch /root/x || echo "pas le droit d'écrire dans /root (attendu)"
```

Rootfs en lecture seule : on autorise uniquement `/tmp` via tmpfs (sinon même `touch /tmp/x` échoue) :

```bash
docker run --rm --read-only --tmpfs /tmp alpine:3.20 sh -c 'touch /tmp/ok && echo tmp-ok'
docker run --rm --read-only --tmpfs /tmp alpine:3.20 sh -c 'touch /etc/interdit' || echo "/etc en lecture seule (attendu)"
```

**Résultat attendu :** `/tmp/ok` réussit ; `/etc/interdit` échoue.

---

## Étape 6 — Plafonds mémoire et CPU

```bash
docker run -d --name c-limits \
  --memory=256m \
  --cpus=0.5 \
  alpine:3.20 sleep 60
```

```bash
docker inspect --format 'Memory={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}}' c-limits
docker rm -f c-limits
```

**Résultat attendu :**

| Option | Valeur inspect |
|---|---|
| `--memory=256m` | `Memory=268435456` (256 * 1024 * 1024) |
| `--cpus=0.5` | `NanoCpus=500000000` (0.5 CPU) |

Sans ces options, `Memory=0` signifie « pas de plafond Docker » (le noyau / la VM Desktop restent la limite réelle).

> **Sur Docker Desktop (macOS/Windows)**  
> Ces plafonds s'appliquent **à l'intérieur** de la RAM/CPU allouées à la VM Desktop (Settings → Resources). `docker stats` reflète aussi cette VM, pas la mémoire totale du Mac/PC.

---

## Pour aller plus loin (lecture, ne pas lancer `--privileged`)

- **`--privileged`** : redonne (presque) toutes les capabilities, relâche seccomp/AppArmor, donne accès aux devices. C'est le mode « comme root sur l'hôte ». **Ne l'utilisez pas** en formation ni en prod « pour que ça marche ». Préférez `--cap-add` ciblé.
- **Rootless Docker** : le démon lui-même tourne sans root (user namespaces). Moins de privilèges si le moteur est compromis ; quelques limites (ports < 1024, overlay). Documenté dans la doc Docker Engine.
- **Docker Bench for Security** : script qui audite la config du démon (`docker.sock`, profils, logging). À lancer sur une machine de lab, pas en aveugle en production.
- **Images** : `docker scout quickview alpine:3.20` (plugin Scout, compte Docker Hub) ou **Trivy** (`trivy image alpine:3.20`) pour les CVE. Un tag figé n'élimine pas les CVE ; il rend les builds reproductibles.
- User namespace remapping (`userns-remap`) : l'uid 0 du conteneur est un uid non-root sur l'hôte. Plus lourd à activer sur Desktop ; courant sur des démons Linux durcis.

## Nettoyage

```bash
docker rm -f ns-a ns-host c-limits 2>/dev/null
```

L'image `alpine:3.20` peut rester en local.

Vérification automatique (saute AppArmor si `aa-status` est absent ou inactif) :

```bash
./check.sh
```
