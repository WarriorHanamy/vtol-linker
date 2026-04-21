#pragma once

#include <array>
#include <cstdint>
#include <string>

#include <Eigen/Dense>

#include <nav_msgs/msg/odometry.hpp>
#include <px4_msgs/msg/vehicle_odometry.hpp>
#include <rclcpp/rclcpp.hpp>

namespace px4_odometry_bridge
{

class Px4VisualOdometryBridgeComponent : public rclcpp::Node
{
public:
  explicit Px4VisualOdometryBridgeComponent(const rclcpp::NodeOptions & options);

private:
  void handle_odometry(nav_msgs::msg::Odometry::UniquePtr message);
  uint64_t to_microseconds(const rclcpp::Time & time) const;
  std::array<float, 3> rotate_vector(
    const Eigen::Matrix3d & rotation,
    const geometry_msgs::msg::Vector3 & vector) const;
  std::array<float, 3> remap_enu_variance_to_ned(const std::array<double, 36> & covariance) const;
  std::array<float, 3> orientation_variance_from_pose_covariance(
    const std::array<double, 36> & covariance) const;

  Eigen::Matrix3d enu_to_ned_;
  Eigen::Matrix3d flu_to_frd_;
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr subscription_;
  rclcpp::Publisher<px4_msgs::msg::VehicleOdometry>::SharedPtr publisher_;
};

}  // namespace px4_odometry_bridge
