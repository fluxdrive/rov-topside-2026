#!/bin/bash
# One-time host setup for the topside laptop on Debian 13 "trixie" (amd64).
#
# Suggested install: Debian netinst with only "Xfce" (or LXQt) + "standard system utilities"
# ticked. You just need a browser for the dashboard. ROS 2 Lyrical runs inside Docker,
# so nothing ROS-related is installed on the host.
#
# Usage:
#   sudo ./host-setup/setup-debian.sh                  # Docker, DS4 permissions, firewall rules if ufw is on
#   sudo ./host-setup/setup-debian.sh --network        # also set the tether's static IP
#
# Re-running is safe.

set -euo pipefail

TETHER_IFACE="${TETHER_IFACE:-}"                  # e.g. enp3s0; auto-detected if empty
TETHER_ADDR="${TETHER_ADDR:-192.168.1.69/24}"     # Pi 5 is 192.168.1.70
ROV_SUBNET="${ROV_SUBNET:-192.168.1.0/24}"

CONFIGURE_NETWORK=false
[[ "${1:-}" == "--network" ]] && CONFIGURE_NETWORK=true

if [[ $EUID -ne 0 ]]; then echo "Run with sudo."; exit 1; fi
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

. /etc/os-release
echo "[setup] Host: $PRETTY_NAME ($(uname -m)), user: $TARGET_USER"

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git psmisc

# --- Docker Engine ---
if ! command -v docker >/dev/null; then
    echo "[setup] Installing Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if [[ ! -f /etc/docker/daemon.json ]]; then
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
fi
systemctl enable --now docker
systemctl restart docker
usermod -aG docker,input "$TARGET_USER"

# --- DualShock 4: readable without sudo chmod (USB and Bluetooth) ---
cat > /etc/udev/rules.d/99-ds4.rules <<'EOF'
# Sony DualShock 4 (054c:05c4 v1, 054c:09cc v2) - allow evdev reads for the ROV joystick node
SUBSYSTEM=="input", ATTRS{idVendor}=="054c", MODE="0666"
SUBSYSTEM=="input", KERNELS=="*054C:05C4*", MODE="0666"
SUBSYSTEM=="input", KERNELS=="*054C:09CC*", MODE="0666"
EOF
udevadm control --reload-rules && udevadm trigger --subsystem-match=input || true

# --- Firewall: only matters if ufw is installed and active ---
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    echo "[setup] ufw is active; allowing ROV traffic from $ROV_SUBNET"
    ufw allow from "$ROV_SUBNET" to any port 7400:7600 proto udp comment 'ROS 2 Cyclone DDS'
    ufw allow from "$ROV_SUBNET" to any port 8080,9090 proto tcp comment 'ROV dashboard'
fi

# --- Optional: static tether IP via NetworkManager ---
if $CONFIGURE_NETWORK; then
    if ! command -v nmcli >/dev/null; then
        echo "[setup] nmcli not found; set $TETHER_ADDR on the tether NIC manually (/etc/network/interfaces)."
    else
        if [[ -z "$TETHER_IFACE" ]]; then
            TETHER_IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')
        fi
        [[ -z "$TETHER_IFACE" ]] && { echo "[setup] No ethernet NIC found; set TETHER_IFACE=..."; exit 1; }
        echo "[setup] Tether: $TETHER_IFACE -> $TETHER_ADDR"
        nmcli con delete rov-tether >/dev/null 2>&1 || true
        nmcli con add type ethernet con-name rov-tether ifname "$TETHER_IFACE" \
            ipv4.method manual ipv4.addresses "$TETHER_ADDR" ipv4.never-default yes ipv6.method disabled \
            connection.autoconnect yes
    fi
fi

cat <<EOF

[setup] Done. Next steps:
  1. Log out and back in so '$TARGET_USER' picks up the docker/input groups.
  2. cd ~/rov_topside_ws && ./start-docker.sh     # first run builds the Lyrical image
  3. Open http://localhost:8080
EOF
