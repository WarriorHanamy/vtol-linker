# =============================================================
# LIO (FastLIO + Upstream Livox ROS Driver2) — Multi-stage Dockerfile
#
# Base image: ros:humble-ros-base
#   - Ubuntu 22.04 (Jammy), ROS2 Humble
#   - Multi-arch: amd64, arm64
#   - Compatible with Jetson JetPack 5 (L4T R35.x, Ubuntu 20.04 host)
#     and JetPack 6 (L4T R36.x, Ubuntu 22.04 host)
#   - CUDA not required in this image; CUDA/ROS bridge is separate
#
# Workspaces:
#   /root/ros2_ws — upstream livox_ros_driver2 (from GitHub) + local fast_lio
#
# Stages:
#   1. sdk-builder  — Livox-SDK2 (isolated compile)
#   2. ros-builder  — colcon build of upstream livox_ros_driver2 + fast_lio
#   3. runtime      — minimal image with pre-built packages
#
# Build args:
#   LIVOX_ROS_DRIVER2_REPO — git URL for livox_ros_driver2 (default: upstream)
#   LIVOX_ROS_DRIVER2_REF  — git branch/tag (default: master)
# =============================================================

# =============================================================
# LIO (FastLIO + Upstream Livox ROS Driver2) — Multi-stage Dockerfile
#
# Base image: ros:humble-ros-base
#   - Ubuntu 22.04 (Jammy), ROS2 Humble
#   - Multi-arch: amd64, arm64
#   - Compatible with Jetson JetPack 5 (L4T R35.x, Ubuntu 20.04 host)
#     and JetPack 6 (L4T R36.x, Ubuntu 22.04 host)
#   - CUDA not required in this image; CUDA/ROS bridge is separate
#
# Workspaces:
#   /root/ros2_ws — upstream livox_ros_driver2 (from GitHub) + local fast_lio
#
# Stages:
#   1. sdk-builder  — Livox-SDK2 (isolated compile)
#   2. ros-builder  — colcon build of upstream livox_ros_driver2 + fast_lio
#   3. runtime      — minimal image with pre-built packages
#
# Build args:
#   LIVOX_ROS_DRIVER2_REPO — git URL for livox_ros_driver2 (default: upstream)
#   LIVOX_ROS_DRIVER2_REF  — git branch/tag (default: master)
# =============================================================

# ============================================================
# stage 1: Livox-SDK2 (independent build)
# ============================================================
FROM ros:humble-ros-base AS sdk-builder

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu

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
# stage 2: colcon build (upstream livox_ros_driver2 + local fast_lio)
# ============================================================
FROM ros:humble-ros-base AS ros-builder

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu
ARG LIVOX_ROS_DRIVER2_REPO=https://github.com/Livox-SDK/livox_ros_driver2.git
ARG LIVOX_ROS_DRIVER2_REF=master

ENV DEBIAN_FRONTEND=noninteractive
ENV WS_DIR=/root/ros2_ws

RUN sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${UBUNTU_PORTS_MIRROR}|g" /etc/apt/sources.list && \
    sed -i "s|http://packages.ros.org/ros2/ubuntu|${ROS_MIRROR}|g" /etc/apt/sources.list.d/ros2.sources && \
    sed -i "s|Types: deb deb-src|Types: deb|g" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3-rosdep python3-pip libeigen3-dev libpcl-dev libssl-dev git

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
RUN git clone --depth 1 --branch ${LIVOX_ROS_DRIVER2_REF} ${LIVOX_ROS_DRIVER2_REPO} livox_ros_driver2 && \
    cd livox_ros_driver2 && \
    if [ -f package_ROS2.xml ]; then mv package_ROS2.xml package.xml; fi && \
    if grep -q 'LIVOX_INTERFACES_INCLUDE_DIRECTORIES' CMakeLists.txt; then \
      sed -i '/LIVOX_INTERFACES_INCLUDE_DIRECTORIES/d' CMakeLists.txt; \
    fi && \
    python3 - <<'PY'
from pathlib import Path

path = Path('CMakeLists.txt')
text = path.read_text()

# Locate ROS2 branch; upstream uses else(ROS_EDITION ...), local uses else()
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

COPY lidar_connector/FAST_LIO_ROS2 ./FAST_LIO_ROS2

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

RUN arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" && \
    source /opt/ros/humble/setup.bash && \
    colcon build \
    --packages-select livox_ros_driver2 fast_lio \
    --cmake-args \
    -DHUMBLE_ROS=ON \
    -DOPENSSL_ROOT_DIR=/usr \
    -DOPENSSL_SSL_LIBRARY=/usr/lib/${arch}/libssl.so \
    -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/${arch}/libcrypto.so \
    --parallel-workers 1

# ============================================================
# stage 3: runtime
# ============================================================
FROM ros:humble-ros-base

ARG UBUNTU_PORTS_MIRROR=http://mirrors.ustc.edu.cn/ubuntu-ports
ARG ROS_MIRROR=https://mirrors.ustc.edu.cn/ros2/ubuntu

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
    libflann1.9

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-pcl-ros ros-humble-pcl-conversions

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
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
