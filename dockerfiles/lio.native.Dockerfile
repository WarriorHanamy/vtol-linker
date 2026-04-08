# =============================================================
# LIO native image (FastLIO + local Livox ROS Driver2)
#
# This Dockerfile runs on a Jetson-native Docker daemon and resumes
# from a prep image built elsewhere.
# =============================================================

ARG PREP_IMAGE
FROM ${PREP_IMAGE} AS native-build

ENV ROS_DISTRO=humble
ENV WS_DIR=/root/ros2_ws

WORKDIR /opt/livox-src/Livox-SDK2
RUN mkdir -p build && cd build && \
    cmake .. && make -j4 && make install && \
    ldconfig

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

RUN arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" && \
    source /opt/ros/humble/setup.bash && \
    colcon build \
    --packages-select livox_ros_driver2 fast_lio \
    --cmake-args \
    -DOPENSSL_ROOT_DIR=/usr \
    -DOPENSSL_SSL_LIBRARY=/usr/lib/${arch}/libssl.so \
    -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/${arch}/libcrypto.so \
    --parallel-workers 4

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
    libflann1.9 \
    ros-humble-pcl-ros ros-humble-pcl-conversions \
    ros-humble-tf2 ros-humble-tf2-ros ros-humble-tf2-sensor-msgs \
    ros-humble-tf2-geometry-msgs ros-humble-tf2-eigen

COPY --from=native-build /usr/local/lib/liblivox_lidar_sdk_shared.so /usr/local/lib/
COPY --from=native-build ${WS_DIR}/install ${WS_DIR}/install
COPY --from=native-build ${WS_DIR}/src/livox_ros_driver2 ${WS_DIR}/src/livox_ros_driver2
COPY --from=native-build ${WS_DIR}/src/FAST_LIO_ROS2 ${WS_DIR}/src/FAST_LIO_ROS2

COPY dockerfiles/ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
