from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    socket_path = LaunchConfiguration("socket_path")
    output_mode = LaunchConfiguration("output_mode")
    output_topic = LaunchConfiguration("output_topic")

    return LaunchDescription(
        [
            DeclareLaunchArgument("socket_path", default_value="/tmp/imu_bridge.sock"),
            DeclareLaunchArgument("output_mode", default_value="topic"),
            DeclareLaunchArgument("output_topic", default_value="/px4/imu"),
            Node(
                package="imu_bridge",
                executable="imu_sender_node",
                name="imu_sender_node",
                parameters=[
                    {
                        "socket_path": socket_path,
                        "output_mode": output_mode,
                        "output_topic": output_topic,
                    }
                ],
                output="screen",
            ),
        ]
    )
