#pragma once

#include <cstddef>
#include <cstdint>
#include <atomic>
#include <string>

#include <px4_msgs/msg/highres_imu.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/imu.hpp>
#include <sys/un.h>

namespace imu_bridge
{

class ImuSenderComponent : public rclcpp::Node
{
public:
  explicit ImuSenderComponent(const rclcpp::NodeOptions & options);
  ~ImuSenderComponent() override;

private:
  struct ImuData
  {
    uint64_t timestamp;
    float accel[3];
    float gyro[3];
  };

  void validate_parameters();
  void setup_socket();
  void imu_callback(px4_msgs::msg::HighresImu::UniquePtr msg);
  sensor_msgs::msg::Imu::UniquePtr build_ros2_imu(const px4_msgs::msg::HighresImu & src) const;
  void publish_topic(const px4_msgs::msg::HighresImu & src);
  void send_via_socket(const px4_msgs::msg::HighresImu & src);
  int64_t resolve_timestamp_ns(const px4_msgs::msg::HighresImu & src) const;

  std::string socket_path_;
  std::string input_topic_;
  std::string output_mode_;
  std::string output_topic_;
  size_t input_qos_depth_;
  size_t output_qos_depth_;
  int socket_fd_;
  sockaddr_un dest_addr_;
  rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr imu_subscription_;
  rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr imu_publisher_;
  std::atomic<uint64_t> dropped_socket_messages_;
};

}  // namespace imu_bridge
