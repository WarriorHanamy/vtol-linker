#include <chrono>
#include <cstring>
#include <functional>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <px4_msgs/msg/highres_imu.hpp>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace
{

constexpr const char* kSocketPath = "/tmp/imu_bridge.sock";

struct ImuData
{
    uint64_t timestamp;  // nanoseconds (ROS time, with offset applied)
    float accel[3];      // m/s^2 (FLU frame)
    float gyro[3];       // rad/s (FLU frame)
};

}  // namespace

class ImuSender : public rclcpp::Node
{
public:
    ImuSender()
    : Node("imu_sender_node"),
      socket_fd_(-1),
      px4_to_ros_offset_ns_(0),
      first_message_(true)
    {
        socket_path_ = declare_parameter<std::string>("socket_path", kSocketPath);

        connect_socket();

        subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
            "/fmu/out/highres_imu_flu",
            rclcpp::SensorDataQoS(),
            std::bind(&ImuSender::imu_callback, this, std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Subscribed to /fmu/out/highres_imu_flu");
        RCLCPP_INFO(get_logger(), "Sending to Unix socket: %s", socket_path_.c_str());
    }

    ~ImuSender() override
    {
        if (socket_fd_ >= 0)
        {
            close(socket_fd_);
        }
    }

private:
    void connect_socket()
    {
        if (socket_fd_ >= 0)
        {
            close(socket_fd_);
        }

        socket_fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socket_fd_ < 0)
        {
            RCLCPP_WARN(get_logger(), "Failed to create socket: %s", strerror(errno));
            return;
        }

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path_.c_str(), sizeof(addr.sun_path) - 1);

        if (connect(socket_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0)
        {
            RCLCPP_WARN(get_logger(), "Failed to connect to socket: %s (will retry)", strerror(errno));
            close(socket_fd_);
            socket_fd_ = -1;
        }
        else
        {
            RCLCPP_INFO(get_logger(), "Connected to Unix socket");
        }
    }

    void imu_callback(const px4_msgs::msg::HighresImu::SharedPtr msg)
    {
        if (first_message_)
        {
            uint64_t current_ros_time_ns = now().nanoseconds();
            px4_to_ros_offset_ns_ = current_ros_time_ns - msg->timestamp_sample;
            first_message_ = false;

            RCLCPP_INFO(get_logger(),
                "Time offset: %lu ns (%.3f s)",
                px4_to_ros_offset_ns_,
                px4_to_ros_offset_ns_ / 1e9);
        }

        ImuData data;
        data.timestamp = msg->timestamp_sample + px4_to_ros_offset_ns_;
        data.accel[0] = msg->accel[0];
        data.accel[1] = msg->accel[1];
        data.accel[2] = msg->accel[2];
        data.gyro[0] = msg->gyro[0];
        data.gyro[1] = msg->gyro[1];
        data.gyro[2] = msg->gyro[2];

        if (socket_fd_ < 0)
        {
            connect_socket();
            if (socket_fd_ < 0)
            {
                return;
            }
        }

        ssize_t sent = send(socket_fd_, &data, sizeof(data), MSG_NOSIGNAL);
        if (sent < 0)
        {
            RCLCPP_WARN(get_logger(), "Failed to send data: %s (reconnecting)", strerror(errno));
            close(socket_fd_);
            socket_fd_ = -1;
        }
    }

    std::string socket_path_;
    int socket_fd_;
    uint64_t px4_to_ros_offset_ns_;
    bool first_message_;
    rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr subscription_;
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ImuSender>());
    rclcpp::shutdown();
    return 0;
}
