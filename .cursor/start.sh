#!/usr/bin/env bash
# Per-boot startup for the Goof Cloud Agent environment.
# Starts the Docker daemon (fuse-overlayfs) and the mongo:3 + mysql:5 database
# containers the app depends on, then waits until they accept connections.
# Idempotent: safe to run repeatedly; it will not create duplicate containers.
set -euo pipefail

wait_for_port() {
  local host="$1" port="$2" name="$3" tries="${4:-60}"
  for _ in $(seq 1 "$tries"); do
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
      exec 3>&- 3<&- 2>/dev/null || true
      echo "${name} is ready on ${host}:${port}"
      return 0
    fi
    sleep 1
  done
  echo "WARNING: ${name} did not become ready on ${host}:${port}" >&2
  return 1
}

# --- Ensure the Docker daemon is running ---
if ! sudo docker info >/dev/null 2>&1; then
  sudo rm -f /var/run/docker.pid
  sudo setsid dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 30); do sudo docker info >/dev/null 2>&1 && break; sleep 1; done
fi

# --- MongoDB (mongo:3) ---
if ! sudo docker ps --format '{{.Names}}' | grep -qx 'goof-mongo'; then
  sudo docker rm -f goof-mongo >/dev/null 2>&1 || true
  sudo docker image inspect mongo:3 >/dev/null 2>&1 || sudo docker pull mongo:3
  sudo docker run -d --name goof-mongo -p 27017:27017 mongo:3 >/dev/null
fi

# --- MySQL (mysql:5, for the TypeORM users table) ---
if ! sudo docker ps --format '{{.Names}}' | grep -qx 'goof-mysql'; then
  sudo docker rm -f goof-mysql >/dev/null 2>&1 || true
  sudo docker image inspect mysql:5 >/dev/null 2>&1 || sudo docker pull mysql:5
  sudo docker run -d --name goof-mysql \
    -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=acme \
    -p 3306:3306 mysql:5 >/dev/null
fi

# --- Wait for the databases so the app connects cleanly on first launch ---
wait_for_port 127.0.0.1 27017 "MongoDB" 60 || true
wait_for_port 127.0.0.1 3306 "MySQL" 120 || true

echo "start.sh complete"
