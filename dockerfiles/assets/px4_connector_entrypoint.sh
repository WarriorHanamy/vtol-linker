#!/bin/bash
set -eo pipefail

# ROS2 setup.bash references unbound variables (e.g. AMENT_TRACE_SETUP_FILES).
# Temporarily disable nounset around sourcing to avoid "unbound variable" errors.
set +u
source /opt/ros/humble/setup.bash

WS_SETUP="${WS_DIR:-/home/ros/ros2_ws}/install/setup.bash"
source "$WS_SETUP"
set -u

MICRO_XRCE_DEVICE="${MICRO_XRCE_DEVICE:-/dev/ttyTHS1}"
MICRO_XRCE_BAUDRATE="${MICRO_XRCE_BAUDRATE:-921600}"

MicroXRCEAgent serial --dev "$MICRO_XRCE_DEVICE" -b "$MICRO_XRCE_BAUDRATE" &

sleep 3

OUTPUT_MODE="${OUTPUT_MODE:-topic}"

case "$OUTPUT_MODE" in
    topic)
        LAUNCH_FILE="px4_connector_topic.launch.py"
        ;;
    socket)
        LAUNCH_FILE="px4_connector_socket.launch.py"
        ;;
    *)
        echo "[ERROR] Unsupported OUTPUT_MODE: $OUTPUT_MODE (expected: topic|socket)" >&2
        exit 1
        ;;
esac

exec ros2 launch px4_connector "$LAUNCH_FILE" "$@"
