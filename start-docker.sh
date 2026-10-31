#!/bin/bash
# ROV Topside — start all services in Docker
<<<<<<< HEAD
# Usage: ./start-docker.sh           (builds image on first run)
#        ./start-docker.sh --build   (rebuild after code changes)
=======
# Usage: ./start-docker.sh
>>>>>>> 613bc57504edb5b445fd2492fa1709f1f692d8f9

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== ROV Topside (Docker) ==="

# Ensure joystick devices are readable
for dev in /dev/input/event*; do
    if [ -r "$dev" ] 2>/dev/null; then continue; fi
    echo "[start] Setting input device permissions..."
    sudo chmod 666 /dev/input/event* /dev/input/js* 2>/dev/null
    break
done

# Clean stale DDS shared memory
rm -f /dev/shm/cyclonedds_* /dev/shm/iox_* 2>/dev/null || true

# Kill any stale ports
fuser -k 8080/tcp 9090/tcp 2>/dev/null || true
sleep 1

# Start containers
<<<<<<< HEAD
docker compose up -d "$@"
=======
docker compose up -d
>>>>>>> 613bc57504edb5b445fd2492fa1709f1f692d8f9
sleep 3

# Verify
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo ""
echo "Dashboard: http://localhost:8080"
echo "Captures saved to: ./captures/"
