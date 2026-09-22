#!/usr/bin/env bash
# Spins up a throwaway local Postgres, applies a Supabase-compatible auth stub,
# then all migrations. Usage: scripts/local-db.sh [start|reset|stop|psql]
set -euo pipefail
# Work from the repo root with *relative* paths: on GitHub runners /home/runner isn't searchable by the
# postgres user, so absolute paths into the checkout fail even though the checkout itself is readable.
cd "$(dirname "$0")/.."
ROOT=.
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
DATA="${PGDATA_DIR:-/tmp/cartel-pg}"
PORT="${PGPORT:-54329}"
export PGHOST=localhost PGPORT=$PORT PGUSER=postgres PGDATABASE=cartel

start() {
  if [ ! -f "$DATA/PG_VERSION" ]; then
    "$PGBIN/initdb" -D "$DATA" -U postgres --auth=trust >/dev/null
  fi
  if ! "$PGBIN/pg_ctl" -D "$DATA" status >/dev/null 2>&1; then
    "$PGBIN/pg_ctl" -D "$DATA" -o "-p $PORT -k /tmp" -l "$DATA/log" start >/dev/null
    sleep 1
  fi
}

reset() {
  start
  psql -d postgres -qc "drop database if exists cartel" -c "create database cartel"
  psql -v ON_ERROR_STOP=1 -q -f "$ROOT/scripts/auth-stub.sql"
  for f in "$ROOT"/supabase/migrations/*.sql; do
    echo "applying $(basename "$f")"
    psql -v ON_ERROR_STOP=1 -q -f "$f"
  done
}

case "${1:-reset}" in
  start) start ;;
  reset) reset ;;
  stop)  "$PGBIN/pg_ctl" -D "$DATA" stop >/dev/null ;;
  psql)  shift; start; psql "$@" ;;
  test)  reset; psql -v ON_ERROR_STOP=1 -q -f "$ROOT/scripts/smoke-test.sql"; psql -v ON_ERROR_STOP=1 -q -f "$ROOT/scripts/casino-test.sql"; psql -v ON_ERROR_STOP=1 -q -f "$ROOT/scripts/forum-test.sql" ;;
  demo)  start; psql -v ON_ERROR_STOP=1 -q -f "$ROOT/scripts/seed-demo.sql" ;;
  *) echo "usage: $0 [start|reset|stop|test|demo|psql]"; exit 1 ;;
esac
