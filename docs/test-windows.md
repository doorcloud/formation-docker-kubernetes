# Tests Windows — ce que CI prouve (et ce qu'elle ne prouve pas)

Le job GitHub Actions `windows-hygiene`
(`.github/workflows/windows-client.yml`, runner `windows-latest`) est le
chemin Windows **automatise** de la formation. Il ne lance **aucun** lab
Docker.

Les stagiaires Windows travaillent sur **leur propre laptop** : Docker
Desktop + backend WSL 2. Les commandes des labs se tapent dans un
terminal **Ubuntu (WSL)** ou **Git Bash**, jamais dans PowerShell.
Voir `docs/prerequis-installation.md`.

## Ce que le job prouve

1. **Hygiene du clone** — `actions/checkout` garde les reglages par
   defaut du runner Windows (`core.autocrlf` typiquement `true`). Le job
   exige `.gitattributes` a la racine, puis relit en **octets bruts** les
   fichiers suivis `*.sh`, `Dockerfile*`, `*.yml` / `*.yaml`, `*.conf`,
   `*.php`, `*.py`, `*.json`, `.env.example`, `*.md` sous `docker/` et
   `scripts/` (sauf `*.ps1`). Echec s'il trouve un CRLF (`\r\n`) ou un
   BOM UTF-8 (`EF BB BF`). C'est la preuve que `.gitattributes`
   (`eol=lf`) protege un clone Windows : sans cela, shebangs, scripts et
   Dockerfiles cassent dans WSL.
2. **Copier-coller des labs** — extraction des blocs fences `bash` /
   `sh` dans `docker/lab*/README.md` et `docs/*.md`. Echec si un bloc
   contient des guillemets typographiques (U+2018 U+2019 U+201C U+201D),
   un tiret cadratin / demi-cadratin (U+2014 U+2013) ou un espace
   inseparable (U+00A0). Ces caracteres, souvent colles depuis Word /
   PowerPoint, cassent le copier-coller dans le terminal.
3. **Doc terminaux** — si `docs/prerequis-installation.md` existe, il
   doit mentionner **WSL** et **Git Bash**, et ne pas recommander
   PowerShell comme terminal des labs (`Test-Prereqs.ps1` et
   `ExecutionPolicy` restent autorises).
4. **Syntaxe PowerShell** — parse de `scripts/windows/*.ps1` via
   `[System.Management.Automation.Language.Parser]::ParseFile` (echec si
   erreur de syntaxe). C'est le script que les stagiaires lancent une
   fois **avant** la formation.

Les etapes `wsl --status` et `docker --version` sont **informatives**
(`continue-on-error: true`) : le runner GHA n'est pas un laptop
stagiaire.

## Ce que le job ne prouve pas

- **Docker Desktop sur Windows** (moteur WSL 2, integration Ubuntu,
  baleine verte, `docker run hello-world` depuis WSL).
- Les **labs Linux** : AppArmor, `--pid=host` (VM Desktop, pas l'hote),
  bind mounts `~/...`, cgroups vues depuis Ubuntu. Le runner
  `windows-latest` expose Docker en mode **conteneurs Windows** : il ne
  peut pas executer les labs. Ceux-ci tournent dans `ci.yml` sur
  `ubuntu-latest`.
- Le comportement d'un poste **verrouille** (pas d'admin, WSL bloque,
  antivirus). Plan B : `docs/plan-b.md`.
- Git Bash vs WSL sur un vrai clavier stagiaire (`$(...)`,
  continuations `\`, alias `curl`, chemins `/mnt/c`).

D'ou la checklist manuelle ci-dessous, a faire **sur un vrai laptop
Windows** avant d'entrer en salle.

## Checklist formateur (laptop Windows reel)

A cocher la veille ou le matin, avec Docker Desktop + Ubuntu WSL, en
tant que stagiaire (pas en admin une fois l'install faite).

1. **Installer Docker Desktop** (backend WSL 2) + distro Ubuntu, puis
   lancer `scripts/windows/Test-Prereqs.ps1` depuis Windows PowerShell
   (`Set-ExecutionPolicy -Scope Process Bypass ; .\Test-Prereqs.ps1`).
   Table 100 % PASS. Documenter tout FAIL (politique machine, virt
   BIOS, WSL bloque) pour le plan B.
2. **Ouvrir un terminal Ubuntu (WSL)** — pas PowerShell, pas `cmd`.
   Prompt Linux (`user@pc:~$`). Verifier `uname -a` (kernel WSL2) et
   `docker version` **dans ce terminal** (integration WSL).
3. **Cloner dans `~/`**, pas sous `/mnt/c` ni `C:\Users\...` :

   ```bash
   cd ~
   git clone https://github.com/doorcloud/formation-docker-kubernetes.git
   cd ~/formation-docker-kubernetes
   git ls-files --eol | head
   ```

   Les fichiers `*.sh` / `Dockerfile` doivent rester `lf`. Si `crlf`
   apparait, `.gitattributes` n'a pas joue : arreter et corriger avant
   la classe.

4. **Lancer `scripts/check-all.sh` depuis WSL** (pas depuis Git Bash
   sur `C:\`, pas depuis PowerShell) :

   ```bash
   cd ~/formation-docker-kubernetes
   bash scripts/check-all.sh
   ```

   Les 7 labs doivent passer comme sur `ubuntu-latest`. Noter le temps
   (pulls Docker Hub : `docker login` conseille).

5. **Bind mount lab 04 depuis un chemin WSL** — dans
   `~/formation-docker-kubernetes/docker/lab04-volumes` (ou equivalent),
   executer l'etape volume / bind mount avec `$PWD` sous `/home/...`.
   Confirmer que le fichier apparait dans le conteneur. **Ne pas**
   tester uniquement via `/mnt/c/Users/...` : c'est le piege classique
   (lenteur, UID, chemins Windows).

6. **Lab 05 AppArmor saute proprement** — Docker Desktop n'a pas
   AppArmor. L'etape `docker-default` / `apparmor` doit s'afficher comme
   **informative** (macOS / Windows) et `check.sh` du lab 05 ne doit
   **pas** echouer. Seccomp, capabilities et namespaces restent a
   demonstrer.

Si un point echoue sur le laptop formateur, il echouera en salle.
Corriger la doc / le lab **avant** 08h00, ou prevoir le plan B
(`labs.play-with-docker.com` / binome / VM de secours).
