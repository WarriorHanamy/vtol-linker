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
agent_pid=$!

cleanup() {
    kill "$agent_pid" 2>/dev/null || true
    if [ -n "${imu_pid:-}" ]; then
        kill "$imu_pid" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# OUTPUT_MODE 环境变量控制 IMU 输出模式
# - "topic": 启动 IMU bridge 并发布到 ROS2 topic
# - "socket": 启动 IMU bridge 并创建 Unix socket 桥
OUTPUT_MODE="${OUTPUT_MODE:-topic}"
IMU_OUTPUT_TOPIC="${IMU_OUTPUT_TOPIC:-/px4/imu}"

case "$OUTPUT_MODE" in
    topic|socket)
        ;;
    *)
        echo "[ERROR] Unsupported OUTPUT_MODE: $OUTPUT_MODE" >&2
        echo "[ERROR] Expected one of: topic, socket" >&2
        exit 1
        ;;
esac

ros2 launch imu_bridge sender.launch.py \
    output_mode:="$OUTPUT_MODE" \
    output_topic:="$IMU_OUTPUT_TOPIC" &
imu_pid=$!

if [ "$OUTPUT_MODE" = "socket" ]; then
    echo "[INFO] IMU bridge started (output_mode: socket, path: /tmp/imu_bridge.sock)"
else
    echo "[INFO] IMU bridge started (output_mode: topic, topic: $IMU_OUTPUT_TOPIC)"
fi

exec "$@"
