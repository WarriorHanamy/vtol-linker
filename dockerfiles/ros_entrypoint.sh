#!/bin/bash
set -eo pipefail

# ROS2 setup.bash references unbound variables (e.g. AMENT_TRACE_SETUP_FILES).
# Temporarily disable nounset around sourcing to avoid "unbound variable" errors.
set +u
source /opt/ros/humble/setup.bash

WS_SETUP="${WS_DIR:-/root/ros2_ws}/install/setup.bash"
if [ -f "$WS_SETUP" ]; then
    source "$WS_SETUP"
fi
set -u

exec "$@"
