# Docker Desktop (macOS / Windows) vs Linux natif

Les labs sont écrits pour un **moteur Docker Linux**. Sur **Linux** (Ubuntu, Debian, Fedora), le démon tourne sur la machine. Sur **macOS** et **Windows**, Docker Desktop fait tourner ce démon dans une **petite VM Linux**. Les commandes `docker …` restent les mêmes ; quelques options et mesures ne veulent pas dire la même chose.

Ce n’est pas un obstacle : Seccomp, capabilities, namespaces et cgroups fonctionnent partout. Les écarts ci-dessous sont ceux que vous verrez en salle.

## Tableau des différences

| Sujet | Linux natif | Docker Desktop (macOS / Windows + WSL2) |
|-------|-------------|------------------------------------------|
| AppArmor | Disponible (`aa-status`, profil `docker-default`) | **Absent** (le noyau de la VM Desktop n’expose pas AppArmor comme un Ubuntu de lab) |
| `--pid=host` | PID de **votre** machine | PID de la **VM Linux** de Desktop, pas du Mac / de Windows |
| `--network host` | La pile réseau de l’hôte | **Limité** : le « host » est la VM, pas l’interface Wi-Fi du laptop |
| RAM / CPU vus par `docker stats` | Ressources de la machine | **Plafond = allocation Desktop** (Settings → Resources, viser 4 Go) |
| Bind mounts (`-v /chemin:/…`) | Performants | Plus lents ; chemins **partagés** avec la VM. Sous Windows : cloner dans `~/` WSL, **pas** `/mnt/c` |
| Ports déjà pris | Conflit avec un service Linux local | macOS : le port **5000** est souvent pris par **AirPlay Receiver** |
| `localhost` depuis un conteneur | L’hôte Linux | L’hôte du laptop se joint via **`host.docker.internal`** (pas `localhost` du conteneur) |
| Apple Silicon | N/A | Images `amd64` : ajouter `--platform linux/amd64` si l’image n’a pas de variant `arm64` |

## Impact par lab

| Lab | Impact Desktop |
|-----|----------------|
| **lab01-cli** | Aucun écart bloquant. `curl localhost:8080` se fait **sur le laptop** (Terminal macOS ou Ubuntu WSL), pas depuis l’intérieur du conteneur. |
| **lab02-build** | Si une étape publie ou écoute sur le port **5000** sous macOS : désactiver *Réglages → Général → Récepteur AirPlay*, ou utiliser un autre port hôte (ex. `5001`). Apple Silicon : un `FROM` uniquement `amd64` peut nécessiter `--platform linux/amd64`. |
| **lab03-networking** | Les réseaux bridge utilisateur (`app-net`, `isolated-net`) et le DNS interne fonctionnent. `--network host` n’est **pas** l’équivalent d’un Ubuntu nu. |
| **lab04-volumes** | Les **volumes nommés** (`db-data`) se comportent comme sous Linux. Un **bind mount** doit pointer vers un chemin **Linux** : sous Windows, `/home/<user>/…` dans WSL, jamais `C:\Users\…` ni `/mnt/c/Users/…` (lenteur, verrous, fins de ligne). |
| **lab05-security** | L’étape **AppArmor** est **informative** : le profil `docker-default` et `aa-status` peuvent être absents ou inopérants. Ne pas considérer ça comme un échec du lab. Capabilities, Seccomp (`no-mkdir.json`) et `--cap-drop ALL` restent valides. `--pid=host` montre les processus de la VM Desktop. |
| **lab06-debug** | `docker stats` reflète la RAM **allouée à Desktop**, pas les 16 Go du Mac. Un OOMKilled peut arriver plus tôt si l’allocation est trop basse (monter à 4 Go). |
| **lab07-compose** | `localhost:8080` dans le navigateur du laptop fonctionne (publication de port). Bind mounts des fichiers PHP/Nginx : même règle WSL que le lab 04. |

## Rappels Windows

- Terminal des labs : **Ubuntu (WSL)** ou Git Bash.
- Dépôt cloné dans `$HOME` Linux (`~/formation-docker-kubernetes`).
- `git config --global core.autocrlf input` (déjà dans [prerequis-installation.md](prerequis-installation.md)).

## Rappels macOS

- Installateur **Apple Silicon** ou **Intel**, pas l’inverse.
- Port 5000 : AirPlay. Préférer un autre port hôte dans les énoncés si le bind échoue avec `address already in use`.
