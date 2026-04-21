#pragma once

#include <cstddef>
#include <cstdint>
#include <atomic>
#include <string>

#include <px4_msgs/msg/highres_imu.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sys/un.h>

namespace px4_connector
{

class ImuSocketSenderComponent : public rclcpp::Node
{
public:
  explicit ImuSocketSenderComponent(const rclcpp::NodeOptions & options);
  ~ImuSocketSenderComponent() override;

private:
  struct ImuData
  {
    uint64_t timestamp;
    float accel[3];
    float gyro[3];
  };

  void setup_socket();
  void imu_callback(px4_msgs::msg::HighresImu::UniquePtr msg);
  void send(const px4_msgs::msg::HighresImu & src);
  int64_t resolve_timestamp_ns(const px4_msgs::msg::HighresImu & src) const;

  std::string socket_path_;
  std::string input_topic_;
  size_t input_qos_depth_;
  int socket_fd_;
  sockaddr_un dest_addr_;
  rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr subscription_;
  std::atomic<uint64_t> dropped_messages_;
};

}  // namespace px4_connector
