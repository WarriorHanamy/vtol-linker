#include <chrono>
#include <cerrno>
#include <cstring>
#include <functional>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <px4_msgs/msg/highres_imu.hpp>
#include <px4_msgs/msg/timesync_status.hpp>
#include <sensor_msgs/msg/imu.hpp>

#include "clock_alignment.h"

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
    uint64_t timestamp;  // nanoseconds (ROS time, after offset and systematic delta)
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
      output_mode_("topic"),
      output_topic_("/px4/imu"),
      log_interval_(1000),
      msg_count_(0)
    {
        // 声明参数
        socket_path_ = declare_parameter<std::string>("socket_path", kSocketPath);
        log_interval_ = declare_parameter<int>("log_interval", 1000);
        output_mode_ = declare_parameter<std::string>("output_mode", "topic");
        output_topic_ = declare_parameter<std::string>("output_topic", "/px4/imu");

        // 根据模式初始化
        if (output_mode_ == "socket")
        {
            setup_socket();
            RCLCPP_INFO(get_logger(), "Output mode: socket (path: %s)", socket_path_.c_str());
        }
        else if (output_mode_ == "topic")
        {
            imu_publisher_ = create_publisher<sensor_msgs::msg::Imu>(
                output_topic_, rclcpp::SensorDataQoS());
            RCLCPP_INFO(get_logger(), "Output mode: topic (%s)", output_topic_.c_str());
        }
        else
        {
            RCLCPP_ERROR(get_logger(), "Invalid output_mode: %s (expected 'topic' or 'socket')",
                         output_mode_.c_str());
        }

        // 订阅 TimesyncStatus
        timesync_subscription_ = create_subscription<px4_msgs::msg::TimesyncStatus>(
            kTimesyncTopic,
            rclcpp::SensorDataQoS(),
            std::bind(&ImuSender::timesync_callback, this, std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Subscribed to %s", kTimesyncTopic);

        // 订阅 IMU 数据
        imu_subscription_ = create_subscription<px4_msgs::msg::HighresImu>(
            kImuTopic,
            rclcpp::SensorDataQoS(),
            std::bind(&ImuSender::imu_callback, this, std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Subscribed to %s", kImuTopic);
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
        clock_.update_timesync_offset(static_cast<int64_t>(msg->estimated_offset));

        RCLCPP_DEBUG(get_logger(),
            "TimesyncStatus: offset=%ld us, RTT=%u us, protocol=%u",
            msg->estimated_offset,
            msg->round_trip_time,
            msg->source_protocol);
    }

    void setup_socket()
    {
        socket_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (socket_fd_ < 0)
        {
            RCLCPP_ERROR(get_logger(), "Failed to create datagram socket: %s", strerror(errno));
            return;
        }

        memset(&dest_addr_, 0, sizeof(dest_addr_));
        dest_addr_.sun_family = AF_UNIX;
        strncpy(dest_addr_.sun_path, socket_path_.c_str(), sizeof(dest_addr_.sun_path) - 1);

        RCLCPP_INFO(get_logger(), "Unix datagram socket created, target: %s", socket_path_.c_str());
    }

    void imu_callback(const px4_msgs::msg::HighresImu::SharedPtr msg)
    {
        const int64_t ros_now_ns = now().nanoseconds();
        const int64_t timestamp_sample_us = static_cast<int64_t>(msg->timestamp_sample);

        // 首次收到 IMU 且无 Timesync 时使用 fallback
        if (!clock_.has_offset())
        {
            RCLCPP_WARN_ONCE(get_logger(),
                "TimesyncStatus not received yet, using static offset from first IMU message");

            clock_.init_fallback_offset(timestamp_sample_us, ros_now_ns);

            RCLCPP_INFO(get_logger(),
                "Fallback offset initialized (source: first IMU sample)");
        }

        // 时间对齐
        const auto aligned = clock_.align(timestamp_sample_us, ros_now_ns);

        if (!aligned.ready)
        {
            // 仍在校准中，跳过输出
            return;
        }

        // 准备 IMU 数据 (FLU frame)
        ImuData socket_data;
        socket_data.timestamp = static_cast<uint64_t>(aligned.ros_time_ns);
        socket_data.accel[0] = msg->accel[0];
        socket_data.accel[1] = msg->accel[1];
        socket_data.accel[2] = msg->accel[2];
        socket_data.gyro[0] = msg->gyro[0];
        socket_data.gyro[1] = msg->gyro[1];
        socket_data.gyro[2] = msg->gyro[2];

        // 模式分发
        if (output_mode_ == "topic")
        {
            publish_ros2_imu(aligned.ros_time_ns, msg);
        }
        else if (output_mode_ == "socket")
        {
            send_via_socket(socket_data);
        }

        // 诊断日志
        msg_count_++;
        if (msg_count_ % log_interval_ == 0)
        {
            log_diagnostics(ros_now_ns, aligned.ros_time_ns);
        }
    }

    void publish_ros2_imu(int64_t timestamp_ns, const px4_msgs::msg::HighresImu::SharedPtr& src)
    {
        auto msg = std::make_unique<sensor_msgs::msg::Imu>();

        // Header
        msg->header.stamp = rclcpp::Time(timestamp_ns);
        msg->header.frame_id = "imu_link";

        // Linear acceleration (FLU frame)
        msg->linear_acceleration.x = src->accel[0];
        msg->linear_acceleration.y = src->accel[1];
        msg->linear_acceleration.z = src->accel[2];

        // Angular velocity (FLU frame)
        msg->angular_velocity.x = src->gyro[0];
        msg->angular_velocity.y = src->gyro[1];
        msg->angular_velocity.z = src->gyro[2];

        // Orientation unknown
        msg->orientation_covariance[0] = -1;

        // Covariances (standard IMU values)
        msg->linear_acceleration_covariance[0] = 0.01;
        msg->linear_acceleration_covariance[4] = 0.01;
        msg->linear_acceleration_covariance[8] = 0.01;

        msg->angular_velocity_covariance[0] = 0.0001;
        msg->angular_velocity_covariance[4] = 0.0001;
        msg->angular_velocity_covariance[8] = 0.0001;

        imu_publisher_->publish(std::move(msg));
    }

    void send_via_socket(const ImuData& data)
    {
        if (socket_fd_ < 0)
        {
            RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 5000,
                "Socket not initialized, skipping IMU message");
            return;
        }

        ssize_t sent = sendto(socket_fd_, &data, sizeof(data), MSG_NOSIGNAL,
                              (struct sockaddr*)&dest_addr_, sizeof(dest_addr_));
        if (sent < 0)
        {
            RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 5000,
                "Failed to send datagram: %s", strerror(errno));
        }
    }

    void log_diagnostics(int64_t ros_now_ns, int64_t imu_time_ns)
    {
        const int64_t final_delta_us = (ros_now_ns - imu_time_ns) / 1000;

        RCLCPP_INFO(get_logger(),
            "TimeSync verify: source=%s ros_now=%lld imu_time=%lld systematic_delta=%lld us final_delta=%lld us (%.1f ms) %s",
            clock_.is_using_fallback() ? "fallback" : "timesync",
            static_cast<long long>(ros_now_ns),
            static_cast<long long>(imu_time_ns),
            static_cast<long long>(clock_.systematic_delta_ns() / 1000),
            static_cast<long long>(final_delta_us),
            final_delta_us / 1000.0,
            (final_delta_us < 0) ? "[FAIL: ros_now < imu_time]" : "[OK]");

        if (final_delta_us < 0)
        {
            RCLCPP_WARN(get_logger(),
                "Time sync error: ros_now is BEHIND imu_time by %lld us",
                static_cast<long long>(-final_delta_us));
        }
    }

    // 成员变量
    ClockAlignment clock_;

    std::string socket_path_;
    int socket_fd_;
    struct sockaddr_un dest_addr_;

    std::string output_mode_;
    std::string output_topic_;
    int log_interval_;
    uint64_t msg_count_;

    rclcpp::Subscription<px4_msgs::msg::TimesyncStatus>::SharedPtr timesync_subscription_;
    rclcpp::Subscription<px4_msgs::msg::HighresImu>::SharedPtr imu_subscription_;
    rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr imu_publisher_;
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ImuSender>());
    rclcpp::shutdown();
    return 0;
}
