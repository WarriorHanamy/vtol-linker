cmake_minimum_required(VERSION 3.8)
project(imu_bridge)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_components REQUIRED)
find_package(px4_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)

add_library(imu_sender_component SHARED
  src/imu_sender.cpp
)
target_include_directories(imu_sender_component PUBLIC include)
ament_target_dependencies(imu_sender_component rclcpp rclcpp_components px4_msgs sensor_msgs)
rclcpp_components_register_nodes(imu_sender_component "imu_bridge::ImuSenderComponent")

add_executable(imu_sender_node src/imu_sender_main.cpp)
target_link_libraries(imu_sender_node imu_sender_component)
ament_target_dependencies(imu_sender_node rclcpp)

install(TARGETS
  imu_sender_component
  EXPORT export_${PROJECT_NAME}
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)

install(TARGETS
  imu_sender_node
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY include/
  DESTINATION include
)

install(DIRECTORY launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
