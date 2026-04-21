cmake_minimum_required(VERSION 3.8)
project(px4_odometry_bridge)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(px4_msgs REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_components REQUIRED)

add_library(px4_visual_odometry_bridge_component SHARED
  src/px4_visual_odometry_bridge.cpp
)
target_include_directories(px4_visual_odometry_bridge_component PUBLIC include)
target_link_libraries(px4_visual_odometry_bridge_component Eigen3::Eigen)
ament_target_dependencies(
  px4_visual_odometry_bridge_component
  rclcpp
  rclcpp_components
  nav_msgs
  px4_msgs
)
rclcpp_components_register_nodes(
  px4_visual_odometry_bridge_component
  "px4_odometry_bridge::Px4VisualOdometryBridgeComponent"
)

add_executable(px4_visual_odometry_bridge src/px4_visual_odometry_bridge_main.cpp)
target_link_libraries(px4_visual_odometry_bridge px4_visual_odometry_bridge_component)
ament_target_dependencies(px4_visual_odometry_bridge rclcpp)

install(TARGETS
  px4_visual_odometry_bridge_component
  EXPORT export_${PROJECT_NAME}
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)

install(TARGETS
  px4_visual_odometry_bridge
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY include/
  DESTINATION include
)

install(DIRECTORY launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
