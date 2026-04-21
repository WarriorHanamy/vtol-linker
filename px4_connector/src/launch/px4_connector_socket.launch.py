# SPDX-FileCopyrightText: OpenCode
# SPDX-License-Identifier: MIT

import launch
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode


def generate_launch_description():
    socket_path = LaunchConfiguration("socket_path")

    px4_container = ComposableNodeContainer(
        package="rclcpp_components",
        name="px4_connector_container",
        namespace="",
        executable="component_container_mt",
        composable_node_descriptions=[
            ComposableNode(
                package="px4_connector",
                plugin="px4_connector::ImuSocketSenderComponent",
                name="imu_socket_sender",
                parameters=[
                    {
                        "socket_path": socket_path,
                    }
                ],
            ),
            ComposableNode(
                package="px4_connector",
                plugin="px4_connector::Px4VisualOdometryBridgeComponent",
                name="px4_visual_odometry_bridge",
            ),
        ],
        output="screen",
    )

    return launch.LaunchDescription(
        [
            DeclareLaunchArgument("socket_path", default_value="/tmp/imu_bridge.sock"),
            px4_container,
        ]
    )
