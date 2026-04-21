#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include <px4_msgs/msg/highres_imu.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/imu.hpp>

namespace px4_connector
{

class ImuTopicSenderComponent : public rclcpp::Node
{
public:
  explicit ImuTopicSenderComponent(const rclcpp::NodeOptions & options);

private:
  void imu_callback(px4_msgs::msg::HighresImu::UniquePtr msg);
  sensor_msgs::msg::Imu::UniquePtr build_imu(const px4_msgs::msg::HighresImu & src) const;
  int64_t resolve_timestamp_ns(const px4_msgs::msg::HighresImu & src) const;

  std::string input_topic_;
  std::string output_topic_;
  size_t input_qos_depth_;
  size_t output_qos_depth_;
  rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr subscription_;
  rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr publisher_;
};

}  // namespace px4_connector
