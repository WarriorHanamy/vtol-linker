# =============================================================
# PX4 Connector prep image
#
# This stage only installs dependencies and prepares sources.
# Native compilation happens on Jetson in px4_connector.native.Dockerfile.
# =============================================================

FROM ros:humble-ros-core-jammy AS prep

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
ENV WS_DIR=/root/px4_connector_ws

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    sudo \
    libeigen3-dev \
    python3-colcon-common-extensions \
    ros-humble-eigen3-cmake-module \
    ros-humble-nav-msgs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/agent
COPY px4_connector/Micro-XRCE-DDS-Agent ./Micro-XRCE-DDS-Agent

WORKDIR ${WS_DIR}/src
COPY px4_connector/px4_msgs ./px4_msgs
COPY px4_connector/px4_msgs_overlay/CMakeLists.txt ./px4_msgs/CMakeLists.txt
COPY px4_connector/px4_msgs_overlay/package.xml ./px4_msgs/package.xml
COPY px4_connector/src/px4_odometry_bridge ./px4_odometry_bridge

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]
