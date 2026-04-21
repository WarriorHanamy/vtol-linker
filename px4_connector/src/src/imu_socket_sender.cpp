#include "px4_connector/imu_socket_sender_component.hpp"

#include <cerrno>
#include <cstring>
#include <functional>
#include <memory>
#include <stdexcept>
#include <utility>

#include <rclcpp_components/register_node_macro.hpp>

#include <sys/socket.h>
#include <unistd.h>

namespace {

constexpr char kDefaultSocketPath[] = "/tmp/imu_bridge.sock";
constexpr char kDefaultInputTopic[] = "/fmu/out/highres_imu_flu";
constexpr size_t kDefaultDepth = 40;

}  // namespace

namespace px4_connector
{

ImuSocketSenderComponent::ImuSocketSenderComponent(const rclcpp::NodeOptions & options)
: Node("imu_socket_sender", options),
  input_qos_depth_(kDefaultDepth),
  socket_fd_(-1),
  dest_addr_{},
  dropped_messages_(0)
{
  socket_path_ = declare_parameter<std::string>("socket_path", kDefaultSocketPath);
  input_topic_ = declare_parameter<std::string>("input_topic", kDefaultInputTopic);
  input_qos_depth_ = declare_parameter<int>("input_qos_depth", static_cast<int>(kDefaultDepth));

  setup_socket();

  auto input_qos = rclcpp::SensorDataQoS();
  input_qos.keep_last(input_qos_depth_);
  subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
    input_topic_, input_qos,
    std::bind(&ImuSocketSenderComponent::imu_callback, this, std::placeholders::_1));

  RCLCPP_INFO(get_logger(), "%s -> %s", input_topic_.c_str(), socket_path_.c_str());
}

ImuSocketSenderComponent::~ImuSocketSenderComponent()
{
  if (socket_fd_ >= 0) {
    close(socket_fd_);
  }
}

void ImuSocketSenderComponent::setup_socket()
{
  socket_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
  if (socket_fd_ < 0) {
    throw std::runtime_error(
      std::string("Failed to create Unix datagram socket: ") + strerror(errno));
  }

  memset(&dest_addr_, 0, sizeof(dest_addr_));
  dest_addr_.sun_family = AF_UNIX;
  strncpy(dest_addr_.sun_path, socket_path_.c_str(), sizeof(dest_addr_.sun_path) - 1);
}

int64_t ImuSocketSenderComponent::resolve_timestamp_ns(
  const px4_msgs::msg::HighresImu & src) const
{
  const uint64_t us = src.timestamp_sample != 0 ? src.timestamp_sample : src.timestamp;
  return static_cast<int64_t>(us * 1000ULL);
}

void ImuSocketSenderComponent::send(const px4_msgs::msg::HighresImu & src)
{
  if (socket_fd_ < 0) {
    return;
  }

  ImuData data{};
  data.timestamp = static_cast<uint64_t>(resolve_timestamp_ns(src));
  data.accel[0] = src.accel[0];
  data.accel[1] = src.accel[1];
  data.accel[2] = src.accel[2];
  data.gyro[0] = src.gyro[0];
  data.gyro[1] = src.gyro[1];
  data.gyro[2] = src.gyro[2];

  const ssize_t sent = sendto(
    socket_fd_, &data, sizeof(data),
    MSG_DONTWAIT | MSG_NOSIGNAL,
    reinterpret_cast<const struct sockaddr *>(&dest_addr_),
    sizeof(dest_addr_));

  if (sent >= 0) {
    return;
  }

  if (errno == EAGAIN || errno == EWOULDBLOCK) {
    const auto dropped = dropped_messages_.fetch_add(1, std::memory_order_relaxed) + 1;
    RCLCPP_WARN_THROTTLE(
      get_logger(), *get_clock(), 5000,
      "Socket backpressure, dropping (dropped=%llu)",
      static_cast<unsigned long long>(dropped));
    return;
  }

  RCLCPP_WARN_THROTTLE(
    get_logger(), *get_clock(), 5000,
    "Failed to send to %s: %s", socket_path_.c_str(), strerror(errno));
}

void ImuSocketSenderComponent::imu_callback(px4_msgs::msg::HighresImu::UniquePtr msg)
{
  send(*msg);
}

}  // namespace px4_connector

RCLCPP_COMPONENTS_REGISTER_NODE(px4_connector::ImuSocketSenderComponent)
