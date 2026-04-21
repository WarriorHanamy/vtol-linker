#include "px4_connector/imu_topic_sender_component.hpp"

#include <functional>
#include <memory>
#include <utility>

#include <rclcpp_components/register_node_macro.hpp>

namespace {

constexpr char kDefaultInputTopic[] = "/fmu/out/highres_imu_flu";
constexpr char kDefaultOutputTopic[] = "/px4/imu";
constexpr size_t kDefaultDepth = 40;

}  // namespace

namespace px4_connector
{

ImuTopicSenderComponent::ImuTopicSenderComponent(const rclcpp::NodeOptions & options)
: Node("imu_topic_sender", options),
  input_qos_depth_(kDefaultDepth),
  output_qos_depth_(kDefaultDepth)
{
  input_topic_ = declare_parameter<std::string>("input_topic", kDefaultInputTopic);
  output_topic_ = declare_parameter<std::string>("output_topic", kDefaultOutputTopic);
  input_qos_depth_ = declare_parameter<int>("input_qos_depth", static_cast<int>(kDefaultDepth));
  output_qos_depth_ = declare_parameter<int>("output_qos_depth", static_cast<int>(kDefaultDepth));

  auto output_qos = rclcpp::SensorDataQoS();
  output_qos.keep_last(output_qos_depth_);
  publisher_ = create_publisher<sensor_msgs::msg::Imu>(output_topic_, output_qos);

  auto input_qos = rclcpp::SensorDataQoS();
  input_qos.keep_last(input_qos_depth_);
  subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
    input_topic_, input_qos,
    std::bind(&ImuTopicSenderComponent::imu_callback, this, std::placeholders::_1));

  RCLCPP_INFO(get_logger(), "%s -> %s", input_topic_.c_str(), output_topic_.c_str());
}

int64_t ImuTopicSenderComponent::resolve_timestamp_ns(
  const px4_msgs::msg::HighresImu & src) const
{
  const uint64_t us = src.timestamp_sample != 0 ? src.timestamp_sample : src.timestamp;
  return static_cast<int64_t>(us * 1000ULL);
}

sensor_msgs::msg::Imu::UniquePtr
ImuTopicSenderComponent::build_imu(const px4_msgs::msg::HighresImu & src) const
{
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

void ImuTopicSenderComponent::imu_callback(px4_msgs::msg::HighresImu::UniquePtr msg)
{
  publisher_->publish(build_imu(*msg));
}

}  // namespace px4_connector

RCLCPP_COMPONENTS_REGISTER_NODE(px4_connector::ImuTopicSenderComponent)
