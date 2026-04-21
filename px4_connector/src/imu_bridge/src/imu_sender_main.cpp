#include <memory>

#include <rclcpp/rclcpp.hpp>

#include "imu_bridge/imu_sender_component.hpp"

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto options = rclcpp::NodeOptions().use_intra_process_comms(true);
  rclcpp::spin(std::make_shared<imu_bridge::ImuSenderComponent>(options));
  rclcpp::shutdown();
  return 0;
}
