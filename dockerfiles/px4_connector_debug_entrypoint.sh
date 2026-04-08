#!/bin/bash
set -eo pipefail

# ROS2 setup.bash references unbound variables (e.g. AMENT_TRACE_SETUP_FILES).
# Temporarily disable nounset around sourcing to avoid "unbound variable" errors.
set +u
source /opt/ros/humble/setup.bash

WS_SETUP="${WS_DIR:-/root/px4_connector_ws}/install/setup.bash"
if [ -f "$WS_SETUP" ]; then
    source "$WS_SETUP"
fi
set -u

echo "=== PX4 Connector Debug Shell ==="
echo "ROS2 environment sourced."
echo "Workspace: ${WS_DIR:-/root/px4_connector_ws}"
echo ""

exec bash