# =============================================================
# LIO prep image (FastLIO + local Livox ROS Driver2)
#
# This Dockerfile intentionally stops before any native compilation.
# It is safe to build on the host with buildx and then hand off to
# a Jetson-native Docker build for Livox-SDK2 and colcon.
# =============================================================

FROM ros:humble-ros-base AS prep

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
ENV WS_DIR=/root/ros2_ws

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git \
    python3-rosdep python3-pip \
    libeigen3-dev libpcl-dev libssl-dev

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-pcl-ros ros-humble-pcl-conversions \
    ros-humble-tf2 ros-humble-tf2-ros ros-humble-tf2-sensor-msgs \
    ros-humble-tf2-geometry-msgs ros-humble-tf2-eigen \
    ros-humble-eigen3-cmake-module

RUN rosdep init || echo "rosdep already initialized" && \
    rosdep update || rosdep update || true

WORKDIR /opt/livox-src
COPY lidar_connector/Livox-SDK2 ./Livox-SDK2

WORKDIR ${WS_DIR}/src
COPY lidar_connector/livox_ros_driver2 ./livox_ros_driver2
COPY lidar_connector/FAST_LIO_ROS2 ./FAST_LIO_ROS2

RUN python3 - <<'PY'
from pathlib import Path

path = Path('livox_ros_driver2/CMakeLists.txt')
text = path.read_text()

ros2_pos = 0
for marker in ('else(ROS_EDITION STREQUAL "ROS2")', 'else()'):
    pos = text.find(marker)
    if pos != -1:
        ros2_pos = text.index('\n', pos) + 1
        break

before = text[:ros2_pos]
ros2 = text[ros2_pos:]

if 'find_package(Eigen3 REQUIRED)' not in ros2:
    ros2 = ros2.replace(
        '  find_package(PCL REQUIRED)\n',
        '  find_package(PCL REQUIRED)\n  find_package(Eigen3 REQUIRED)\n',
        1,
    )

if '${EIGEN3_INCLUDE_DIRS}' not in ros2:
    ros2 = ros2.replace(
        '    ${PCL_INCLUDE_DIRS}\n',
        '    ${PCL_INCLUDE_DIRS}\n    ${EIGEN3_INCLUDE_DIRS}\n',
        1,
    )

if 'Eigen3::Eigen' not in ros2:
    ros2 = ros2.replace(
        '    ${PCL_LIBRARIES}\n',
        '    ${PCL_LIBRARIES}\n    Eigen3::Eigen\n',
        1,
    )

path.write_text(before + ros2)
PY

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]
