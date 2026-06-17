# =============================================================
# Linker ROS2 base image for R35.x Jetson targets
#
# Uses R36.x L4T userland (Ubuntu Jammy) on the host R35.x kernel.
# This provides a working ROS2 Humble environment from the public
# repo without requiring NVIDIA-specific ROS2 packages.
#
# LIO and PX4 connector containers do not need CUDA, so the R36.x
# base image version mismatch is transparent.
# =============================================================

ARG BASE_IMAGE=nvcr.io/nvidia/l4t-jetpack
ARG JETPACK_TAG=r36.4.0
FROM ${BASE_IMAGE}:${JETPACK_TAG}
SHELL ["/bin/bash", "-c"]

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu

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

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | apt-key add - && \
  echo "deb http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2.list

# Override mirrors after repo setup
RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
  sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.list && \
  sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.list || true

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
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
