# ROV Topside

Pilot station software for the underwater ROV. Runs on the topside laptop (AlmaLinux 10, ROS 2 Lyrical Luth from RoboStack via pixi) connected to the ROV via Ethernet tether.

## Hardware

| Component | Details |
|-----------|---------|
| Computer | AlmaLinux 10 x86_64 (`192.168.1.69`), alternative: Debian 13 + Docker |
| ROS | ROS 2 Lyrical Luth from RoboStack (pixi), or Docker on Debian |
| Controller | DualShock 4 (USB or Bluetooth) |
| Tether | Ethernet to Pi 5 at `192.168.1.70` |

## Quick Start

### Recommended: RoboStack (pixi) on AlmaLinux 10

ROS 2 Lyrical comes from [RoboStack](https://robostack.github.io) through [pixi](https://pixi.sh), pinned in `pixi.toml` / `pixi.lock`. Nothing ROS-related is installed system-wide, and the same setup works on any x86_64 Linux.

```bash
git clone git@github.com:aikios/rov-topside.git ~/rov_topside_ws
cd ~/rov_topside_ws
./host-setup/setup-almalinux.sh             # run as your user, not sudo
./host-setup/setup-almalinux.sh --network   # optional: static 192.168.1.69 on the tether NIC
```

The script installs pixi, adds the DS4 udev rule, trusts `192.168.1.0/24` in firewalld, adds a `rov-shell` alias, then runs `pixi install`, `pixi run build` and `pixi run check`. Log out/in once, then:

```bash
./start.sh          # re-runs itself inside the pixi env; foreground (Ctrl+C to stop)
./start.sh -d       # daemon mode (logs in ./logs/)
./stop.sh
```

Open dashboard: **http://localhost:8080**

Day to day:

| Command | What it does |
|---|---|
| `pixi run build` | `colcon build --symlink-install` |
| `pixi run check` | Verifies rclpy, mavros_msgs, evdev, websockets import |
| `rov-shell` (or `pixi shell`) | Shell with ROS sourced: `ros2 topic list`, `ros2 bag record ...` |
| `pixi add <pkg>` | Add a dependency (RoboStack ROS packages are `ros-lyrical-*`) |

Commit `pixi.lock` after the first successful install so every machine resolves identical versions. `rosdep` doesn't apply inside pixi; add dependencies with `pixi add`.

On other distros, install pixi (`curl -fsSL https://pixi.sh/install.sh | bash`), then `pixi install && ./start.sh`. The DS4 udev rule and firewall steps from the script still apply.

### Alternative: Debian 13 + Docker

Install Debian 13 from the netinst image, ticking only a light desktop (Xfce or LXQt) and "standard system utilities".

```bash
git clone git@github.com:aikios/rov-topside.git ~/rov_topside_ws
cd ~/rov_topside_ws
sudo ./host-setup/setup-debian.sh            # Docker, DS4 udev rule, ufw rules if ufw is active
sudo ./host-setup/setup-debian.sh --network  # optional: static 192.168.1.69 on the ethernet NIC
```

Log out/in once so the `docker` and `input` groups apply.

#### Run (Docker)

```bash
./start-docker.sh           # builds the Lyrical image on first run, starts all containers
./start-docker.sh --build   # rebuild after code changes
./stop-docker.sh            # stops and removes containers
```

Open dashboard: **http://localhost:8080**

ROS tools from inside a running container:

```bash
docker compose exec web_dashboard ros2 topic list
```

### Native on other distros (any machine with ROS 2 Lyrical installed, e.g. Ubuntu 26.04)

```bash
cd ~/rov_topside_ws
source /opt/ros/lyrical/setup.bash
colcon build --symlink-install
source install/setup.bash

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file://$HOME/rov_topside_ws/cyclonedds_topside.xml

./start.sh          # foreground (Ctrl+C to stop)
./start.sh -d       # daemon mode (logs in ./logs/)
./stop.sh           # stop everything
```

`start.sh` exits with a message if `/opt/ros/lyrical` is missing. Override with `ROS_DISTRO=<distro> ./start.sh`.

## ROS2 Packages

### `rov_joystick` — DualShock 4 publisher

**Node:** `joy_publisher`

Custom DS4 driver using `evdev` (replaces `ros2-joy` which has DS4 issues):

- Reads `/dev/input/event*` directly via evdev
- Publishes `sensor_msgs/Joy` on `/joy` at 20 Hz
- Normalises axes to `−1.0…+1.0`, applies ROS conventions (Y-inverted sticks, triggers mapped `1.0`→`−1.0`)
- Correctly identifies the DS4 main gamepad vs touchpad/motion sensor devices

### `rov_dashboard` — Web UI

**Node:** `server`

Browser-based operator dashboard:

- **HTTP `:8080`** — serves `static/index.html`
- **WebSocket `:9090`** — pushes JSON state to all connected browsers at 10 Hz, binary frames for camera preview

Dashboard panels:
- Live camera preview from Pi Zero (~2 fps MJPEG)
- Joystick axis bars + motor output visualisation (8 channels)
- FC heartbeat indicator, armed state, flight mode, depth readout
- Depth hold status and live PID gains (P/I/D)
- Photogrammetry capture flash indicator and count
- Camera rotation toggle button

Subscribes to: `/joy`, `/mavros/state`, `/mavros/battery`, `/mavros/vfr_hud`, `/mavros/mavros/override`, `/mavros/mavros/out`, `/rov/depth_setpoint`, `/rov/depth_current`, `/rov/depth_hold_active`, `/rov/pid_status`, `/rov/fc_heartbeat`, `/photogrammetry/preview`, `/photogrammetry/image`

### `rov_photogrammetry` — Image saver

**Node:** `saver`

- Subscribes `/photogrammetry/image` (`sensor_msgs/CompressedImage`)
- Saves each frame as a timestamped JPEG to `./captures/`
- Configurable save path via `save_dir` ROS parameter

## Controller Mapping

| Input | Action |
|-------|--------|
| Left stick Y / X | Surge / Sway |
| Right stick Y / X | Heave / Yaw (manual mode) |
| Square | Toggle depth hold |
| L1 / R1 | Depth setpoint −0.25 m / +0.25 m |
| Circle | Photogrammetry capture |
| Options | Arm / Disarm |

## Network & DDS

CycloneDDS with unicast peer discovery (no multicast). Edit `cyclonedds_topside.xml` if IPs change:

```xml
<Peer address="192.168.1.70"/>  <!-- Pi 5 onboard -->
<Peer address="192.168.1.69"/>  <!-- this machine (self) -->
```

All containers use `network_mode: host`. `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` is set in start scripts and Dockerfile (Lyrical's default is still Fast DDS).

If the laptop's Wi-Fi or `docker0` confuses discovery, uncomment the `<Interfaces>` block in `cyclonedds_topside.xml` to pin DDS to the tether address.

## Captures

Photogrammetry images are saved to `./captures/` (relative to the workspace root). In Docker, this folder is bind-mounted into the container.

## Dependencies

RoboStack environment (`pixi.toml`): `ros-lyrical-ros-base`, `ros-lyrical-rmw-cyclonedds-cpp`, `ros-lyrical-mavros-msgs`, `ros-lyrical-std-srvs`, `websockets`, `colcon-common-extensions`, `setuptools>=68,<80`, and `evdev-binary` from PyPI.

Debian (installed by `host-setup/setup-debian.sh`): Docker Engine + Compose plugin.

Container (installed by the Dockerfile, ROS 2 Lyrical):

- `ros-lyrical-rmw-cyclonedds-cpp`
- `ros-lyrical-mavros-msgs`, `ros-lyrical-std-srvs`
- `python3-evdev`, `python3-websockets` (apt, nothing compiled)

## Related Repo

Onboard Pi 5 software: [`aikios/rov-onboard`](https://github.com/aikios/rov-onboard)
