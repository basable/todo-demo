#!/usr/bin/env bash
# End-to-end test: the server's image against a real PostgreSQL, driven with
# curl from a third container. Needs nothing on the machine but Docker and
# bash: no published ports, no bind mounts.
#
#   test/e2e.sh [IMAGE]     (without IMAGE, the repository is built first)
set -euo pipefail
cd "$(dirname "$0")/.."

image=${1:-}
run="todo-e2e-$$"
network=$run
database=$run-postgres
app=$run-app
client_image=todo-demo-e2e-client
failures=0

cleanup() {
    docker rm -f "$app" "$database" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; [ $# -lt 2 ] || printf '        %s\n' "${@:2}"; failures=$((failures + 1)); }

client() { # run one phase of test/cases.sh on the test network
    docker run --rm --network "$network" "$client_image" "$1" || failures=$((failures + 1))
}
psql() {
    docker exec -i "$database" psql -v ON_ERROR_STOP=1 -q -U postgres -d todos "$@"
}

if [ -z "$image" ]; then
    say "building the server image"
    image=todo-demo:e2e
    docker build --platform linux/amd64 -t "$image" .
fi
say "building the test client"
docker build -q -f test/Dockerfile -t "$client_image" . >/dev/null

docker network create "$network" >/dev/null

say "starting the server before PostgreSQL, so it has to wait for it"
# The same environment as k8s/deployment.yaml, and the same restrictions as
# its pod: not root, no capabilities, a read-only file system.
docker run -d --name "$app" --network "$network" --network-alias app \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    -e PORT=8080 \
    -e DATABASE_URL='postgres://postgres@postgres:5432/todos?sslmode=disable' \
    "$image" >/dev/null
sleep 3
docker run -d --name "$database" --network "$network" --network-alias postgres \
    -e POSTGRES_DB=todos -e POSTGRES_USER=postgres \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    postgres:17-alpine >/dev/null
client wait

logs=$(docker logs "$app" 2>&1)
case $logs in
    *"waiting for database (attempt 1)"*) pass "it logged that it was waiting for the database" ;;
    *) fail "it logged that it was waiting for the database" "$logs" ;;
esac
case $logs in
    *"listening on 0.0.0.0:8080"*) pass "it logged where it listens" ;;
    *) fail "it logged where it listens" "$logs" ;;
esac
if [ "$(psql -tA -c "select count(*) from information_schema.tables where table_name = 'todos'")" = 1 ]; then
    pass "it created the todos table"
else
    fail "it created the todos table"
fi

say "the API, the web files and HTTP itself"
client api

say "createdAt, and a long title, for rows written straight into the table"
psql <<'SQL'
TRUNCATE todos;
INSERT INTO todos (id, title, done, created_at) VALUES
    (101, 'whole second',      false, '2026-01-02 03:04:05+00'),
    (102, 'hundredths',        false, '2026-01-02 03:04:05.12+00'),
    (103, 'microseconds',      false, '2026-01-02 03:04:05.123456+00'),
    (104, 'tenth',             true,  '2026-01-02 03:04:05.1+00'),
    (105, 'from another zone', false, '2026-01-02 05:04:06.5+02:00'),
    (106, repeat('L', 120),    false, '2026-01-02 03:04:07+00');
SQL
client timestamps

say "PostgreSQL restarts under the running server"
docker restart "$database" >/dev/null
for _ in $(seq 30); do
    if docker exec "$database" pg_isready -q -U postgres -d todos; then break; fi
    sleep 1
done
client recovery

say "clients that stall or trickle"
client slow

say "stopping the server the way Kubernetes does (SIGTERM)"
start=$(date +%s)
docker stop -t 10 "$app" >/dev/null
took=$(( $(date +%s) - start ))
code=$(docker inspect -f '{{.State.ExitCode}}' "$app")
if [ "$code" = 0 ] && [ "$took" -le 3 ]; then
    pass "it stops at once, with exit status 0 (${took}s)"
else
    fail "it stops at once, with exit status 0" "exit status $code after ${took}s"
fi

say "server log"
docker logs "$app" 2>&1 | sed 's/^/    /'

if [ "$failures" -ne 0 ]; then
    say "FAILED: $failures phase(s) or check(s) failed"
    exit 1
fi
say "all end-to-end checks passed"
