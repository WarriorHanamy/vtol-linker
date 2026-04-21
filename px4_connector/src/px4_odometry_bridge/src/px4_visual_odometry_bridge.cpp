#include "px4_odometry_bridge/px4_visual_odometry_bridge_component.hpp"

#include <cmath>
#include <functional>
#include <memory>
#include <utility>

#include <Eigen/Geometry>

#include <rclcpp_components/register_node_macro.hpp>

namespace
{

Eigen::Matrix3d enu_to_ned_matrix()
{
  Eigen::Matrix3d matrix;
  matrix << 0.0, 1.0, 0.0,
    1.0, 0.0, 0.0,
    0.0, 0.0, -1.0;
  return matrix;
}

Eigen::Matrix3d flu_to_frd_matrix()
{
  Eigen::Matrix3d matrix = Eigen::Matrix3d::Identity();
  matrix(1, 1) = -1.0;
  matrix(2, 2) = -1.0;
  return matrix;
}

}  // namespace

namespace px4_odometry_bridge
{

Px4VisualOdometryBridgeComponent::Px4VisualOdometryBridgeComponent(
  const rclcpp::NodeOptions & options)
: Node("px4_visual_odometry_bridge", options),
  enu_to_ned_(enu_to_ned_matrix()),
  flu_to_frd_(flu_to_frd_matrix())
{
  const auto input_topic = declare_parameter<std::string>("input_topic", "/Odometry");
  const auto output_topic = declare_parameter<std::string>(
    "output_topic", "/fmu/in/vehicle_visual_odometry");
  const auto input_qos_depth = declare_parameter<int>("input_qos_depth", 20);
  const auto output_qos_depth = declare_parameter<int>("output_qos_depth", 10);

  publisher_ = create_publisher<px4_msgs::msg::VehicleOdometry>(
    output_topic,
    rclcpp::QoS(output_qos_depth));
  subscription_ = create_subscription<nav_msgs::msg::Odometry>(
    input_topic,
    rclcpp::QoS(input_qos_depth),
    std::bind(&Px4VisualOdometryBridgeComponent::handle_odometry, this, std::placeholders::_1));

  RCLCPP_INFO(get_logger(), "Bridging %s -> %s", input_topic.c_str(), output_topic.c_str());
}

uint64_t Px4VisualOdometryBridgeComponent::to_microseconds(const rclcpp::Time & time) const
{
  return static_cast<uint64_t>(time.nanoseconds() / 1000);
}

std::array<float, 3> Px4VisualOdometryBridgeComponent::rotate_vector(
  const Eigen::Matrix3d & rotation,
  const geometry_msgs::msg::Vector3 & vector) const
{
  const Eigen::Vector3d input(vector.x, vector.y, vector.z);
  const Eigen::Vector3d output = rotation * input;
  return {
    static_cast<float>(output.x()),
    static_cast<float>(output.y()),
    static_cast<float>(output.z())
  };
}

std::array<float, 3> Px4VisualOdometryBridgeComponent::remap_enu_variance_to_ned(
  const std::array<double, 36> & covariance) const
{
  return {
    static_cast<float>(covariance[7]),
    static_cast<float>(covariance[0]),
    static_cast<float>(covariance[14])
  };
}

std::array<float, 3> Px4VisualOdometryBridgeComponent::orientation_variance_from_pose_covariance(
  const std::array<double, 36> & covariance) const
{
  return {
    static_cast<float>(covariance[21]),
    static_cast<float>(covariance[28]),
    static_cast<float>(covariance[35])
  };
}

void Px4VisualOdometryBridgeComponent::handle_odometry(nav_msgs::msg::Odometry::UniquePtr message)
{
  auto output = std::make_unique<px4_msgs::msg::VehicleOdometry>();

  const rclcpp::Time sample_time(message->header.stamp);
  output->timestamp_sample = to_microseconds(sample_time);
  output->timestamp = to_microseconds(now());

  output->pose_frame = px4_msgs::msg::VehicleOdometry::POSE_FRAME_NED;
  output->velocity_frame = px4_msgs::msg::VehicleOdometry::VELOCITY_FRAME_BODY_FRD;

  const Eigen::Vector3d position_enu(
    message->pose.pose.position.x,
    message->pose.pose.position.y,
    message->pose.pose.position.z);
  const Eigen::Vector3d position_ned = enu_to_ned_ * position_enu;

  output->position[0] = static_cast<float>(position_ned.x());
  output->position[1] = static_cast<float>(position_ned.y());
  output->position[2] = static_cast<float>(position_ned.z());

  Eigen::Quaterniond q_enu_flu(
    message->pose.pose.orientation.w,
    message->pose.pose.orientation.x,
    message->pose.pose.orientation.y,
    message->pose.pose.orientation.z);

  if (std::abs(q_enu_flu.norm()) < 1e-6) {
    q_enu_flu = Eigen::Quaterniond::Identity();
  } else {
    q_enu_flu.normalize();
  }

  const Eigen::Matrix3d rotation_ned_frd =
    enu_to_ned_ * q_enu_flu.toRotationMatrix() * flu_to_frd_;
  Eigen::Quaterniond q_ned_frd(rotation_ned_frd);
  q_ned_frd.normalize();

  output->q[0] = static_cast<float>(q_ned_frd.w());
  output->q[1] = static_cast<float>(q_ned_frd.x());
  output->q[2] = static_cast<float>(q_ned_frd.y());
  output->q[3] = static_cast<float>(q_ned_frd.z());

  const auto linear_velocity = rotate_vector(flu_to_frd_, message->twist.twist.linear);
  output->velocity[0] = linear_velocity[0];
  output->velocity[1] = linear_velocity[1];
  output->velocity[2] = linear_velocity[2];

  const auto angular_velocity = rotate_vector(flu_to_frd_, message->twist.twist.angular);
  output->angular_velocity[0] = angular_velocity[0];
  output->angular_velocity[1] = angular_velocity[1];
  output->angular_velocity[2] = angular_velocity[2];

  const auto position_variance = remap_enu_variance_to_ned(message->pose.covariance);
  output->position_variance[0] = position_variance[0];
  output->position_variance[1] = position_variance[1];
  output->position_variance[2] = position_variance[2];

  const auto orientation_variance = orientation_variance_from_pose_covariance(
    message->pose.covariance);
  output->orientation_variance[0] = orientation_variance[0];
  output->orientation_variance[1] = orientation_variance[1];
  output->orientation_variance[2] = orientation_variance[2];

  const auto velocity_variance = remap_enu_variance_to_ned(message->twist.covariance);
  output->velocity_variance[0] = velocity_variance[0];
  output->velocity_variance[1] = velocity_variance[1];
  output->velocity_variance[2] = velocity_variance[2];

  output->reset_counter = 0;
  output->quality = 100;

  publisher_->publish(std::move(output));
}

}  // namespace px4_odometry_bridge

RCLCPP_COMPONENTS_REGISTER_NODE(px4_odometry_bridge::Px4VisualOdometryBridgeComponent)
