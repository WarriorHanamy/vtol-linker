#include <memory>

#include <rclcpp/rclcpp.hpp>

#include "px4_odometry_bridge/px4_visual_odometry_bridge_component.hpp"

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto options = rclcpp::NodeOptions().use_intra_process_comms(true);
  rclcpp::spin(std::make_shared<px4_odometry_bridge::Px4VisualOdometryBridgeComponent>(options));
  rclcpp::shutdown();
  return 0;
}
