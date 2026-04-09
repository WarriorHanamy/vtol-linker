# IMU Bridge: PX4 (ROS2) -> ROS1

Minimal bridge to forward PX4 HighresIMU data from ROS2 to ROS1 for LiDAR IMU initialization.

## Architecture

```
PX4 → Micro-XRCE-DDS → /fmu/out/highres_imu_flu (ROS2) → [Unix DGRAM Socket] → /mavros/imu/data_raw (ROS1) → LI-Init
```

## Components

### ROS2 Side (`px4_connector`)
- **imu_sender_node**: Subscribes to `/fmu/out/highres_imu_flu` and sends via Unix datagram socket
- Uses `timestamp_sample` + initial offset to match ROS time
- Connectionless: no handshake, fire-and-forget datagrams

### ROS1 Side (`imu_bridge_ros1`)
- **imu_receiver_node**: Receives from Unix datagram socket and publishes to `/mavros/imu/data_raw`
- Uses **threaded ring buffer** (~2 seconds, 2000 messages):
  - **Receiver thread**: polls socket @ ~10kHz, pushes to buffer (drops oldest if full)
  - **Publisher thread**: pops from buffer, publishes to ROS at native rate
- Converts nanoseconds to ROS time format

## Socket

- Path: `/tmp/imu_bridge.sock`
- Protocol: **Unix domain datagram (SOCK_DGRAM)** - connectionless, unordered, no reliability guarantees
- Shared between containers via `--ipc=host`
- No connection handshake; sender creates socket and calls `sendto()`, receiver binds once
- Buffer: receiver-side ring buffer (2000 messages) absorbs rate mismatches

## Data Format

```c++
struct ImuData {
    uint64_t timestamp;  // nanoseconds (ROS time)
    float accel[3];      // m/s² (FLU frame)
    float gyro[3];       // rad/s (FLU frame)
};
```

## Why DGRAM?

- **Simplicity**: no connection lifecycle, no reconnect logic
- **Low latency**: sender never blocks on connection state
- **Receiver buffering**: ring buffer decouples sender/receiver rates, handles bursts
- **Loss tolerance**: IMU stream is continuous; occasional dropped datagram acceptable for LI-Init (temporal alignment handles gaps)

**Tradeoff**: no guaranteed delivery or ordering - acceptable for high-rate IMU where occasional packet loss doesn't break initialization.
