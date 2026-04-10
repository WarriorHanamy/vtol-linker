# =============================================================
# PX4 Connector native image
# =============================================================

ARG PREP_IMAGE
FROM ${PREP_IMAGE} AS native-build

ENV ROS_DISTRO=humble
ENV WS_DIR=/root/px4_connector_ws

WORKDIR /tmp/agent
RUN cd Micro-XRCE-DDS-Agent && \
    mkdir -p build && cd build && \
    cmake .. && \
    make -j4 && \
    make install && \
    ldconfig

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

RUN rm -rf ${WS_DIR}/build ${WS_DIR}/install ${WS_DIR}/log && \
    source /opt/ros/humble/setup.bash && \
    colcon build \
    --packages-select px4_msgs px4_odometry_bridge imu_bridge \
    --parallel-workers 4

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
    ros-humble-nav-msgs \
    && rm -rf /var/lib/apt/lists/*

COPY --from=native-build /usr/local /usr/local
COPY --from=native-build ${WS_DIR}/install ${WS_DIR}/install
RUN ldconfig
COPY dockerfiles/assets/px4_connector_entrypoint.sh /px4_connector_entrypoint.sh
RUN chmod +x /px4_connector_entrypoint.sh

ENTRYPOINT ["/px4_connector_entrypoint.sh"]
CMD ["ros2", "launch", "px4_odometry_bridge", "bridge.launch.py"]
