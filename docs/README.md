# Documentation

Index des guides de la formation **Docker & Kubernetes sur Door (DKS)**, signée Cloudoor.

## Pour les stagiaires

| Document | Quand le lire |
|----------|----------------|
| [prerequis-installation.md](prerequis-installation.md) | **Avant le Jour 1** (mail « À faire avant mercredi 9h ») : installer Docker sur **votre laptop**, tester `hello-world` |
| [differences-docker-desktop.md](differences-docker-desktop.md) | Pendant les labs, si vous êtes sous macOS ou Windows (Docker Desktop) |
| [plan-b.md](plan-b.md) | Si vous n’avez pas les droits admin, ou si Docker ne s’installe pas |
| [prerequis-kubernetes.md](prerequis-kubernetes.md) | **Avant le Jour 2** : kubectl, Helm 4, kubeconfig, compte Door |
| [dks-creer-cluster.md](dks-creer-cluster.md) | Lab 1 : créer le cluster DKS dans la console Door |
| [dks-kubeconfig.md](dks-kubeconfig.md) | Télécharger le kubeconfig, exposition publique, contextes |
| [plan-b-kubernetes.md](plan-b-kubernetes.md) | Pas de cluster DKS personnel : cluster partagé, kind, Killercoda |

Les commandes des labs se tapent dans un terminal Unix (Terminal macOS, **Ubuntu WSL** ou Git Bash, shell Linux). Voir le [README racine](../README.md) pour Docker (7 labs) et [kubernetes/README.md](../kubernetes/README.md) pour Kubernetes (10 labs) et la convention `check.sh`.

## Pour le formateur

| Document | Contenu |
|----------|----------|
| [test-windows.md](test-windows.md) | Checklist manuelle Docker Desktop Windows (hygiène CRLF, terminal WSL) |
| [test-kubernetes.md](test-kubernetes.md) | Comment les labs K8s sont testés : kind 1.37, kind+Cilium, DKS, CI |
| [../infra/digitalocean/README.md](../infra/digitalocean/README.md) | VMs DigitalOcean de **test** et de **secours** uniquement — pas le poste des stagiaires |
