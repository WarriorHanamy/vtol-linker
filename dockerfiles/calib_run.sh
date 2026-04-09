#!/usr/bin/env bash
#
# LiDAR-IMU Calibration Runner
# Always uses IMU bridge (PX4 → ROS1 via Unix DGRAM socket)
#

readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
readonly DATA_DIR="/data"
readonly WS_DIR="/root/catkin_ws"
readonly RESULT_SRC="${WS_DIR}/src/LiDAR_IMU_Init/result/Initialization_result.txt"
readonly RESULT_DST="${DATA_DIR}/Initialization_result.txt"
readonly DEFAULT_LAUNCH="calib_with_imu.launch"

BAG_FILE=""
LAUNCH="${DEFAULT_LAUNCH}"
PLAY_RATE=""

fct_usage() {
	cat <<EOF
Usage: ${SCRIPT_NAME} [options] <bag_file>

Options:
  -h, --help        Show this help and exit
  -l, --launch NAME ROS launch file (default: ${DEFAULT_LAUNCH})
  -r, --rate RATE   rosbag play rate (default: 1.0)

Arguments:
  bag_file          Path to rosbag file inside ${DATA_DIR}/

Examples:
  ${SCRIPT_NAME} calibration_data.bag
  ${SCRIPT_NAME} --rate 0.5 calibration.bag
EOF
}

fct_parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h|--help) fct_usage; exit 0 ;;
		-l|--launch) LAUNCH="$2"; shift 2 ;;
		-r|--rate) PLAY_RATE="$2"; shift 2 ;;
		--) shift; [[ $# -ge 1 ]] && BAG_FILE="$1"; break ;;
		-*) echo "Unknown option: $1" >&2; fct_usage >&2; exit 2 ;;
		*) BAG_FILE="$1"; shift ;;
		esac
	done
	[[ -z "$BAG_FILE" ]] && { echo "Error: bag_file required" >&2; fct_usage >&2; exit 2; }
}

fct_validate_inputs() {
	[[ -f "$BAG_FILE" ]] || { echo "Error: bag not found: $BAG_FILE" >&2; exit 1; }
	[[ -f "${WS_DIR}/devel/setup.bash" ]] || { echo "Error: workspace not built" >&2; exit 1; }
	mkdir -p "$DATA_DIR"
}

fct_run_calibration() {
	source /opt/ros/noetic/setup.bash
	source "${WS_DIR}/devel/setup.bash"

	echo "========================================"
	echo " LiDAR-IMU Calibration (IMU bridge enabled)"
	echo "========================================"
	echo " Bag:   $BAG_FILE"
	echo " Launch: $LAUNCH"
	echo "========================================"

	roscore & local roscore_pid=$!; sleep 3
	kill -0 "$roscore_pid" 2>/dev/null || { echo "[ERROR] roscore failed" >&2; exit 1; }

	# Always use IMU bridge launch
	local launch_file="${WS_DIR}/src/LiDAR_IMU_Init/launch/${LAUNCH}"
	[[ -f "$launch_file" ]] || cp "/dockerfiles/calib_with_imu.launch" "$launch_file" 2>/dev/null || true
	roslaunch lidar_imu_init "$LAUNCH" rviz:=false & local node_pid=$!; sleep 5
	kill -0 "$node_pid" 2>/dev/null || { echo "[ERROR] li_init failed" >&2; kill "$roscore_pid" 2>/dev/null; exit 1; }

	local play_args=()
	[[ -n "$PLAY_RATE" ]] && play_args+=("--rate" "$PLAY_RATE")
	play_args+=("$BAG_FILE")

	echo "[INFO] Playing rosbag ..."
	rosbag play "${play_args[@]}"
	local bag_exit=$?

	echo "[INFO] Rosbag finished (exit=${bag_exit}), waiting for refinement ..."
	local wait_time=0
	local max_wait=$(( $(rosbag info --yaml "$BAG_FILE" 2>/dev/null | grep -oP 'duration: \K[0-9.]+' || echo "60") + 60 ))
	while kill -0 "$node_pid" 2>/dev/null && [[ $wait_time -lt $max_wait ]]; do sleep 2; wait_time=$((wait_time + 2)); done
	kill -0 "$node_pid" 2>/dev/null && { kill -INT "$node_pid" 2>/dev/null || true; sleep 5; kill "$node_pid" 2>/dev/null || true; }
	kill "$roscore_pid" 2>/dev/null || true; wait "$roscore_pid" 2>/dev/null || true
}

fct_collect_result() {
	if [[ -f "$RESULT_SRC" ]]; then
		cp "$RESULT_SRC" "$RESULT_DST"
		echo ""; echo "========================================"; echo " Calibration Result"; echo "========================================"
		cat "$RESULT_DST"
		echo ""; echo "Result saved to: $RESULT_DST"; echo "========================================"
	else
		echo "[WARN] Result not found: $RESULT_SRC" >&2
	fi
}

fct_cleanup() {
	set +e
	pkill -f "roscore" 2>/dev/null || true
	pkill -f "li_init" 2>/dev/null || true
	pkill -f "rosmaster" 2>/dev/null || true
	pkill -f "imu_receiver_node" 2>/dev/null || true
}

main() {
	set -euo pipefail
	trap fct_cleanup EXIT
	fct_parse_arguments "$@"
	fct_validate_inputs
	fct_run_calibration
	fct_collect_result
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
