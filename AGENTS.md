# Agent Instructions: Docker Test Commands

## Overview

The `docker-test-*` Makefile targets are used to run Docker containers **on the Jetson device** after the images have been built. These commands assume:

- You are physically on or SSH'd into the Jetson device
- The Docker images have already been built (via `docker-build-*-jetson` targets)
- Docker daemon is running on the Jetson

## Operational Constraints

1. **Device assumption**: These commands run on the Jetson device (not from the host).
   The `docker-build-*-jetson` targets build images remotely on the Jetson via SSH;
   once built, you can test them directly on the device.

2. **Image availability**: Ensure images are built and available locally:
   ```bash
   docker images | grep vtol
   ```

3. **Container lifecycle**: All containers use `--rm` -- they are automatically removed on exit.

4. **Host networking**: `--net=host` is required for ROS2 discovery and low-latency
   communication with hardware (LiDAR, serial devices).

5. **Data directory**: Calibration tests mount `./data` from the host. Ensure the bag file exists.

6. **Serial device access**: PX4 connector requires `--privileged` to access `/dev/ttyTHS*`
   or `/dev/ttyACM*` serial ports connected to the flight controller.
