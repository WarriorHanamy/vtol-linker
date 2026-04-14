# =============================================================
# LiDAR-IMU calibration prep image
#
# This stage only installs dependencies and prepares sources.
# Native compilation happens on Jetson in calib_lidar_imu_init.native.Dockerfile.
# =============================================================

ARG BASE_IMAGE=ros:noetic-ros-base
ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG CERES_VERSION=2.0.0
ARG CERES_CXX_FLAGS=-O0 -g0 -fno-inline

FROM ${BASE_IMAGE} AS prep

 ARG UBUNTU_PORTS_MIRROR
 ARG CERES_VERSION
 ARG CERES_CXX_FLAGS

ENV DEBIAN_FRONTEND=noninteractive
ENV WS_DIR=/root/catkin_ws
ENV CERES_VERSION=${CERES_VERSION}
ENV CERES_CXX_FLAGS=${CERES_CXX_FLAGS}

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
    apt-get install -y --no-install-recommends \
    ros-noetic-pcl-ros \
    ros-noetic-pcl-conversions \
    libpcl-dev \
    ros-noetic-ddynamic-reconfigure

RUN pip3 install --no-cache-dir matplotlib

WORKDIR /opt/calib-src
COPY lidar_connector/Livox-SDK2 /opt/livox-src/Livox-SDK2
COPY dockerfiles/assets/livox_mid360_integrated.launch /dockerfiles/livox_mid360_integrated.launch
RUN wget -q "https://github.com/ceres-solver/ceres-solver/archive/refs/tags/${CERES_VERSION}.tar.gz" && \
    tar zxf "${CERES_VERSION}.tar.gz" && \
    rm -f "${CERES_VERSION}.tar.gz"

WORKDIR ${WS_DIR}/src
COPY LiDAR_IMU_Init ./LiDAR_IMU_Init
COPY LiDAR_IMU_Init/imu_bridge_ros1 ./imu_bridge_ros1
COPY lidar_connector/livox_ros_driver2 ./livox_ros_driver2
# Overwrite livox_ros_driver2 package.xml with fixed dependencies (add roscpp/rospy exec_depends)
COPY dockerfiles/assets/livox_ros_driver2_package.xml ${WS_DIR}/src/livox_ros_driver2/package.xml
COPY dockerfiles/assets/patch_livox_ros_driver2_ros1_aarch64.py /tmp/patch_livox_ros_driver2_ros1_aarch64.py

RUN python3 /tmp/patch_livox_ros_driver2_ros1_aarch64.py

# Patch LiDAR_IMU_Init to use livox_ros_driver2 instead of livox_ros_driver (v1)
RUN sed -i 's/livox_ros_driver/livox_ros_driver2/g' \
    ${WS_DIR}/src/LiDAR_IMU_Init/package.xml \
    ${WS_DIR}/src/LiDAR_IMU_Init/CMakeLists.txt \
    ${WS_DIR}/src/LiDAR_IMU_Init/src/preprocess.h \
    ${WS_DIR}/src/LiDAR_IMU_Init/src/preprocess.cpp \
    ${WS_DIR}/src/LiDAR_IMU_Init/src/laserMapping.cpp

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]
