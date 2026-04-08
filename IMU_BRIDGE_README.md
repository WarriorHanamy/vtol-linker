# IMU Bridge: PX4 (ROS2) -> ROS1

Minimal bridge to forward PX4 HighresIMU data from ROS2 to ROS1 for LiDAR IMU initialization.

## Architecture

```
PX4 → Micro-XRCE-DDS → /fmu/out/highres_imu_flu (ROS2) → [Unix Socket] → /mavros/imu/data_raw (ROS1) → LI-Init
```

## Components

### ROS2 Side (`px4_connector`)
- **imu_sender_node**: Subscribes to `/fmu/out/highres_imu_flu` and sends via Unix socket
- Time sync: Uses `timestamp_sample` + initial offset to match ROS time

### ROS1 Side (`imu_bridge_ros1`)
- **imu_receiver_node**: Receives from Unix socket and publishes to `/mavros/imu/data_raw`
- Converts nanoseconds to ROS time format

## Usage

### Build

```bash
# Build PX4 connector (includes imu_sender_node)
make docker-build-px4-connector-jetson

# Build calibration container (includes imu_receiver_node)
make docker-build-calib-jetson
```

### Run with IMU Bridge

```bash
# Terminal 1: Start PX4 connector
make docker-run-px4-connector-jetson

# Terminal 2: Start calibration with IMU bridge
make docker-run-calib-jetson BAG=your_data.bag IMU_BRIDGE=true
```

### Run without IMU Bridge (existing behavior)

```bash
make docker-run-calib-jetson BAG=your_data.bag
```

## Time Synchronization

- Uses `timestamp_sample` (sensor sampling time) instead of `timestamp` (PX4 publish time)
- Calculates initial offset on first message: `offset = ros_now - timestamp_sample`
- Applies offset to all subsequent messages: `ros_time = timestamp_sample + offset`
- Ensures continuous timestamps compatible with LI-Init

## Socket

- Path: `/tmp/imu_bridge.sock`
- Protocol: Unix domain socket (SOCK_STREAM)
- Shared between containers via `--ipc=host`

## Data Format

```c++
struct ImuData {
    uint64_t timestamp;  // nanoseconds (ROS time)
    float accel[3];      // m/s² (FLU frame)
    float gyro[3];       // rad/s (FLU frame)
};
```
