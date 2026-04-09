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
constexpr int kSystematicDeltaSampleCount = 100;

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
      smoothed_offset_us_(0),
      has_offset_(false),
      using_fallback_offset_(false),
      has_systematic_delta_(false),
      systematic_delta_ns_(0),
      systematic_delta_sample_count_(0),
      systematic_delta_sum_ns_(0),
      msg_count_(0)
    {
        socket_path_ = declare_parameter<std::string>("socket_path", kSocketPath);
        log_interval_ = declare_parameter<int>("log_interval", 1000);

        setup_socket();

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
        RCLCPP_INFO(get_logger(), "Sending via Unix datagram to: %s", socket_path_.c_str());
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

        if (using_fallback_offset_)
        {
            using_fallback_offset_ = false;
            reset_systematic_delta(
                "TimesyncStatus received, restarting 100-sample systematic delta calibration");
        }

        RCLCPP_DEBUG(get_logger(),
            "TimesyncStatus: offset=%ld us, RTT=%u us, protocol=%u",
            msg->estimated_offset,
            msg->round_trip_time,
            msg->source_protocol);
    }

    void reset_systematic_delta(const char* reason)
    {
        has_systematic_delta_ = false;
        systematic_delta_ns_ = 0;
        systematic_delta_sample_count_ = 0;
        systematic_delta_sum_ns_ = 0;

        if (reason != nullptr)
        {
            RCLCPP_INFO(get_logger(), "%s", reason);
        }
    }

    void setup_socket()
    {
        socket_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (socket_fd_ < 0)
        {
            RCLCPP_ERROR(get_logger(), "Failed to create datagram socket: %s", strerror(errno));
            return;
        }

        // Prepare destination address (receiver's socket path)
        memset(&dest_addr_, 0, sizeof(dest_addr_));
        dest_addr_.sun_family = AF_UNIX;
        strncpy(dest_addr_.sun_path, socket_path_.c_str(), sizeof(dest_addr_.sun_path) - 1);

        RCLCPP_INFO(get_logger(), "Datagram socket created, sending to %s", socket_path_.c_str());
    }

    void imu_callback(const px4_msgs::msg::HighresImu::SharedPtr msg)
    {
        if (!has_offset_)
        {
            RCLCPP_WARN_ONCE(get_logger(),
                "TimesyncStatus not received yet, using static offset from first IMU message");

            const int64_t first_ros_time_ns = now().nanoseconds();
            smoothed_offset_us_ = first_ros_time_ns / 1000 - static_cast<int64_t>(msg->timestamp_sample);
            has_offset_ = true;
            using_fallback_offset_ = true;
            reset_systematic_delta(nullptr);

            RCLCPP_INFO(get_logger(),
                "Static offset initialized: %lld ns (%.3f s)",
                static_cast<long long>(smoothed_offset_us_ * 1000),
                smoothed_offset_us_ / 1e6);
        }

        const int64_t ros_now_ns = now().nanoseconds();
        const int64_t imu_ros_time_ns =
            (static_cast<int64_t>(msg->timestamp_sample) + smoothed_offset_us_) * 1000;

        if (!has_systematic_delta_)
        {
            if (systematic_delta_sample_count_ == 0)
            {
                RCLCPP_INFO(get_logger(),
                    "Collecting %d IMU samples to estimate systematic delta",
                    kSystematicDeltaSampleCount);
            }

            const int64_t delta_ns = ros_now_ns - imu_ros_time_ns;
            systematic_delta_sum_ns_ += static_cast<__int128>(delta_ns);
            systematic_delta_sample_count_++;

            if (systematic_delta_sample_count_ >= kSystematicDeltaSampleCount)
            {
                systematic_delta_ns_ = static_cast<int64_t>(
                    systematic_delta_sum_ns_ / systematic_delta_sample_count_);
                has_systematic_delta_ = true;
                RCLCPP_INFO(get_logger(),
                    "Systematic delta computed from %d IMU samples: %lld ns (%.3f ms)",
                    systematic_delta_sample_count_,
                    static_cast<long long>(systematic_delta_ns_),
                    systematic_delta_ns_ / 1e6);
            }

            return;
        }

        const int64_t final_imu_time_ns = imu_ros_time_ns + systematic_delta_ns_;
        if (final_imu_time_ns <= 0)
        {
            RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 5000,
                "Converted IMU timestamp is non-positive after ROS clock alignment: %lld ns",
                static_cast<long long>(final_imu_time_ns));
            return;
        }

        ImuData data;
        data.timestamp = static_cast<uint64_t>(final_imu_time_ns);
        data.accel[0] = msg->accel[0];
        data.accel[1] = msg->accel[1];
        data.accel[2] = msg->accel[2];
        data.gyro[0] = msg->gyro[0];
        data.gyro[1] = msg->gyro[1];
        data.gyro[2] = msg->gyro[2];

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

        // Diagnostic verification after ROS clock alignment
        msg_count_++;
        if (msg_count_ % log_interval_ == 0)
        {
            const int64_t verify_ros_now_ns = now().nanoseconds();
            const int64_t final_delta_us = (verify_ros_now_ns - final_imu_time_ns) / 1000;

            RCLCPP_INFO(get_logger(),
                "TimeSync verify: source=%s ros_now=%lld imu_time=%lld systematic_delta=%lld us final_delta=%lld us (%.1f ms) %s",
                using_fallback_offset_ ? "fallback" : "timesync",
                static_cast<long long>(verify_ros_now_ns),
                static_cast<long long>(final_imu_time_ns),
                static_cast<long long>(systematic_delta_ns_ / 1000),
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
    }

    std::string socket_path_;
    int socket_fd_;
    struct sockaddr_un dest_addr_;      // Receiver address for sendto()
    int64_t smoothed_offset_us_;        // PX4 estimated offset (microseconds)
    bool has_offset_;                   // true once TimesyncStatus received or fallback computed
    bool using_fallback_offset_;        // true while using first-sample fallback offset
    bool has_systematic_delta_;         // true once the 100-sample systematic delta is ready
    int64_t systematic_delta_ns_;       // average residual delta after converting PX4 time to ROS time
    int systematic_delta_sample_count_; // number of IMU samples collected for systematic delta
    __int128 systematic_delta_sum_ns_;  // sum of residual deltas across initial IMU samples
    uint64_t msg_count_;                // for periodic diagnostics
    int log_interval_;                  // diagnostic print interval

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
