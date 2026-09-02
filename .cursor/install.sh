#!/usr/bin/env bash
# Idempotent dependency setup for the Goof Cloud Agent environment.
# Installs Docker (used to run the mongo:3 + mysql:5 databases the app needs),
# the fuse-overlayfs storage driver (the default overlayfs snapshotter fails in
# the nested Cloud Agent VM), and the Node.js dependencies. Best-effort pre-pull
# of the database images so a fresh boot starts quickly.
set -euo pipefail

cd "$(dirname "$0")/.."

export DEBIAN_FRONTEND=noninteractive

# --- System packages: Docker + fuse-overlayfs ---
if ! command -v docker >/dev/null 2>&1 || ! command -v fuse-overlayfs >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y docker.io fuse-overlayfs
fi

# The containerd/overlayfs snapshotter cannot extract images inside the nested
# Cloud Agent VM, so pin the classic graph driver backed by fuse-overlayfs.
sudo mkdir -p /etc/docker
echo '{"features":{"containerd-snapshotter":false},"storage-driver":"fuse-overlayfs"}' \
  | sudo tee /etc/docker/daemon.json >/dev/null

# --- Node dependencies ---
npm install

# --- Best-effort pre-pull of database images (cached on disk for fast boots) ---
# Non-fatal: if the daemon cannot run during the build phase, start.sh pulls on boot.
STARTED_DOCKERD=0
if ! sudo docker info >/dev/null 2>&1; then
  sudo rm -f /var/run/docker.pid
  sudo setsid dockerd >/tmp/dockerd-install.log 2>&1 &
  for _ in $(seq 1 30); do sudo docker info >/dev/null 2>&1 && break; sleep 1; done
  STARTED_DOCKERD=1
fi
if sudo docker info >/dev/null 2>&1; then
  sudo docker pull mongo:3 || true
  sudo docker pull mysql:5 || true
fi
# Stop the daemon only if this script started it (leave a pre-existing one alone).
if [ "$STARTED_DOCKERD" = "1" ] && [ -f /var/run/docker.pid ]; then
  sudo kill "$(cat /var/run/docker.pid)" 2>/dev/null || true
fi

echo "install.sh complete"
