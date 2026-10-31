#!/bin/bash
# One-time setup for the topside laptop on AlmaLinux 10 (x86_64).
#
# ROS 2 Lyrical comes from RoboStack via pixi (pixi.toml in the repo root), so nothing
# ROS-related is installed system-wide. This script handles the host pieces only:
# pixi itself, DualShock 4 permissions, firewalld, optional static tether IP, then
# creates the pixi environment and builds the workspace.
#
# Usage (from the repo root, as your normal user; it calls sudo where needed):
#   ./host-setup/setup-almalinux.sh              # everything except network config
#   ./host-setup/setup-almalinux.sh --network    # also set the tether's static IP
#
# Re-running is safe. Most of it works on other distros too; only the dnf/firewalld bits are Alma-specific.

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TETHER_IFACE="${TETHER_IFACE:-}"                 # e.g. enp3s0 or a USB adapter; auto-detected if empty
TETHER_ADDR="${TETHER_ADDR:-192.168.1.69/24}"    # Pi is 192.168.1.70
ROV_SUBNET="${ROV_SUBNET:-192.168.1.0/24}"

CONFIGURE_NETWORK=false
[[ "${1:-}" == "--network" ]] && CONFIGURE_NETWORK=true

log()  { echo -e "\n\033[1;34m[setup]\033[0m $*"; }
warn() { echo -e "\033[1;33m[setup] WARNING:\033[0m $*"; }
die()  { echo -e "\033[1;31m[setup] ERROR:\033[0m $*"; exit 1; }

[[ $EUID -eq 0 ]] && die "Run as your normal user, not root/sudo. The script uses sudo itself."
[[ "$(uname -m)" == "x86_64" ]] || die "pixi.toml targets linux-64 (x86_64)."

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "almalinux" || "${VERSION_ID%%.*}" != "10" ]]; then
    warn "Written for AlmaLinux 10, found ${PRETTY_NAME:-unknown}. Continuing anyway."
fi
log "Host: $PRETTY_NAME, user: $USER, repo: $REPO_DIR"

# ------------------------------------------------------------- host packages
log "Installing host tools (curl, git, psmisc for fuser)..."
sudo dnf install -y curl git psmisc tar

# --------------------------------------------------------------------- pixi
if ! command -v pixi >/dev/null 2>&1 && [[ ! -x "$HOME/.pixi/bin/pixi" ]]; then
    log "Installing pixi..."
    curl -fsSL https://pixi.sh/install.sh | bash
fi
export PATH="$HOME/.pixi/bin:$PATH"
log "pixi $(pixi --version)"

# ------------------------------------------------------ DualShock 4 permissions
log "Adding DualShock 4 udev rule and input group..."
sudo tee /etc/udev/rules.d/99-ds4.rules >/dev/null <<'EOF'
# Sony DualShock 4 (054c:05c4 v1, 054c:09cc v2): allow evdev reads for the ROV joystick node
SUBSYSTEM=="input", ATTRS{idVendor}=="054c", MODE="0666"
SUBSYSTEM=="input", KERNELS=="*054C:05C4*", MODE="0666"
SUBSYSTEM=="input", KERNELS=="*054C:09CC*", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input || true
sudo usermod -aG input,dialout "$USER"

# ------------------------------------------------------------------- firewalld
if systemctl is-active --quiet firewalld; then
    log "firewalld: trusting the ROV subnet $ROV_SUBNET (DDS discovery + dashboard)"
    sudo firewall-cmd --permanent --zone=trusted --add-source="$ROV_SUBNET"
    sudo firewall-cmd --reload
fi

# --------------------------------------------------------- static tether IP
if $CONFIGURE_NETWORK; then
    if [[ -z "$TETHER_IFACE" ]]; then
        TETHER_IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')
    fi
    [[ -n "$TETHER_IFACE" ]] || die "No ethernet NIC found; rerun with TETHER_IFACE=<name> (see: nmcli device)"
    log "Tether: $TETHER_IFACE -> $TETHER_ADDR"
    sudo nmcli con delete rov-tether >/dev/null 2>&1 || true
    sudo nmcli con add type ethernet con-name rov-tether ifname "$TETHER_IFACE" \
        ipv4.method manual ipv4.addresses "$TETHER_ADDR" ipv4.never-default yes ipv6.method disabled \
        connection.autoconnect yes
fi

# ------------------------------------------------- shell convenience
if ! grep -q "# >>> rov-topside >>>" "$HOME/.bashrc" 2>/dev/null; then
    log "Adding 'rov-shell' alias to ~/.bashrc (a shell with ROS 2 sourced)"
    cat >> "$HOME/.bashrc" <<EOF

# >>> rov-topside >>>
export PATH="\$HOME/.pixi/bin:\$PATH"
alias rov-shell='pixi shell --manifest-path "$REPO_DIR/pixi.toml"'
# <<< rov-topside <<<
EOF
fi

# ------------------------------------- RoboStack environment + workspace build
cd "$REPO_DIR"
log "Creating the RoboStack environment (first run downloads a few GB)..."
pixi install
log "Building the workspace..."
pixi run build
log "Checking imports..."
pixi run check || warn "An import failed; see the error above."

if [[ -f pixi.lock ]] && git -C "$REPO_DIR" status --porcelain pixi.lock 2>/dev/null | grep -q .; then
    warn "pixi.lock was created/changed. Commit it so every machine gets the same versions."
fi

cat <<EOF

[setup] Done. Next steps:
  1. Log out and back in once (input/dialout groups).
  2. cd $REPO_DIR && ./start.sh        # runs inside the RoboStack env automatically
  3. Open http://localhost:8080
  For ROS CLI tools: rov-shell, then ros2 topic list
EOF
