cmake_minimum_required(VERSION 3.0.2)
project(imu_bridge_ros1)

find_package(catkin REQUIRED COMPONENTS
  roscpp
  sensor_msgs
)

catkin_package()

include_directories(
  ${catkin_INCLUDE_DIRS}
)

add_executable(imu_receiver_node src/imu_receiver.cpp)
target_link_libraries(imu_receiver_node ${catkin_LIBRARIES})

install(TARGETS imu_receiver_node
  RUNTIME DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
