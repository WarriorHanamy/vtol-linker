# =============================================================
# Linker ROS2 base image for Jetson native builds
#
# This image provides the shared R35.x L4T (Ubuntu Focal) + ROS2 Humble
# environment used by the native LIO and PX4 connector images.
#
# For R35.x (JetPack 5.x / Ubuntu Focal), ROS2 Humble packages are
# provided by NVIDIA's pre-configured L4T apt sources — no public
# ROS2 repo needed.
# =============================================================

ARG BASE_IMAGE=nvcr.io/nvidia/l4t-jetpack
ARG JETPACK_TAG=r35.4.1
FROM ${BASE_IMAGE}:${JETPACK_TAG}
SHELL ["/bin/bash", "-c"]

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ENV WS_DIR=/home/ros/ros2_ws
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg2 \
  locales \
  lsb-release \
  software-properties-common && \
  locale-gen en_US en_US.UTF-8 && \
  update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Use mirror for faster apt operations
RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
  sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list || true

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  git \
  python3-colcon-common-extensions \
  python3-pip \
  python3-rosdep \
  ros-humble-rmw-fastrtps-cpp \
  ros-humble-ros-base \
  sudo \
  wget

RUN rosdep init || echo "rosdep already initialized" && \
  rosdep update || rosdep update || true

RUN useradd -m -u 1000 ros || true && \
  grep -q '^ros ALL=(ALL) NOPASSWD:ALL$' /etc/sudoers || echo 'ros ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
  mkdir -p ${WS_DIR}/src && \
  chown -R ros:ros /home/ros

WORKDIR ${WS_DIR}
