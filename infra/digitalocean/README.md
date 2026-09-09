# DigitalOcean — VMs de test et de secours uniquement

Les stagiaires travaillent sur **leur laptop** (macOS, Windows + WSL2, ou Linux). Les droplets de ce dossier ne sont **pas** des postes stagiaires. Elles servent :

- aux **tests** de la formation (agents, CI manuelle, AppArmor réel) ;
- de **plan B** si un laptop est verrouillé (voir [docs/plan-b.md](../../docs/plan-b.md)).

Aucun secret dans git : pas de clé privée, pas de jeton `doctl`, pas d’IP réelle. Le fichier [cloud-init.yaml](cloud-init.yaml) contient le placeholder `__SSH_PUBKEY__`.

Les scripts `create-vms.sh` et `destroy-vms.sh` sont des aides formateur. La création unitaire ci-dessous suffit.

## Créer une VM de test ou de secours

Prérequis : [`doctl`](https://docs.digitalocean.com/reference/doctl/) authentifié (`doctl account get`), une clé publique SSH locale.

Substituer le placeholder, **sans** committer le fichier rendu :

```bash
pubkey="$(cat ~/.ssh/id_ed25519.pub)"
sed "s|__SSH_PUBKEY__|${pubkey}|" infra/digitalocean/cloud-init.yaml > /tmp/cloud-init-formation.yaml
grep -q '__SSH_PUBKEY__' /tmp/cloud-init-formation.yaml && echo "ERREUR: placeholder non substitué" && exit 1
```

Créer la droplet (région / taille ajustables) :

```bash
doctl compute droplet create lab-test-01 \
  --region ams3 \
  --size s-2vcpu-4gb \
  --image ubuntu-24-04-x64 \
  --user-data-file /tmp/cloud-init-formation.yaml \
  --tag-names formation-docker \
  --wait
```

Attendre la fin de cloud-init (Docker + clone du dépôt) :

```bash
ssh -i ~/.ssh/id_ed25519 formation@IP -- cloud-init status --wait
```

Compte Unix : `formation` (groupe `docker`, sudo). Auth SSH par clé uniquement.

Pour plusieurs VMs, le script `./create-vms.sh <prefix> <count> [--keys-dir DIR]` injecte `__SSH_PUBKEY__` de la même façon (clés **hors** git).

## Détruire par tag

Ne supprime **que** les droplets taguées `formation-docker` (pas les autres ressources du compte) :

```bash
doctl compute droplet list --tag-name formation-docker
doctl compute droplet delete --tag-name formation-docker --force
```

Équivalent avec confirmation : `./destroy-vms.sh` (taper `oui`) ou `./destroy-vms.sh --yes`.

Détruire les VMs de **test** dès que la validation est finie, pour arrêter la facturation. Les VMs de **secours** éventuelles se détruisent à la fin de la formation.

## Connexion

```bash
ssh -i cle formation@IP
```

Sous Windows (PowerShell), si OpenSSH refuse la clé : voir les quatre lignes `icacls` dans [docs/plan-b.md](../../docs/plan-b.md).
