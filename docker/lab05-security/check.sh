#!/usr/bin/env bash
# Lab 05 — namespaces PID, capabilities, seccomp, AppArmor (optionnel), user, read-only, limits.
set -euo pipefail

cd "$(dirname "$0")"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NAMES=(ns-a ns-host c-limits)

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

[[ -f no-mkdir.json ]] || fail "no-mkdir.json manquant"

grep -q '"defaultAction": "SCMP_ACT_ALLOW"' no-mkdir.json \
  || fail "no-mkdir.json : defaultAction SCMP_ACT_ALLOW requis"
grep -q 'SCMP_ACT_ERRNO' no-mkdir.json \
  || fail "no-mkdir.json : SCMP_ACT_ERRNO manquant"
grep -q '"architectures"' no-mkdir.json \
  || fail "no-mkdir.json : liste architectures manquante"
ok "no-mkdir.json : ALLOW + mkdir/mkdirat ERRNO + architectures"

docker pull alpine:3.20 >/dev/null
ok "image alpine:3.20"

# ---------------------------------------------------------------------------
# 1. PID namespace
# ---------------------------------------------------------------------------
docker run -d --name ns-a alpine:3.20 sleep 3600 >/dev/null
docker run -d --name ns-host --pid=host alpine:3.20 sleep 3600 >/dev/null

ps_a="$(docker exec ns-a ps)"
echo "$ps_a" | grep -q sleep || fail "ns-a ps doit montrer sleep"
if echo "$ps_a" | grep -Eq 'dockerd|containerd|systemd'; then
  fail "ns-a (PID isole) ne devrait pas montrer dockerd/containerd/systemd"
fi
n_a="$(echo "$ps_a" | awk 'END { print NR }')"
(( n_a <= 6 )) || fail "ns-a devrait avoir peu de processus (obtenu $n_a lignes: $ps_a)"
ok "ns-a : PID isole ($n_a lignes, sleep visible)"

ps_h="$(docker exec ns-host ps)"
n_h="$(echo "$ps_h" | awk 'END { print NR }')"
(( n_h > n_a )) || fail "--pid=host devrait lister plus de processus que ns-a (host=$n_h ns-a=$n_a)"
(( n_h >= 8 )) || fail "--pid=host trop peu de processus (obtenu $n_h) — isolation PID douteuse"
ok "ns-host --pid=host : $n_h lignes (> ns-a)"

docker rm -f ns-a ns-host >/dev/null

# ---------------------------------------------------------------------------
# 2. Capabilities
# ---------------------------------------------------------------------------
docker run --rm alpine:3.20 sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f' \
  || fail "chown devrait reussir avec les capabilities par defaut"
ok "chown OK par defaut"

if docker run --rm --cap-drop ALL alpine:3.20 sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f' \
  >/dev/null 2>&1; then
  fail "chown aurait du echouer avec --cap-drop ALL"
fi
ok "chown refuse avec --cap-drop ALL"

docker run --rm --cap-drop ALL --cap-add CHOWN alpine:3.20 \
  sh -c 'touch /tmp/f && chown 1000:1000 /tmp/f' \
  || fail "chown devrait reussir avec --cap-drop ALL --cap-add CHOWN"
ok "chown restaure avec --cap-add CHOWN"

# BusyBox date sort souvent 0 meme si settimeofday echoue : on assert le message, pas le code.
date_out="$(docker run --rm alpine:3.20 date -s '2020-01-01 00:00:00' 2>&1)" || true
echo "$date_out" | grep -q "can't set date" \
  || fail "date -s devrait afficher can't set date sans SYS_TIME (obtenu: $date_out)"
year="$(docker run --rm alpine:3.20 date +%Y)"
[[ "$year" != "2020" ]] || fail "l'horloge a ete changee (annee=$year) — ne pas ajouter SYS_TIME"
ok "date -s refuse sans SYS_TIME (message can't set date; annee=$year)"

# ---------------------------------------------------------------------------
# 3. Seccomp no-mkdir.json
# ---------------------------------------------------------------------------
seccomp="$(pwd)/no-mkdir.json"
docker run --rm --security-opt "seccomp=${seccomp}" alpine:3.20 touch /tmp/ok-touch \
  || fail "touch devrait reussir sous le profil no-mkdir"
ok "seccomp : touch autorise"

if docker run --rm --security-opt "seccomp=${seccomp}" alpine:3.20 mkdir /tmp/interdit \
  >/dev/null 2>&1; then
  fail "mkdir aurait du etre bloque par seccomp"
fi
ok "seccomp : mkdir bloque"

# ---------------------------------------------------------------------------
# 4. AppArmor (skip si aa-status absent ou inactif)
# ---------------------------------------------------------------------------
apparmor_on=0
if command -v aa-status >/dev/null 2>&1; then
  if aa-status --enabled >/dev/null 2>&1 || sudo -n aa-status --enabled >/dev/null 2>&1; then
    apparmor_on=1
  fi
fi

if (( apparmor_on == 0 )); then
  ok "AppArmor indisponible ou inactif — etape ignoree (Docker Desktop / macOS / Windows)"
else
  prof="$(docker run --rm alpine:3.20 cat /proc/1/attr/current)"
  echo "$prof" | grep -q 'docker-default' \
    || fail "profil AppArmor attendu docker-default (obtenu: [$prof])"
  ok "AppArmor docker-default (obtenu: $(echo "$prof" | tr -d '\n'))"
fi

# ---------------------------------------------------------------------------
# 5. Non-root + read-only + tmpfs /tmp
# ---------------------------------------------------------------------------
uid="$(docker run --rm --user 1000:1000 alpine:3.20 id -u)"
[[ "$uid" == "1000" ]] || fail "--user 1000:1000 devrait donner uid 1000 (obtenu: $uid)"
ok "--user 1000:1000 (uid=$uid)"

if docker run --rm --user 1000:1000 alpine:3.20 touch /root/x >/dev/null 2>&1; then
  fail "uid 1000 n'aurait pas du pouvoir ecrire dans /root"
fi
ok "uid 1000 : ecriture /root refusee"

docker run --rm --read-only --tmpfs /tmp alpine:3.20 touch /tmp/ok \
  || fail "touch /tmp devrait reussir avec --read-only --tmpfs /tmp"
ok "--read-only --tmpfs /tmp : /tmp inscriptible"

if docker run --rm --read-only --tmpfs /tmp alpine:3.20 touch /etc/interdit \
  >/dev/null 2>&1; then
  fail "touch /etc aurait du echouer en --read-only"
fi
ok "--read-only : /etc non inscriptible"

# ---------------------------------------------------------------------------
# 6. Limits memoire / CPU via inspect
# ---------------------------------------------------------------------------
docker run -d --name c-limits --memory=256m --cpus=0.5 alpine:3.20 sleep 60 >/dev/null
mem="$(docker inspect --format '{{.HostConfig.Memory}}' c-limits)"
nano="$(docker inspect --format '{{.HostConfig.NanoCpus}}' c-limits)"
[[ "$mem" == "268435456" ]] || fail "--memory=256m => 268435456 attendu (obtenu: $mem)"
[[ "$nano" == "500000000" ]] || fail "--cpus=0.5 => NanoCpus=500000000 attendu (obtenu: $nano)"
ok "inspect --memory=256m --cpus=0.5 (Memory=$mem NanoCpus=$nano)"

ok "lab05-security termine"
exit 0
