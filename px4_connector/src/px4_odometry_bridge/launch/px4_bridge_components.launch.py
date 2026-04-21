from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode


def generate_launch_description():
    imu_input_topic = LaunchConfiguration("imu_input_topic")
    imu_output_mode = LaunchConfiguration("imu_output_mode")
    imu_output_topic = LaunchConfiguration("imu_output_topic")
    imu_socket_path = LaunchConfiguration("imu_socket_path")
    odom_input_topic = LaunchConfiguration("odom_input_topic")
    odom_output_topic = LaunchConfiguration("odom_output_topic")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "imu_input_topic", default_value="/fmu/out/highres_imu_flu"
            ),
            DeclareLaunchArgument("imu_output_mode", default_value="topic"),
            DeclareLaunchArgument("imu_output_topic", default_value="/px4/imu"),
            DeclareLaunchArgument(
                "imu_socket_path", default_value="/tmp/imu_bridge.sock"
            ),
            DeclareLaunchArgument("odom_input_topic", default_value="/Odometry"),
            DeclareLaunchArgument(
                "odom_output_topic",
                default_value="/fmu/in/vehicle_visual_odometry",
            ),
            ComposableNodeContainer(
                name="px4_bridge_container",
                namespace="",
                package="rclcpp_components",
                executable="component_container_mt",
                output="screen",
                composable_node_descriptions=[
                    ComposableNode(
                        package="imu_bridge",
                        plugin="imu_bridge::ImuSenderComponent",
                        name="imu_sender_node",
                        extra_arguments=[{"use_intra_process_comms": True}],
                        parameters=[
                            {
                                "input_topic": imu_input_topic,
                                "output_mode": imu_output_mode,
                                "output_topic": imu_output_topic,
                                "socket_path": imu_socket_path,
                            }
                        ],
                    ),
                    ComposableNode(
                        package="px4_odometry_bridge",
                        plugin="px4_odometry_bridge::Px4VisualOdometryBridgeComponent",
                        name="px4_visual_odometry_bridge",
                        extra_arguments=[{"use_intra_process_comms": True}],
                        parameters=[
                            {
                                "input_topic": odom_input_topic,
                                "output_topic": odom_output_topic,
                            }
                        ],
                    ),
                ],
            ),
        ]
    )
