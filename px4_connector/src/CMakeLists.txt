cmake_minimum_required(VERSION 3.8)
project(px4_connector)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(px4_msgs REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_components REQUIRED)
find_package(sensor_msgs REQUIRED)

add_library(imu_topic_sender_component SHARED
  src/imu_topic_sender.cpp
)
target_include_directories(imu_topic_sender_component PUBLIC include)
ament_target_dependencies(imu_topic_sender_component
  rclcpp
  rclcpp_components
  px4_msgs
  sensor_msgs
)
rclcpp_components_register_nodes(imu_topic_sender_component "px4_connector::ImuTopicSenderComponent")

add_library(imu_socket_sender_component SHARED
  src/imu_socket_sender.cpp
)
target_include_directories(imu_socket_sender_component PUBLIC include)
ament_target_dependencies(imu_socket_sender_component
  rclcpp
  rclcpp_components
  px4_msgs
)
rclcpp_components_register_nodes(imu_socket_sender_component "px4_connector::ImuSocketSenderComponent")

add_library(px4_visual_odometry_bridge_component SHARED
  src/px4_visual_odometry_bridge.cpp
)
target_include_directories(px4_visual_odometry_bridge_component PUBLIC include)
target_link_libraries(px4_visual_odometry_bridge_component Eigen3::Eigen)
ament_target_dependencies(px4_visual_odometry_bridge_component
  rclcpp
  rclcpp_components
  nav_msgs
  px4_msgs
)
rclcpp_components_register_nodes(px4_visual_odometry_bridge_component "px4_connector::Px4VisualOdometryBridgeComponent")

install(TARGETS
  imu_topic_sender_component
  imu_socket_sender_component
  px4_visual_odometry_bridge_component
  EXPORT export_${PROJECT_NAME}
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)

install(DIRECTORY include/
  DESTINATION include
)

install(DIRECTORY launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
