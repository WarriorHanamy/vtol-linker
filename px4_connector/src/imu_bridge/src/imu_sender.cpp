#include "imu_bridge/imu_sender_component.hpp"

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
constexpr char kDefaultOutputTopic[] = "/px4/imu";
constexpr size_t kDefaultImuDepth = 40;

} // namespace

namespace imu_bridge {

ImuSenderComponent::ImuSenderComponent(const rclcpp::NodeOptions &options)
    : Node("imu_sender_node", options), input_qos_depth_(kDefaultImuDepth),
      output_qos_depth_(kDefaultImuDepth), socket_fd_(-1), dest_addr_{},
      dropped_socket_messages_(0) {
  socket_path_ =
      declare_parameter<std::string>("socket_path", kDefaultSocketPath);
  input_topic_ =
      declare_parameter<std::string>("input_topic", kDefaultInputTopic);
  output_mode_ = declare_parameter<std::string>("output_mode", "topic");
  output_topic_ =
      declare_parameter<std::string>("output_topic", kDefaultOutputTopic);
  input_qos_depth_ = declare_parameter<int>("input_qos_depth",
                                            static_cast<int>(kDefaultImuDepth));
  output_qos_depth_ = declare_parameter<int>(
      "output_qos_depth", static_cast<int>(kDefaultImuDepth));

  validate_parameters();

  if (output_mode_ == "topic") {
    auto output_qos = rclcpp::SensorDataQoS();
    output_qos.keep_last(output_qos_depth_);
    imu_publisher_ =
        create_publisher<sensor_msgs::msg::Imu>(output_topic_, output_qos);
    RCLCPP_INFO(get_logger(), "IMU topic output enabled: %s",
                output_topic_.c_str());
  }

  if (output_mode_ == "socket") {
    setup_socket();
    RCLCPP_INFO(get_logger(), "IMU socket output enabled: %s",
                socket_path_.c_str());
  }

  auto input_qos = rclcpp::SensorDataQoS();
  input_qos.keep_last(input_qos_depth_);
  imu_subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
      input_topic_, input_qos,
      std::bind(&ImuSenderComponent::imu_callback, this,
                std::placeholders::_1));

  RCLCPP_INFO(get_logger(), "Subscribed to %s with output_mode=%s",
              input_topic_.c_str(), output_mode_.c_str());
}

ImuSenderComponent::~ImuSenderComponent() {
  if (socket_fd_ >= 0) {
    close(socket_fd_);
  }
}

void ImuSenderComponent::validate_parameters() {
  if (output_mode_ != "topic" && output_mode_ != "socket") {
    throw std::invalid_argument(
        "Invalid output_mode. Expected one of: topic, socket");
  }

  if (input_qos_depth_ == 0 || output_qos_depth_ == 0) {
    throw std::invalid_argument("QoS depths must be greater than zero");
  }
}

void ImuSenderComponent::setup_socket() {
  socket_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
  if (socket_fd_ < 0) {
    throw std::runtime_error(
        std::string("Failed to create Unix datagram socket: ") +
        strerror(errno));
  }

  memset(&dest_addr_, 0, sizeof(dest_addr_));
  dest_addr_.sun_family = AF_UNIX;
  strncpy(dest_addr_.sun_path, socket_path_.c_str(),
          sizeof(dest_addr_.sun_path) - 1);
}

int64_t ImuSenderComponent::resolve_timestamp_ns(
    const px4_msgs::msg::HighresImu &src) const {
  const uint64_t timestamp_us =
      src.timestamp_sample != 0 ? src.timestamp_sample : src.timestamp;
  return static_cast<int64_t>(timestamp_us * 1000ULL);
}

sensor_msgs::msg::Imu::UniquePtr
ImuSenderComponent::build_ros2_imu(const px4_msgs::msg::HighresImu &src) const {
  auto msg = std::make_unique<sensor_msgs::msg::Imu>();
  msg->header.stamp = rclcpp::Time(resolve_timestamp_ns(src));
  msg->header.frame_id = "imu_link";

  msg->linear_acceleration.x = src.accel[0];
  msg->linear_acceleration.y = src.accel[1];
  msg->linear_acceleration.z = src.accel[2];

  msg->angular_velocity.x = src.gyro[0];
  msg->angular_velocity.y = src.gyro[1];
  msg->angular_velocity.z = src.gyro[2];

  msg->orientation_covariance[0] = -1.0;

  msg->linear_acceleration_covariance[0] = 0.01;
  msg->linear_acceleration_covariance[4] = 0.01;
  msg->linear_acceleration_covariance[8] = 0.01;

  msg->angular_velocity_covariance[0] = 0.0001;
  msg->angular_velocity_covariance[4] = 0.0001;
  msg->angular_velocity_covariance[8] = 0.0001;

  return msg;
}

void ImuSenderComponent::publish_topic(const px4_msgs::msg::HighresImu &src) {
  if (!imu_publisher_) {
    return;
  }
  imu_publisher_->publish(build_ros2_imu(src));
}

void ImuSenderComponent::send_via_socket(const px4_msgs::msg::HighresImu &src) {
  if (socket_fd_ < 0) {
    return;
  }

  ImuData socket_data{};
  socket_data.timestamp = static_cast<uint64_t>(resolve_timestamp_ns(src));
  socket_data.accel[0] = src.accel[0];
  socket_data.accel[1] = src.accel[1];
  socket_data.accel[2] = src.accel[2];
  socket_data.gyro[0] = src.gyro[0];
  socket_data.gyro[1] = src.gyro[1];
  socket_data.gyro[2] = src.gyro[2];

  const ssize_t sent =
      sendto(socket_fd_, &socket_data, sizeof(socket_data),
             MSG_DONTWAIT | MSG_NOSIGNAL,
             reinterpret_cast<const struct sockaddr *>(&dest_addr_),
             sizeof(dest_addr_));

  if (sent >= 0) {
    return;
  }

  if (errno == EAGAIN || errno == EWOULDBLOCK) {
    const auto dropped =
        dropped_socket_messages_.fetch_add(1, std::memory_order_relaxed) + 1;
    RCLCPP_WARN_THROTTLE(
        get_logger(), *get_clock(), 5000,
        "IMU socket backpressure, dropping sample (dropped=%llu)",
        static_cast<unsigned long long>(dropped));
    return;
  }

  RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 5000,
                       "Failed to send IMU datagram to %s: %s",
                       socket_path_.c_str(), strerror(errno));
}

void ImuSenderComponent::imu_callback(
    px4_msgs::msg::HighresImu::UniquePtr msg) {
  if (output_mode_ == "topic") {
    publish_topic(*msg);
  }
  if (output_mode_ == "socket") {
    send_via_socket(*msg);
  }
}

} // namespace imu_bridge

RCLCPP_COMPONENTS_REGISTER_NODE(imu_bridge::ImuSenderComponent)
