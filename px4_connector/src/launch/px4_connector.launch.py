# SPDX-FileCopyrightText: OpenCode
# SPDX-License-Identifier: MIT

import launch
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode


def generate_launch_description():
    socket_path = LaunchConfiguration("socket_path")
    output_mode = LaunchConfiguration("output_mode")
    output_topic = LaunchConfiguration("output_topic")

    px4_container = ComposableNodeContainer(
        package="rclcpp_components",
        name="px4_connector_container",
        namespace="",
        executable="component_container_mt",
        composable_node_descriptions=[
            ComposableNode(
                package="px4_connector",
                plugin="px4_connector::ImuSenderComponent",
                name="imu_sender",
                parameters=[
                    {
                        "socket_path": socket_path,
                        "output_mode": output_mode,
                        "output_topic": output_topic,
                    }
                ],
            ),
            ComposableNode(
                package="px4_connector",
                plugin="px4_connector::Px4VisualOdometryBridgeComponent",
                name="px4_visual_odometry_bridge",
                parameters=[
                    {
                        "input_topic": "/Odometry",
                        "output_topic": "/fmu/in/vehicle_visual_odometry",
                    }
                ],
            ),
        ],
        output="screen",
    )

    return launch.LaunchDescription(
        [
            DeclareLaunchArgument("socket_path", default_value="/tmp/imu_bridge.sock"),
            DeclareLaunchArgument("output_mode", default_value="topic"),
            DeclareLaunchArgument("output_topic", default_value="/px4/imu"),
            px4_container,
        ]
    )
