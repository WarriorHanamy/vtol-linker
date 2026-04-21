# =============================================================
# LIO image for Jetson deployment (single-stage native build)
# =============================================================

ARG BASE_IMAGE=vtol/l4t-ros2-base-jetson:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-c"]

ENV ROS_DISTRO=humble
ENV WS_DIR=/home/ros/ros2_ws
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libeigen3-dev \
    libpcl-dev \
    libssl-dev \
    ros-humble-eigen3-cmake-module \
    ros-humble-pcl-conversions \
    ros-humble-pcl-ros \
    ros-humble-tf2 \
    ros-humble-tf2-eigen \
    ros-humble-tf2-geometry-msgs \
    ros-humble-tf2-ros \
    ros-humble-tf2-sensor-msgs

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

WORKDIR /opt/livox-src/Livox-SDK2
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --parallel 4 && \
    cmake --install build && \
    ldconfig

WORKDIR ${WS_DIR}
RUN arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" && \
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    colcon build \
    --packages-select livox_ros_driver2 fast_lio \
    --cmake-args \
    -DOPENSSL_ROOT_DIR=/usr \
    -DOPENSSL_SSL_LIBRARY=/usr/lib/${arch}/libssl.so \
    -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/${arch}/libcrypto.so \
    --parallel-workers 4

COPY dockerfiles/assets/ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
