# Images des labs Kubernetes : pourquoi `ghcr.io/doorcloud/formation/*`

Les manifestes des labs Kubernetes référencent des images miroir :

| Image d'origine (Docker Hub) | Image utilisée dans les labs |
|---|---|
| `nginx:1.27-alpine`, `nginx:1.28-alpine` | `ghcr.io/doorcloud/formation/nginx:1.27-alpine`, `:1.28-alpine` |
| `busybox:1.36` | `ghcr.io/doorcloud/formation/busybox:1.36` |
| `redis:7-alpine` | `ghcr.io/doorcloud/formation/redis:7-alpine` |
| `nginxinc/nginx-unprivileged:1.27-alpine` | `ghcr.io/doorcloud/formation/nginx-unprivileged:1.27-alpine` |
| `curlimages/curl:8.10.1` | `ghcr.io/doorcloud/formation/curl:8.10.1` |

Ce sont **exactement les mêmes images** (copie du manifeste multi-architecture, même digest de
couches), publiées par le workflow [`mirror-images.yml`](../.github/workflows/mirror-images.yml)
à partir de [`kubernetes/images.txt`](../kubernetes/images.txt).

## Pourquoi

Mesuré le 09/09/2026 depuis deux clusters DKS (Abidjan), avec `ctr images pull` sur le nœud :

| Registre | Débit observé |
|---|---|
| Docker Hub (`docker.io`) | 16 KiB/s à 1 MiB/s selon la minute — `redis:7-alpine` > 5 min |
| `ghcr.io` | 3 à 5 MiB/s |
| `quay.io`, `registry.k8s.io` | 3 MiB/s et plus |

Avec 10 stagiaires qui déploient en même temps, Docker Hub rendrait les labs impraticables
(`ContainerCreating` pendant des minutes, `ImagePullBackOff`). Le kubelet sérialise en plus
les pulls par nœud (`serializeImagePulls: true`) : une image lente bloque toutes les autres.

## Ce que ça change pour vous

- Rien dans les concepts : `image:` pointe simplement vers un autre registre. Le format
  `registre/espace/nom:tag` est justement vu au lab 03.
- Les commandes `kubectl run --image=...` des README utilisent aussi le miroir.
- Docker Hub reste utilisable en repli (mêmes tags) si `ghcr.io` était indisponible :
  remplacez `ghcr.io/doorcloud/formation/nginx` par `nginx`, etc.

## Pour le formateur

- La veille : `KUBECONFIG=... scripts/k8s-prepull.sh` sur chaque cluster binôme (DaemonSet
  qui met toutes les images en cache sur chaque nœud).
- Ajouter une image : une ligne dans `kubernetes/images.txt`, push sur `main`, le workflow la
  copie ; vérifier que le package est **public** dans GitHub → Packages (par défaut il est privé).
- Un cluster DKS neuf met 10 à 60 min à finir d'installer la plateforme Door (images tirées
  depuis Docker Hub) : créer les clusters **la veille**, et vérifier avant le lab 07 que
  Trident est prêt : `kubectl -n kube-system get pods -l app=controller.csi.trident.netapp.io`.
