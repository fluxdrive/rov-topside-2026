# Sourced by pixi on `pixi run` / `pixi shell` (see [activation] in pixi.toml).
# RoboStack has already put ROS 2 Lyrical on the environment by this point.

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file://${PIXI_PROJECT_ROOT}/cyclonedds_topside.xml"

# Our own packages, once `pixi run build` has been run
if [ -f "${PIXI_PROJECT_ROOT}/install/setup.sh" ]; then
    . "${PIXI_PROJECT_ROOT}/install/setup.sh"
fi
