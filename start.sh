#!/bin/sh
# Start script for JT Doc Tools on Railway.
# 1. Fix the volume's ownership (Railway mounts volumes as root).
# 2. Cap thread pools to the service's CPU quota (Railway shows the host's CPUs).
# 3. Size job concurrency from the memory limit on first boot.
# 4. Create the admin from ADMIN_USERNAME / ADMIN_PASSWORD and switch login on
#    BEFORE the port opens (upstream ships with login off).
# 5. exec uvicorn, so a crash exits non-zero and Railway restarts it.
set -eu

DATA="${JTDT_DATA_DIR:-/data}"
export JTDT_DATA_DIR="$DATA"
PORT="${PORT:-8765}"
export JTDT_PORT="$PORT" JTDT_HOST=0.0.0.0

: "${ADMIN_USERNAME:=jtdt-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
if [ "${#ADMIN_PASSWORD}" -lt 16 ] || [ "${#ADMIN_PASSWORD}" -gt 128 ]; then
  echo "jtdt-start: ADMIN_PASSWORD must be 16 to 128 characters; refusing to start without a login" >&2
  exit 1
fi
export ADMIN_USERNAME ADMIN_PASSWORD

mkdir -p "$DATA"
if [ "$(id -u)" = "0" ]; then
  chown -R jtdt:jtdt "$DATA"
  RUN_AS="setpriv --reuid=10001 --regid=10001 --init-groups --"
else
  RUN_AS=""
fi

# CPU quota from cgroup v2 cpu.max ("max 100000" or "200000 100000").
CPUS=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r q p < /sys/fs/cgroup/cpu.max || true
  if [ "${q:-max}" != "max" ] && [ -n "${p:-}" ] && [ "$p" -gt 0 ]; then
    CPUS=$(( (q + p - 1) / p ))
  fi
fi
if [ -z "$CPUS" ]; then CPUS=$(nproc 2>/dev/null || echo 2); fi
[ "$CPUS" -gt 8 ] && CPUS=8
[ "$CPUS" -lt 1 ] && CPUS=1
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}" \
       OMP_THREAD_LIMIT="${OMP_THREAD_LIMIT:-1}" \
       OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}" \
       MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}" \
       NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}" \
       MAX_CONCURRENCY="${MAX_CONCURRENCY:-$CPUS}" \
       JTDT_SAVE_CONCURRENCY="${JTDT_SAVE_CONCURRENCY:-$CPUS}" \
       MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

# Memory limit in MB (cgroup v2), 0 if unlimited.
MEM_MB=0
if [ -r /sys/fs/cgroup/memory.max ]; then
  m=$(cat /sys/fs/cgroup/memory.max)
  [ "$m" != "max" ] && MEM_MB=$(( m / 1048576 ))
fi
export JTDT_CPUS="$CPUS" JTDT_MEM_MB="$MEM_MB"
echo "jtdt-start: cpus=$CPUS mem_limit_mb=$MEM_MB port=$PORT data=$DATA"

# Admin bootstrap + concurrency defaults (runs as the app user, exits non-zero on failure).
cd /app
$RUN_AS /app/.venv/bin/python /opt/jtdt/bootstrap.py

exec $RUN_AS /app/.venv/bin/python -m uvicorn app.main:app \
  --host 0.0.0.0 --port "$PORT" --workers 1 --timeout-graceful-shutdown 10
