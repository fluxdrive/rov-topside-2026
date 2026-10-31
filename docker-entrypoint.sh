#!/bin/bash
set +u
<<<<<<< HEAD
# ROS_DISTRO is set by the ros:<distro> base image (lyrical)
source "/opt/ros/${ROS_DISTRO:-lyrical}/setup.bash"
=======
source /opt/ros/jazzy/setup.bash
>>>>>>> 613bc57504edb5b445fd2492fa1709f1f692d8f9
source /ros_ws/install/setup.bash
exec "$@"
