#!/usr/bin/env bash
# Crée des VMs Ubuntu 24.04 de lab sur DigitalOcean (tag formation-docker).
# Usage : create-vms.sh <prefix> <count> [--keys-dir DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/cloud-init.yaml"
REGION="${DO_REGION:-ams3}"
SIZE="${DO_SIZE:-s-2vcpu-4gb}"
IMAGE="${DO_IMAGE:-ubuntu-24-04-x64}"
TAGS="formation-docker,docker-lab"
ORCH_PUBKEY_FILE="${ORCH_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"

usage() {
  cat <<'EOF'
Usage : create-vms.sh <prefix> <count> [--keys-dir DIR]

  prefix     nom de base des droplets (ex. lab-test, lab)
  count      nombre de VMs (1..N) — numérotées 01, 02, …
  --keys-dir répertoire des paires ed25519 et de vms.md
             (défaut : ./keys)

Variables d'environnement optionnelles :
  DO_REGION  (défaut ams3)  DO_SIZE (s-2vcpu-4gb)  DO_IMAGE (ubuntu-24-04-x64)
  ORCH_SSH_PUBKEY_FILE  (défaut $HOME/.ssh/id_ed25519.pub)
EOF
  exit 2
}

PREFIX=""
COUNT=""
KEYS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keys-dir)
      [[ $# -ge 2 ]] || usage
      KEYS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --*)
      echo "Option inconnue : $1" >&2
      usage
      ;;
    *)
      if [[ -z "$PREFIX" ]]; then
        PREFIX="$1"
      elif [[ -z "$COUNT" ]]; then
        COUNT="$1"
      else
        echo "Argument inattendu : $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[[ -n "$PREFIX" && -n "$COUNT" ]] || usage
