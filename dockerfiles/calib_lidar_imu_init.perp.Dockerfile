# =============================================================
# LiDAR-IMU calibration prep image
#
# This stage only installs dependencies and prepares sources.
# Native compilation happens on Jetson in calib_lidar_imu_init.native.Dockerfile.
# =============================================================

ARG BASE_IMAGE=ros:noetic-ros-base
ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG CERES_VERSION=2.0.0
ARG LIVOX_DRIVER_VERSION=2.6.0
ARG CERES_CXX_FLAGS=-O0 -g0 -fno-inline

FROM ${BASE_IMAGE} AS prep

ARG UBUNTU_PORTS_MIRROR
ARG CERES_VERSION
ARG LIVOX_DRIVER_VERSION
ARG CERES_CXX_FLAGS

ENV DEBIAN_FRONTEND=noninteractive
ENV WS_DIR=/root/catkin_ws
ENV CERES_VERSION=${CERES_VERSION}
ENV CERES_CXX_FLAGS=${CERES_CXX_FLAGS}
ENV LIVOX_DRIVER_VERSION=${LIVOX_DRIVER_VERSION}

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    python3-dev \
    python3-pip \
    libeigen3-dev \
    libgoogle-glog-dev \
    libgflags-dev

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get install -y --no-install-recommends --fix-missing \
    ros-noetic-tf \
    ros-noetic-eigen-conversions

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get install -y --no-install-recommends --fix-missing \
    ros-noetic-pcl-ros \
    ros-noetic-pcl-conversions \
    libpcl-dev \
    ros-noetic-ddynamic-reconfigure

RUN pip3 install --no-cache-dir matplotlib

WORKDIR /opt/calib-src
RUN wget -q "https://github.com/ceres-solver/ceres-solver/archive/refs/tags/${CERES_VERSION}.tar.gz" && \
    tar zxf "${CERES_VERSION}.tar.gz" && \
    rm -f "${CERES_VERSION}.tar.gz"

WORKDIR ${WS_DIR}/src
COPY LiDAR_IMU_Init ./LiDAR_IMU_Init
COPY imu_bridge_ros1 ./imu_bridge_ros1

RUN cd /opt/calib-src && \
    wget -q "https://github.com/Livox-SDK/livox_ros_driver/archive/refs/tags/v${LIVOX_DRIVER_VERSION}.tar.gz" && \
    tar zxf "v${LIVOX_DRIVER_VERSION}.tar.gz" && \
    mv "livox_ros_driver-${LIVOX_DRIVER_VERSION}" "${WS_DIR}/src/livox_ros_driver" && \
    rm -f "v${LIVOX_DRIVER_VERSION}.tar.gz"

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]
