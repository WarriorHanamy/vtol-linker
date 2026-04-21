#!/bin/bash
set -eo pipefail

MICRO_XRCE_DEVICE="${MICRO_XRCE_DEVICE:-/dev/ttyTHS1}"
MICRO_XRCE_BAUDRATE="${MICRO_XRCE_BAUDRATE:-921600}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-30}"
XRCE_DOMAIN_ID_OVERRIDE="${XRCE_DOMAIN_ID_OVERRIDE:-30}"
PX4_READY_TOPIC="${PX4_READY_TOPIC:-/fmu/out/highres_imu_flu}"
PX4_READY_TIMEOUT_SEC="${PX4_READY_TIMEOUT_SEC:-20}"
WS_SETUP="${WS_DIR:-/home/ros/ros2_ws}/install/setup.bash"

export ROS_DOMAIN_ID
export XRCE_DOMAIN_ID_OVERRIDE

OUTPUT_MODE="${OUTPUT_MODE:-topic}"

case "$OUTPUT_MODE" in
    topic)
        LAUNCH_FILE="px4_connector_imu_topic_only.launch.py"
        ;;
    socket)
        LAUNCH_FILE="px4_connector_socket.launch.py"
        ;;
    *)
        echo "[ERROR] Unsupported OUTPUT_MODE: $OUTPUT_MODE (expected: topic|socket)" >&2
        exit 1
        ;;
esac

launch_ros_when_px4_ready() {
    (
        set +u
        source /opt/ros/humble/setup.bash
        source "$WS_SETUP"
        set -u

        deadline=$((SECONDS + PX4_READY_TIMEOUT_SEC))
        until ros2 topic list 2>/dev/null | grep -Fxq "$PX4_READY_TOPIC"; do
            if [ "$SECONDS" -ge "$deadline" ]; then
                echo "[WARN] Timed out waiting for PX4 topic $PX4_READY_TOPIC after ${PX4_READY_TIMEOUT_SEC}s" >&2
                break
            fi
            sleep 1
        done

        exec ros2 launch px4_connector "$LAUNCH_FILE" "$@"
    )
}

cleanup() {
    if [ -n "${launch_pid:-}" ]; then
        kill "$launch_pid" 2>/dev/null || true
    fi
    if [ -n "${agent_pid:-}" ]; then
        kill "$agent_pid" 2>/dev/null || true
    fi
    wait "${launch_pid:-}" 2>/dev/null || true
    wait "${agent_pid:-}" 2>/dev/null || true
}

trap cleanup SIGINT SIGTERM

launch_ros_when_px4_ready "$@" &
launch_pid=$!

MicroXRCEAgent serial --dev "$MICRO_XRCE_DEVICE" -b "$MICRO_XRCE_BAUDRATE" &
agent_pid=$!

wait -n "$agent_pid" "$launch_pid"
status=$?
cleanup
exit "$status"
