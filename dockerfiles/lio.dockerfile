# ============================================================
# stage 1: Livox-SDK2 (独立编译，隔离 QEMU 压力)
# ============================================================
FROM ros:humble-ros-base AS sdk-builder

ARG UBUNTU_PORTS_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git

COPY lidar_connector/Livox-SDK2 /tmp/Livox-SDK2
RUN cd /tmp/Livox-SDK2 && \
    mkdir -p build && cd build && \
    cmake .. && make -j1 && make install && \
    ldconfig && rm -rf /tmp/Livox-SDK2

# ============================================================
# stage 2: colcon build (livox_ros_driver2 + fast_lio)
# ============================================================
FROM ros:humble-ros-base AS ros-builder

ARG UBUNTU_PORTS_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV WS_DIR=/root/ros2_ws

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3-rosdep python3-pip libeigen3-dev libpcl-dev

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-pcl-ros ros-humble-pcl-conversions \
    ros-humble-tf2 ros-humble-tf2-ros ros-humble-tf2-sensor-msgs \
    ros-humble-tf2-geometry-msgs ros-humble-tf2-eigen \
    ros-humble-eigen3-cmake-module

RUN rosdep init || echo "rosdep already initialized" && \
    rosdep update || rosdep update || true

COPY --from=sdk-builder /usr/local/lib /usr/local/lib
COPY --from=sdk-builder /usr/local/include /usr/local/include

WORKDIR ${WS_DIR}/src
COPY lidar_connector/livox_ros_driver2 ./livox_ros_driver2
COPY lidar_connector/FAST_LIO_ROS2 ./FAST_LIO_ROS2

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

RUN source /opt/ros/humble/setup.bash && \
    colcon build \
    --packages-select livox_ros_driver2 fast_lio \
    --cmake-args -DHUMBLE_ROS=ON \
    --parallel-workers 1

# ============================================================
# stage 3: runtime (最小运行时镜像)
# ============================================================
FROM ros:humble-ros-base

ARG UBUNTU_PORTS_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
ENV WS_DIR=/root/ros2_ws
ENV LD_LIBRARY_PATH=/usr/local/lib

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libflann1.9 libpcl1.12

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-pcl-ros ros-humble-pcl-conversions \
    ros-humble-tf2 ros-humble-tf2-ros ros-humble-tf2-sensor-msgs \
    ros-humble-tf2-geometry-msgs ros-humble-tf2-eigen

COPY --from=sdk-builder /usr/local/lib/liblivox_lidar_sdk_shared.so /usr/local/lib/
COPY --from=ros-builder ${WS_DIR}/install ${WS_DIR}/install
COPY --from=ros-builder ${WS_DIR}/src/livox_ros_driver2 ${WS_DIR}/src/livox_ros_driver2
COPY --from=ros-builder ${WS_DIR}/src/FAST_LIO_ROS2 ${WS_DIR}/src/FAST_LIO_ROS2

COPY dockerfiles/ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["ros2", "launch", "fast_lio", "mapping.launch.py", "config_file:=mid360.yaml", "rviz:=false"]
