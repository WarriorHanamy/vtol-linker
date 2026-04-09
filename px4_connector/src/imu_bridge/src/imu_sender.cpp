#include <chrono>
#include <cstring>
#include <functional>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <px4_msgs/msg/highres_imu.hpp>
#include <px4_msgs/msg/timesync_status.hpp>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace
{

constexpr const char* kSocketPath = "/tmp/imu_bridge.sock";
constexpr const char* kTimesyncTopic = "/fmu/out/timesync_status";
constexpr const char* kImuTopic = "/fmu/out/highres_imu_flu";

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
      smoothed_offset_us_(0),
      has_offset_(false),
      msg_count_(0)
    {
        socket_path_ = declare_parameter<std::string>("socket_path", kSocketPath);
        log_interval_ = declare_parameter<int>("log_interval", 1000);

        connect_socket();

        // Subscribe to TimesyncStatus for smoothed time offset
        timesync_subscription_ = create_subscription<px4_msgs::msg::TimesyncStatus>(
            kTimesyncTopic,
            rclcpp::SensorDataQoS(),
            std::bind(&ImuSender::timesync_callback, this, std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Subscribed to %s", kTimesyncTopic);

        // Subscribe to IMU data
        imu_subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
            kImuTopic,
            rclcpp::SensorDataQoS(),
            std::bind(&ImuSender::imu_callback, this, std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Subscribed to %s", kImuTopic);
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
    void timesync_callback(const px4_msgs::msg::TimesyncStatus::SharedPtr msg)
    {
        smoothed_offset_us_ = static_cast<int64_t>(msg->estimated_offset);
        has_offset_ = true;

        RCLCPP_DEBUG(get_logger(),
            "TimesyncStatus: offset=%ld us, RTT=%u us, protocol=%u",
            msg->estimated_offset,
            msg->round_trip_time,
            msg->source_protocol);
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
        // Use TimesyncStatus offset if available; fallback to static offset on first message
        if (!has_offset_)
        {
            static bool warned = false;
            if (!warned)
            {
                RCLCPP_WARN_ONCE(get_logger(),
                    "TimesyncStatus not received yet, using static offset from first IMU message");
                warned = true;
            }

            // One-time static offset (original behavior, but with unit fix)
            static uint64_t first_timestamp_sample_us = 0;
            static uint64_t first_ros_time_ns = 0;
            static bool first_msg = true;

            if (first_msg)
            {
                first_timestamp_sample_us = msg->timestamp_sample;
                first_ros_time_ns = now().nanoseconds();
                smoothed_offset_us_ = static_cast<int64_t>(first_ros_time_ns / 1000 - first_timestamp_sample_us);
                has_offset_ = true;
                first_msg = false;

                RCLCPP_INFO(get_logger(),
                    "Static offset: %ld ns (%.3f s)",
                    smoothed_offset_us_ * 1000,
                    smoothed_offset_us_ / 1e6);
            }
        }

        // Convert PX4 timestamp_sample (μs) to ROS time (ns) using offset (μs)
        // ros_time_ns = timestamp_sample_us * 1000 + offset_us * 1000
        uint64_t imu_time_ns = static_cast<uint64_t>(
            static_cast<int64_t>(msg->timestamp_sample) * 1000 +
            smoothed_offset_us_ * 1000);

        ImuData data;
        data.timestamp = imu_time_ns;
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

        // Diagnostic verification: print ros_now vs imu_time every log_interval messages
        msg_count_++;
        if (msg_count_ % log_interval_ == 0)
        {
            uint64_t ros_now_ns = now().nanoseconds();
            int64_t delta_us = static_cast<int64_t>(ros_now_ns - imu_time_ns) / 1000;

            RCLCPP_INFO(get_logger(),
                "TimeSync verify: ros_now=%lu imu_time=%lu delta=%ld us (%.1f ms) %s",
                ros_now_ns,
                imu_time_ns,
                delta_us,
                delta_us / 1000.0,
                (delta_us < 0) ? "[FAIL: ros_now < imu_time]" : "[OK]");

            if (delta_us < 0)
            {
                RCLCPP_WARN(get_logger(),
                    "Time sync error: ros_now is BEHIND imu_time by %ld us", -delta_us);
            }
        }
    }

    std::string socket_path_;
    int socket_fd_;
    int64_t smoothed_offset_us_;       // PX4 estimated offset (microseconds)
    bool has_offset_;                  // true once TimesyncStatus received or fallback computed
    uint64_t msg_count_;               // for periodic diagnostics
    int log_interval_;                 // diagnostic print interval

    rclcpp::Subscription<px4_msgs::msg::TimesyncStatus>::SharedPtr timesync_subscription_;
    rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr imu_subscription_;
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ImuSender>());
    rclcpp::shutdown();
    return 0;
}
