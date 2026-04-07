# =============================================================
# PX4 Connector (Micro-XRCE-DDS-Agent + px4_odometry_bridge)
#
# Base image: ros:humble-ros-core-jammy
#   - Ubuntu 22.04 (Jammy), ROS2 Humble (minimal, no GUI tools)
#   - Multi-arch: amd64, arm64
#   - Compatible with Jetson JetPack 5 (L4T R35.x, Ubuntu 20.04 host)
#     and JetPack 6 (L4T R36.x, Ubuntu 22.04 host)
#   - CUDA not required; runs as a standalone bridge node
#
# Workspaces:
#   /root/px4_connector_ws — px4_msgs + px4_odometry_bridge (built in container)
#
# Components:
#   - Micro-XRCE-DDS-Agent (C++): UDP bridge to PX4 uXRCE-DDS middleware
#   - px4_odometry_bridge (ROS2 node): converts PX4 odometry to standard nav_msgs
#   - px4_msgs (overlay): minimal message definitions for PX4-ROS2 communication
# =============================================================

# =============================================================
# PX4 Connector (Micro-XRCE-DDS-Agent + px4_odometry_bridge)
#
# Base image: ros:humble-ros-core-jammy
#   - Ubuntu 22.04 (Jammy), ROS2 Humble (minimal, no GUI tools)
#   - Multi-arch: amd64, arm64
#   - Compatible with Jetson JetPack 5 (L4T R35.x, Ubuntu 20.04 host)
#     and JetPack 6 (L4T R36.x, Ubuntu 22.04 host)
#   - CUDA not required; runs as a standalone bridge node
#
# Workspaces:
#   /root/px4_connector_ws — px4_msgs + px4_odometry_bridge (built in container)
#
# Components:
#   - Micro-XRCE-DDS-Agent (C++): UDP bridge to PX4 uXRCE-DDS middleware
#   - px4_odometry_bridge (ROS2 node): converts PX4 odometry to standard nav_msgs
#   - px4_msgs (overlay): minimal message definitions for PX4-ROS2 communication
# =============================================================

FROM ros:humble-ros-core-jammy

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
RUN cd Micro-XRCE-DDS-Agent && \
    mkdir build && cd build && \
    cmake .. && \
    make -j2 && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/agent

WORKDIR ${WS_DIR}/src

# Todo, the multiple places dependencies on px4_msgs.
COPY px4_connector/px4_msgs ./px4_msgs
COPY px4_connector/px4_msgs_overlay/CMakeLists.txt ./px4_msgs/CMakeLists.txt
COPY px4_connector/px4_msgs_overlay/package.xml ./px4_msgs/package.xml
COPY px4_connector/src/px4_odometry_bridge ./px4_odometry_bridge

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

RUN rm -rf ${WS_DIR}/build ${WS_DIR}/install ${WS_DIR}/log && \
    source /opt/ros/humble/setup.bash && \
    colcon build \
    --packages-select px4_msgs px4_odometry_bridge \
    --parallel-workers 1

COPY dockerfiles/px4_connector_entrypoint.sh /px4_connector_entrypoint.sh
RUN chmod +x /px4_connector_entrypoint.sh

ENTRYPOINT ["/px4_connector_entrypoint.sh"]
CMD ["ros2", "launch", "px4_odometry_bridge", "bridge.launch.py"]
