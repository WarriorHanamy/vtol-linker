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

RUN sed -i '/^target_link_libraries(li_init/i add_dependencies(li_init ${${PROJECT_NAME}_EXPORTED_TARGETS} ${catkin_EXPORTED_TARGETS})' \
    ${WS_DIR}/src/LiDAR_IMU_Init/CMakeLists.txt && \
    source /opt/ros/noetic/setup.bash && \
    catkin_make -j4

RUN mkdir -p /data ${WS_DIR}/src/LiDAR_IMU_Init/result

COPY dockerfiles/calib_entrypoint.sh /calib_entrypoint.sh
RUN chmod +x /calib_entrypoint.sh

COPY dockerfiles/calib_run.sh /usr/local/bin/calib_run.sh
RUN chmod +x /usr/local/bin/calib_run.sh

COPY dockerfiles/calib_with_imu.launch /dockerfiles/calib_with_imu.launch

ENTRYPOINT ["/calib_entrypoint.sh"]
CMD ["bash"]
