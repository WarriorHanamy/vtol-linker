# Agent Instructions: Docker Test Commands

## Overview

The `docker-test-*` Makefile targets are used to run Docker containers **on the Jetson device** after the images have been built. These commands assume:

- You are physically on or SSH'd into the Jetson device
- The Docker images have already been built (via `docker-build-*-jetson` targets)
- Docker daemon is running on the Jetson

## Available Test Commands

### `make docker-test-lio-jetson`

Runs the Fast-LIO odometry container.

- **Image**: `vtol/lio-jetson:latest`
- **Use case**: Real-time LiDAR-inertial odometry
- **Network**: Host network mode (shares host network stack)
- **IPC**: Host IPC mode (shares host IPC namespace)

```bash
make docker-test-lio-jetson
```

### `make docker-test-calib-jetson BAG=<path>`

Runs the LiDAR-IMU calibration container with a specific bag file.

- **Image**: `vtol/calib-lidar-imu-init-jetson:latest`
- **Required parameter**: `BAG` — path to calibration bag file (relative to `data/` directory)
- **Optional parameters**:
  - `LAUNCH` — launch file override (default: `calib_with_imu.launch`)
  - `PLAY_RATE` — playback rate multiplier
- **Volumes**: Mounts `$(CURDIR)/data` to `/data` in container (read-write)
- **Network**: Host network mode
- **IPC**: Host IPC mode

```bash
# Example usage
make docker-test-calib-jetson BAG=calibration.bag
make docker-test-calib-jetson BAG=my_data.bag LAUNCH=custom.launch PLAY_RATE=1.0
```

### `make docker-test-px4-connector-jetson`

Runs the PX4 connector container that bridges PX4 IMU data to ROS2.

- **Image**: `vtol/px4-connector-jetson:latest`
- **Use case**: Extract IMU data from PX4 flight controller and publish as ROS2 topics
- **Privileged**: Runs with `--privileged` flag (required for serial device access)
- **Network**: Host network mode
- **IPC**: Host IPC mode

```bash
make docker-test-px4-connector-jetson
```

### `make docker-test-px4-connector-jetson-shell`

Opens a bash shell inside the PX4 connector container (for debugging).

- **Image**: `vtol/px4-connector-jetson:latest`
- **Entrypoint**: Overridden to `bash`
- **Interactive**: `-it` flags enabled
- **Privileged**: Runs with `--privileged` flag
- **Network**: Host network mode
- **IPC**: Host IPC mode

```bash
make docker-test-px4-connector-jetson-shell
```

## Important Notes

1. **Device assumption**: These commands are designed to run **on the Jetson device** (not from the host development machine). The `docker-build-*-jetson` targets build images remotely on the Jetson via SSH; once built, you can test them directly on the device.

2. **Image availability**: Ensure images are built and available locally:
   ```bash
   docker images | grep vtol
   ```

3. **Container lifecycle**: All containers use `--rm` flag — they are automatically removed when they exit.

4. **Host networking**: `--net=host` is required for ROS2 discovery and low-latency communication with hardware (LiDAR, serial devices).

5. **Data directory**: The calibration test mounts `./data` from the host. Ensure the bag file exists:
   ```bash
   ls -la data/
   ```

6. **Serial device access**: PX4 connector requires `--privileged` to access `/dev/ttyTHS*` or `/dev/ttyACM*` serial ports connected to the flight controller.

## Troubleshooting

- **Image not found**: Build the image first using `make docker-build-*-jetson`
- **Permission denied on serial devices**: Ensure user `nv` is in `dialout` group: `sudo usermod -aG dialout nv`
- **Network issues**: Verify host network is accessible and ROS_DOMAIN is set correctly (default domain: 30)
