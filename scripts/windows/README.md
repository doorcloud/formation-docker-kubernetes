# Scripts Windows (stagiaires)

Les labs Docker se tapent dans **Ubuntu (WSL)** ou **Git Bash**, jamais
dans PowerShell ni `cmd`. Ce dossier contient uniquement le controle a
lancer **une fois** avant la formation, depuis Windows PowerShell.

## Test-Prereqs.ps1

Verifie, **sans droits administrateur** :

- Windows 10 22H2 ou plus recent (Windows 11 22H2+)
- virtualisation activee (firmware / hyperviseur)
- WSL installe, version 2 par defaut, distro Ubuntu en WSL 2
- Docker Desktop (`docker --version`, `docker info`, `docker compose version`)
- integration WSL (la commande `docker` marche *dans* Ubuntu)
- Git for Windows + Git Bash

Chaque ligne FAIL affiche le correctif exact et un lien vers
`docs/prerequis-installation.md` (ancres `#windows`, `#virtualisation`,
`#wsl`, `#docker-desktop`, `#integration-wsl`, `#git-bash`).

## Lancer le script

Dans **Windows PowerShell** (pas WSL) :

```powershell
cd chemin\vers\formation-docker-kubernetes\scripts\windows
Set-ExecutionPolicy -Scope Process Bypass
.\Test-Prereqs.ps1
```

`-Scope Process` n'est pas permanent et **n'exige pas** un compte admin.
Il n'autorise le script que pour cette fenetre PowerShell.

Si la politique du poste bloque encore l'execution :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Prereqs.ps1
```

## Apres un PASS

1. Fermez PowerShell.
2. Ouvrez **Ubuntu** (terminal WSL) — a defaut Git Bash.
3. Clonez le depot dans le home WSL (`~/`), **pas** sous `/mnt/c` ni
   `C:\Users\...`.
4. Suivez `docs/prerequis-installation.md` (test `docker run hello-world`).

Le job GitHub Actions `windows-hygiene`
(`.github/workflows/windows-client.yml`) parse ce `.ps1` a chaque push ;
il ne remplace pas ce controle sur votre laptop.
