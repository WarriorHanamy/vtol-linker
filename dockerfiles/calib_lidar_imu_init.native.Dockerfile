# =============================================================
# LiDAR-IMU calibration native image
# =============================================================

ARG PREP_IMAGE
FROM ${PREP_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV WS_DIR=/root/catkin_ws
ENV Ceres_DIR=/opt/ceres/lib/cmake/Ceres
ENV CMAKE_PREFIX_PATH=/opt/ceres
ENV LD_LIBRARY_PATH=/opt/ceres/lib

WORKDIR /opt/calib-src
RUN mkdir -p "ceres-solver-${CERES_VERSION}/build" && \
    cd "ceres-solver-${CERES_VERSION}/build" && \
    cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/ceres \
    -DCMAKE_CXX_FLAGS="${CERES_CXX_FLAGS}" \
    -DCMAKE_CXX_FLAGS_RELEASE="${CERES_CXX_FLAGS}" \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_BENCHMARKS=OFF \
    -DBUILD_DOCUMENTATION=OFF \
    -DSCHUR_SPECIALIZATIONS=OFF \
    -DSUITESPARSE=OFF \
    -DCXSPARSE=OFF \
    -DLAPACK=OFF \
    -DEIGENSPARSE=ON \
    -DCUSTOM_BLAS=ON \
    -DMINIGLOG=OFF \
    -DGFLAGS=ON \
    -DCERES_THREADING_MODEL=NO_THREADS \
    .. && \
    make -j4 && \
    make install

WORKDIR ${WS_DIR}
SHELL ["/bin/bash", "-c"]

# Apply patches from assets
COPY dockerfiles/assets/LiDAR_IMU_Init_CMakeLists.txt ${WS_DIR}/src/LiDAR_IMU_Init/CMakeLists.txt
COPY dockerfiles/assets/livox_ros_driver2_package.xml ${WS_DIR}/src/livox_ros_driver2/package.xml
COPY dockerfiles/assets/patch_livox_ros_driver2_ros1_aarch64.py /tmp/patch_livox_ros_driver2_ros1_aarch64.py

RUN python3 /tmp/patch_livox_ros_driver2_ros1_aarch64.py && \
    source /opt/ros/noetic/setup.bash && catkin_make -j4

RUN mkdir -p /data ${WS_DIR}/src/LiDAR_IMU_Init/result

COPY dockerfiles/assets/calib_entrypoint.sh /calib_entrypoint.sh
RUN chmod +x /calib_entrypoint.sh

COPY dockerfiles/assets/calib_run.sh /usr/local/bin/calib_run.sh
RUN chmod +x /usr/local/bin/calib_run.sh

COPY dockerfiles/assets/livox_mid360_integrated.launch /dockerfiles/livox_mid360_integrated.launch
COPY dockerfiles/assets/livox_mid360_integrated.launch ${WS_DIR}/src/LiDAR_IMU_Init/launch/livox_mid360_integrated.launch
COPY dockerfiles/assets/calib_with_imu.launch /dockerfiles/calib_with_imu.launch
COPY dockerfiles/assets/calib_with_imu.launch ${WS_DIR}/src/LiDAR_IMU_Init/launch/calib_with_imu.launch

ENTRYPOINT ["/calib_entrypoint.sh"]
CMD ["bash"]
