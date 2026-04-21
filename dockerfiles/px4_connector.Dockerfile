# =============================================================
# PX4 connector image for Jetson deployment (single-stage native build)
# =============================================================

ARG BASE_IMAGE=vtol/l4t-ros2-base-jetson:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-c"]

ENV ROS_DISTRO=humble
ENV WS_DIR=/home/ros/ros2_ws

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  apt-get update && apt-get install -y --no-install-recommends \
  libeigen3-dev \
  ros-humble-eigen3-cmake-module \
  ros-humble-nav-msgs \
  ros-humble-sensor-msgs

WORKDIR /tmp/agent
COPY px4_connector/Micro-XRCE-DDS-Agent ./Micro-XRCE-DDS-Agent

RUN cmake -S Micro-XRCE-DDS-Agent -B Micro-XRCE-DDS-Agent/build \
  -DBUILD_SHARED_LIBS=OFF \
  -DUAGENT_BUILD_USAGE_EXAMPLES=OFF && \
  cmake --build Micro-XRCE-DDS-Agent/build --parallel 4 && \
  cmake --install Micro-XRCE-DDS-Agent/build && \
  ldconfig

WORKDIR ${WS_DIR}/src
COPY px4_connector/px4_msgs ./px4_msgs
COPY px4_connector/px4_msgs_overlay/CMakeLists.txt ./px4_msgs/CMakeLists.txt
COPY px4_connector/px4_msgs_overlay/package.xml ./px4_msgs/package.xml
COPY px4_connector/src ./px4_connector

WORKDIR ${WS_DIR}
RUN source /opt/ros/${ROS_DISTRO}/setup.bash && \
  colcon build \
  --packages-select px4_msgs \
  --parallel-workers 4

RUN source /opt/ros/${ROS_DISTRO}/setup.bash && \
  colcon build \
  --packages-select px4_connector \
  --parallel-workers 4

COPY dockerfiles/assets/px4_connector_entrypoint.sh /px4_connector_entrypoint.sh
RUN chmod +x /px4_connector_entrypoint.sh

ENTRYPOINT ["/px4_connector_entrypoint.sh"]
CMD ["ros2", "launch", "px4_connector", "px4_connector.launch.py"]
