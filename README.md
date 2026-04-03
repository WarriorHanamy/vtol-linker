# vtol-linker

`vtol-linker` contains the real-world backend integration utilities used by the
VTOL stack during hardware deployment.

Each sub-module connects a physical device or runtime backend into the ROS 2
namespace so that upper-layer logic can consume sensor and flight data without
depending on simulator-specific providers.

Within the `vtol_deployment` architecture, `linker` is the layer that replaces
the simulation backend when moving from simulation-first development to
real-world operation. It complements `vtol_interface`, rather than replacing
the upper-layer application logic defined there.

`vtol_deployment` remains the integration layer that defines how the two pieces
fit together:

- `vtol_interface/`: upper-layer application logic, including the
  simulation-first state machine, neural inference, and PX4-facing application
  behavior.
- `linker/`: backend integration utilities that connect sensors, odometry, and
  PX4 runtime interfaces in the real world.

In practice, the system is developed simulation-first with `vtol_interface`
running on top of a simulation backend, then deployed to hardware by replacing
that backend with the real-world providers implemented here.

This repository is intended to be consumed as the `vtol_deployment/linker`
submodule inside the top-level deployment workspace.

## Sub-modules

### lidar_connector

Bridges the hardware LiDAR sensor into the ROS2 space.

- Publishes raw point cloud topics via `livox_ros_driver2`.
- As an exception, also provides **LIO** (Lidar-Inertial Odometry) functionality
  through `FAST_LIO_ROS2`, producing `/Odometry` output.

### px4_connector

Bridges the FMU (flight management unit) hardware into the ROS2 space.

- Runs `Micro-XRCE-DDS-Agent` for PX4 DDS communication.
- Subscribes to `/Odometry` and publishes
  `/fmu/in/vehicle_visual_odometry` (with ENU/FLU to NED/FRD transform).

### calibration

Auxiliary utilities for sensor calibration.

- LiDAR-IMU extrinsic calibration using `LiDAR_IMU_Init`.
- Packaged as a one-shot Docker container: play a rosbag, get calibration
  results.
