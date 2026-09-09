#!/usr/bin/env bash
# Lab 06 — assertions non interactives (Linux, macOS, WSL).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
cd "$ROOT"

ok() { echo "OK: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

NAMES=(test-web crash-test mem-leak crash-restart)
CRASH_OUT="${TMPDIR:-/tmp}/lab06-crash-$$.out"

cleanup() {
  docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
  rm -f "$CRASH_OUT"
}
trap cleanup EXIT

cleanup

for img in nginx:1.27-alpine busybox:1.36 python:3.12-slim; do
  docker pull "$img" >/dev/null
done

# ---------------------------------------------------------------------------
# 1. Conteneur sain + options de logs
# ---------------------------------------------------------------------------
docker run -d --name test-web \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  nginx:1.27-alpine >/dev/null

status="$(docker inspect --format '{{.State.Status}}' test-web)"
[[ "$status" == "running" ]] || fail "test-web devrait être running (obtenu: $status)"
ok "test-web est running"

log_driver="$(docker inspect --format '{{.HostConfig.LogConfig.Type}}' test-web)"
[[ "$log_driver" == "json-file" ]] || fail "driver de logs json-file attendu (obtenu: $log_driver)"
max_size="$(docker inspect --format '{{index .HostConfig.LogConfig.Config "max-size"}}' test-web)"
max_file="$(docker inspect --format '{{index .HostConfig.LogConfig.Config "max-file"}}' test-web)"
[[ "$max_size" == "10m" ]] || fail "log-opt max-size=10m attendu (obtenu: $max_size)"
[[ "$max_file" == "3" ]] || fail "log-opt max-file=3 attendu (obtenu: $max_file)"
ok "log-driver json-file + max-size=10m + max-file=3"

docker exec test-web nginx -t >/dev/null 2>&1 || fail "nginx -t a échoué dans test-web"
ok "docker exec test-web nginx -t"

top_out="$(docker top test-web)"
grep -q nginx <<<"$top_out" || fail "docker top test-web ne montre pas nginx"
ok "docker top affiche nginx"

stats_out="$(docker stats --no-stream test-web)"
grep -q test-web <<<"$stats_out" || fail "docker stats --no-stream n'a pas listé test-web"
ok "docker stats --no-stream"

docker logs --tail 5 test-web >/dev/null 2>&1
docker logs --since 5m test-web >/dev/null 2>&1
ok "docker logs --tail / --since"

# ---------------------------------------------------------------------------
# 2. Crash immédiat (exit 1) — if protège set -e
# ---------------------------------------------------------------------------
if docker run --name crash-test busybox:1.36 sh -c "echo 'Crash imminent'; exit 1" >"$CRASH_OUT" 2>&1; then
  fail "crash-test aurait dû se terminer en erreur"
fi
grep -q "Crash imminent" "$CRASH_OUT" || fail "la sortie de crash-test doit contenir 'Crash imminent'"

ps_a="$(docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^crash-test ' || true)"
grep -q "Exited (1)" <<<"$ps_a" || fail "docker ps -a doit montrer Exited (1) pour crash-test (obtenu: $ps_a)"
ok "crash-test est Exited (1)"

read -r crash_ec crash_oom <<<"$(docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' crash-test)"
[[ "$crash_ec" == "1" ]] || fail "ExitCode crash-test=1 attendu (obtenu: $crash_ec)"
[[ "$crash_oom" == "false" ]] || fail "OOMKilled crash-test=false attendu (obtenu: $crash_oom)"
ok "inspect crash-test: ExitCode=1 OOMKilled=false"

docker logs crash-test 2>&1 | grep -q "Crash imminent" || fail "docker logs crash-test vide"
ok "docker logs crash-test"

# ---------------------------------------------------------------------------
# 3. OOMKilled sous --memory=128m
# ---------------------------------------------------------------------------
docker run -d --name mem-leak \
  --memory=128m \
  --memory-swap=128m \
  python:3.12-slim \
  python -c 'x=[]; exec("while True: x.append(bytearray(8*1024*1024))")' >/dev/null

mem_status="running"
i=0
while [ "$i" -lt 45 ]; do
  mem_status="$(docker inspect --format '{{.State.Status}}' mem-leak)"
  if [[ "$mem_status" == "exited" ]]; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
[[ "$mem_status" == "exited" ]] || fail "mem-leak devrait être exited (OOM) en ≤45s (status=$mem_status)"

read -r mem_ec mem_oom <<<"$(docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}}' mem-leak)"
[[ "$mem_ec" == "137" ]] || fail "ExitCode mem-leak=137 attendu (obtenu: $mem_ec)"
[[ "$mem_oom" == "true" ]] || fail "OOMKilled mem-leak=true attendu (obtenu: $mem_oom)"
ok "mem-leak OOMKilled=true ExitCode=137"

# ---------------------------------------------------------------------------
# 4. Redémarrages on-failure:3
# ---------------------------------------------------------------------------
docker run -d --name crash-restart --restart=on-failure:3 \
  busybox:1.36 sh -c "echo 'Crash imminent'; exit 1" >/dev/null

count=0
i=0
while [ "$i" -lt 25 ]; do
  count="$(docker inspect --format '{{.RestartCount}}' crash-restart)"
  if [ "$count" -ge 3 ]; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$count" -ge 3 ] || fail "RestartCount >= 3 attendu pour crash-restart (obtenu: $count)"
ok "crash-restart RestartCount=$count (on-failure:3)"

# ---------------------------------------------------------------------------
# 5. events + system df (non bloquant)
# ---------------------------------------------------------------------------
events_out="$(docker events --since 5m --until 0s 2>/dev/null || true)"
if [[ -z "$events_out" ]]; then
  events_out="$(docker events --since 5m --until now 2>/dev/null || true)"
fi
[[ -n "$events_out" ]] || fail "docker events --since 5m --until 0s n'a renvoyé aucune ligne"
ok "docker events --since 5m --until 0s"

df_out="$(docker system df)"
[[ -n "$df_out" ]] || fail "docker system df vide"
ok "docker system df"

ok "lab06-debug terminé"
exit 0
