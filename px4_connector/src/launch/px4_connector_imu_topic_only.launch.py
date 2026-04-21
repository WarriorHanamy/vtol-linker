# SPDX-FileCopyrightText: OpenCode
# SPDX-License-Identifier: MIT

import launch
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode


def generate_launch_description():
    output_topic = LaunchConfiguration("output_topic")

    px4_container = ComposableNodeContainer(
        package="rclcpp_components",
        name="px4_connector_container",
        namespace="",
        executable="component_container_mt",
        composable_node_descriptions=[
            ComposableNode(
                package="px4_connector",
                plugin="px4_connector::ImuTopicSenderComponent",
                name="imu_topic_sender",
                parameters=[
                    {
                        "output_topic": output_topic,
                    }
                ],
            ),
        ],
        output="screen",
    )

    return launch.LaunchDescription(
        [
            DeclareLaunchArgument("output_topic", default_value="/px4/imu"),
            px4_container,
        ]
    )
