# ROV Topside image: ROS 2 Lyrical Luth (Ubuntu 26.04 inside the container).
# The host can be any Linux with Docker (we use Debian 13).
#
# Two stages to keep the runtime image small:
#   build   -> ros-base (has colcon) builds the workspace
#   runtime -> ros-core (no compilers/build tools) + only the packages we use

ARG ROS_DISTRO=lyrical

# ---------------------------------------------------------------- build stage
FROM ros:${ROS_DISTRO}-ros-base AS build

WORKDIR /ros_ws
COPY src/ src/

# ament_python packages only, so no ROS deps are needed to build
RUN . /opt/ros/${ROS_DISTRO}/setup.sh && \
    colcon build --event-handlers console_direct-

# -------------------------------------------------------------- runtime stage
FROM ros:${ROS_DISTRO}-ros-core

ENV DEBIAN_FRONTEND=noninteractive

# Only what the nodes actually import:
#   rov_joystick       -> sensor_msgs, evdev
#   rov_dashboard      -> sensor_msgs, std_msgs, mavros_msgs, websockets
#   rov_photogrammetry -> sensor_msgs
# evdev/websockets come from apt so nothing has to be compiled or pip-installed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    ros-${ROS_DISTRO}-mavros-msgs \
    ros-${ROS_DISTRO}-std-srvs \
    python3-evdev \
    python3-websockets \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros_ws
COPY --from=build /ros_ws/install /ros_ws/install

# DDS config — uses env var CYCLONEDDS_URI at runtime for flexibility
COPY cyclonedds_topside.xml /ros_ws/cyclonedds.xml

ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ENV CYCLONEDDS_URI=file:///ros_ws/cyclonedds.xml

# Web dashboard ports
EXPOSE 8080 9090

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