if [[ ! "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "count doit être un entier >= 1" >&2
  exit 2
fi
[[ "$PREFIX" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || {
  echo "prefix invalide : $PREFIX" >&2
  exit 2
}

if [[ -z "$KEYS_DIR" ]]; then
  KEYS_DIR="${PWD}/keys"
fi
mkdir -p "$KEYS_DIR"
KEYS_DIR="$(cd "$KEYS_DIR" && pwd)"

[[ -f "$TEMPLATE" ]] || { echo "Template introuvable : $TEMPLATE" >&2; exit 1; }
[[ -f "$ORCH_PUBKEY_FILE" ]] || { echo "Clé orchestrateur introuvable : $ORCH_PUBKEY_FILE" >&2; exit 1; }

command -v doctl >/dev/null || { echo "doctl n'est pas installé" >&2; exit 1; }
command -v ssh-keygen >/dev/null || { echo "ssh-keygen introuvable" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 introuvable" >&2; exit 1; }

if ! doctl account get >/dev/null 2>&1; then
  echo "doctl n'est pas authentifié" >&2
  exit 1
fi

ORCH_FP=""
if ORCH_FP="$(doctl compute ssh-key import formation-docker-orch --public-key-file "$ORCH_PUBKEY_FILE" --format FingerPrint --no-header 2>/dev/null)"; then
  ORCH_FP="$(echo "$ORCH_FP" | tr -d '[:space:]')"
  echo "Clé SSH orchestrateur importée dans le compte DO (fingerprint ${ORCH_FP})"
else
  ORCH_FP="$(doctl compute ssh-key list --format Name,FingerPrint --no-header 2>/dev/null \
    | awk '$1=="formation-docker-orch" {print $2; exit}')"
  if [[ -z "$ORCH_FP" ]]; then
    ORCH_FP="$(doctl compute ssh-key list --format FingerPrint --no-header 2>/dev/null | awk 'NF{print; exit}')"
  fi
fi

SSH_KEYS_ARGS=()
if [[ -n "${ORCH_FP:-}" ]]; then
  SSH_KEYS_ARGS=(--ssh-keys "$ORCH_FP")
  echo "Droplets : --ssh-keys ${ORCH_FP} (compte ubuntu de secours)"
else
  echo "WARN: aucune clé dans le compte DO — accès uniquement via cloud-init / user formation"
fi

VMS_MD="${KEYS_DIR}/vms.md"
if [[ ! -f "$VMS_MD" ]]; then
  cat > "$VMS_MD" <<'EOF'
# VMs de lab — Formation Docker & Kubernetes (hors git)

| VM | IP | User | Fichier clé | SSH Windows (PowerShell) | SSH Ubuntu |
|----|----|------|-------------|--------------------------|------------|
EOF
fi

droplet_exists() {
  local name="$1"
  local found
  found="$(doctl compute droplet list --format Name --no-header 2>/dev/null | awk -v n="$name" '$0==n {print; exit}')"
  [[ -n "$found" ]]
}

droplet_ip() {
  local name="$1"
  doctl compute droplet get "$name" --format PublicIPv4 --no-header 2>/dev/null | tr -d '[:space:]'
}

render_user_data() {
  local pubfile="$1" outfile="$2"
  python3 - "$TEMPLATE" "$pubfile" "$ORCH_PUBKEY_FILE" "$outfile" <<'PY'
import pathlib, sys
tpl, pub, orch, out = map(pathlib.Path, sys.argv[1:5])
text = tpl.read_text()
text = text.replace("__SSH_PUBKEY__", pub.read_text().strip())
text = text.replace("__ORCH_SSH_PUBKEY__", orch.read_text().strip())
if "__SSH_PUBKEY__" in text or "__ORCH_SSH_PUBKEY__" in text:
    raise SystemExit("placeholder non substitué dans cloud-init")
out.write_text(text)
PY
}

upsert_vms_row() {
  local name="$1" ip="$2" keyfile="$3"
  local keybase
  keybase="$(basename "$keyfile")"
  local ps_cmd ub_cmd row
  ps_cmd="ssh -i .\\${keybase} formation@${ip}"
  ub_cmd="ssh -i ./${keybase} formation@${ip}"
  row="| ${name} | ${ip} | formation | ${keyfile} | \`${ps_cmd}\` | \`${ub_cmd}\` |"
  if grep -q "| ${name} |" "$VMS_MD" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    grep -v "| ${name} |" "$VMS_MD" > "$tmp"
    mv "$tmp" "$VMS_MD"
  fi
  echo "$row" >> "$VMS_MD"
}

echo "=== create-vms : prefix=${PREFIX} count=${COUNT} region=${REGION} size=${SIZE} keys=${KEYS_DIR} ==="

for i in $(seq 1 "$COUNT"); do
  nn="$(printf '%02d' "$i")"
  name="${PREFIX}-${nn}"
  keyfile="${KEYS_DIR}/${name}"
  pubfile="${keyfile}.pub"

  if [[ ! -f "$keyfile" ]]; then
    echo "[${name}] génération de la paire ed25519 (sans passphrase)"
    ssh-keygen -t ed25519 -f "$keyfile" -N "" -C "formation@${name}" -q
    chmod 600 "$keyfile"
    chmod 644 "$pubfile"
  else
    echo "[${name}] clé déjà présente : $keyfile"
    [[ -f "$pubfile" ]] || ssh-keygen -y -f "$keyfile" > "$pubfile"
  fi

  if droplet_exists "$name"; then
    ip="$(droplet_ip "$name")"
    echo "[${name}] droplet déjà existant — skip create (IP ${ip})"
    upsert_vms_row "$name" "$ip" "$keyfile"
    continue
  fi

  userdata="$(mktemp -t "cloud-init-${name}.XXXXXX.yaml")"
  render_user_data "$pubfile" "$userdata"

  echo "[${name}] création droplet ${SIZE} ${IMAGE} ${REGION}…"
  doctl compute droplet create "$name" \
    --region "$REGION" \
    --size "$SIZE" \
    --image "$IMAGE" \
    --user-data-file "$userdata" \
    --tag-names "$TAGS" \
    "${SSH_KEYS_ARGS[@]}" \
    --wait
  rm -f "$userdata"

  ip="$(droplet_ip "$name")"
  if [[ -z "$ip" ]]; then
    echo "[${name}] ERROR: pas d'IPv4 publique" >&2
    exit 1
  fi
  echo "[${name}] prêt côté DigitalOcean — IP ${ip} (cloud-init encore en cours)"
  upsert_vms_row "$name" "$ip" "$keyfile"
done

echo
echo "Table : $VMS_MD"
echo "Les VMs sont actives ; attendre cloud-init (docker + images) via :"
echo "  ssh -i <clé> formation@<IP> -- cloud-init status --wait"
echo "Détruire uniquement les VMs de formation :"
echo "  ${SCRIPT_DIR}/destroy-vms.sh"
