#include <cstring>
#include <string>
#include <deque>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <atomic>
#include <chrono>

#include <ros/ros.h>
#include <sensor_msgs/Imu.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

namespace
{

constexpr const char* kDefaultSocketPath = "/tmp/imu_bridge.sock";
constexpr const char* kDefaultPublishTopic = "/mavros/imu/data_raw";

struct ImuData
{
    uint64_t timestamp;  // nanoseconds (ROS time, with offset applied)
    float accel[3];      // m/s^2 (FLU frame)
    float gyro[3];       // rad/s (FLU frame)
};

}  // namespace

class ImuReceiver
{
public:
    ImuReceiver(ros::NodeHandle& nh, ros::NodeHandle& pnh)
    : nh_(nh),
      pnh_(pnh),
      server_fd_(-1),
      running_(true),
      buffer_max_size_(2000),  // ~2 seconds at 1kHz
      msg_received_(0),
      msg_published_(0)
    {
        pnh_.param<std::string>("socket_path", socket_path_, kDefaultSocketPath);
        pnh_.param<std::string>("publish_topic", publish_topic_, kDefaultPublishTopic);

        imu_pub_ = nh_.advertise<sensor_msgs::Imu>(publish_topic_, 100);

        setup_socket();

        // Start receiver and publisher threads
        receiver_thread_ = std::thread(&ImuReceiver::receiver_loop, this);
        publisher_thread_ = std::thread(&ImuReceiver::publisher_loop, this);

        ROS_INFO("IMU receiver ready (DGRAM mode with ring buffer)");
        ROS_INFO("  Socket: %s", socket_path_.c_str());
        ROS_INFO("  Topic:  %s", publish_topic_.c_str());
        ROS_INFO("  Buffer: max %d messages", buffer_max_size_);
    }

    ~ImuReceiver()
    {
        running_ = false;

        if (receiver_thread_.joinable())
            receiver_thread_.join();
        if (publisher_thread_.joinable())
            publisher_thread_.join();

        if (server_fd_ >= 0)
        {
            close(server_fd_);
        }
        unlink(socket_path_.c_str());
    }

    void spin()
    {
        // Just wait for ROS shutdown; receiver/publisher threads run independently
        while (ros::ok())
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

private:
    void setup_socket()
    {
        // Remove existing socket file
        unlink(socket_path_.c_str());

        server_fd_ = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (server_fd_ < 0)
        {
            ROS_ERROR("Failed to create datagram socket: %s", strerror(errno));
            return;
        }

        // Set non-blocking
        int flags = fcntl(server_fd_, F_GETFL, 0);
        fcntl(server_fd_, F_SETFL, flags | O_NONBLOCK);

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path_.c_str(), sizeof(addr.sun_path) - 1);

        if (bind(server_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0)
        {
            ROS_ERROR("Failed to bind datagram socket: %s", strerror(errno));
            close(server_fd_);
            server_fd_ = -1;
            return;
        }

        ROS_INFO("Unix datagram socket bound and listening");
    }

    void receiver_loop()
    {
        while (running_ && ros::ok())
        {
            ImuData data;
            ssize_t received = recv(server_fd_, &data, sizeof(data), 0);

            if (received == sizeof(data))
            {
                std::lock_guard<std::mutex> lock(buffer_mutex_);
                if (imu_buffer_.size() >= buffer_max_size_)
                {
                    // Drop oldest to preserve recency
                    imu_buffer_.pop_front();
                }
                imu_buffer_.push_back(data);
                buffer_cv_.notify_one();
                msg_received_++;  // statistics
            }
            else if (received < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
            {
                ROS_WARN_THROTTLE(5.0, "Recv error: %s", strerror(errno));
            }

            std::this_thread::sleep_for(std::chrono::microseconds(100)); // ~10kHz poll
        }
    }

    void publisher_loop()
    {
        while (running_ && ros::ok())
        {
            ImuData data;
            bool has_data = false;

            {
                std::unique_lock<std::mutex> lock(buffer_mutex_);
                if (buffer_cv_.wait_for(lock, std::chrono::milliseconds(100),
                    [this](){ return !imu_buffer_.empty() || !running_; }))
                {
                    if (!imu_buffer_.empty())
                    {
                        data = imu_buffer_.front();
                        imu_buffer_.pop_front();
                        has_data = true;
                    }
                }
            }

            if (has_data)
            {
                publish_imu(data);
                msg_published_++;

                // Periodic statistics log every 5 seconds
                static auto last_log = std::chrono::steady_clock::now();
                auto now = std::chrono::steady_clock::now();
                if (now - last_log >= std::chrono::seconds(5))
                {
                    uint64_t received = msg_received_.load();
                    uint64_t published = msg_published_.load();
                    ROS_INFO("IMU bridge stats: received=%lu published=%lu dropped=%lu buffer=%zu",
                             received, published, received - published, imu_buffer_.size());
                    last_log = now;
                }
            }
        }
    }

    void publish_imu(const ImuData& data)
    {
        sensor_msgs::Imu msg;

        // Convert nanoseconds to ROS time
        msg.header.stamp.sec = static_cast<int32_t>(data.timestamp / 1000000000ULL);
        msg.header.stamp.nsec = static_cast<int32_t>(data.timestamp % 1000000000ULL);
        msg.header.frame_id = "imu_link";

        // Linear acceleration (FLU frame, no conversion needed)
        msg.linear_acceleration.x = data.accel[0];
        msg.linear_acceleration.y = data.accel[1];
        msg.linear_acceleration.z = data.accel[2];

        // Angular velocity (FLU frame, no conversion needed)
        msg.angular_velocity.x = data.gyro[0];
        msg.angular_velocity.y = data.gyro[1];
        msg.angular_velocity.z = data.gyro[2];

        // Orientation unknown
        msg.orientation_covariance[0] = -1;

        // Linear acceleration covariance (typical IMU)
        msg.linear_acceleration_covariance[0] = 0.01;
        msg.linear_acceleration_covariance[4] = 0.01;
        msg.linear_acceleration_covariance[8] = 0.01;

        // Angular velocity covariance (typical IMU)
        msg.angular_velocity_covariance[0] = 0.0001;
        msg.angular_velocity_covariance[4] = 0.0001;
        msg.angular_velocity_covariance[8] = 0.0001;

        imu_pub_.publish(msg);
    }

    ros::NodeHandle& nh_;
    ros::NodeHandle& pnh_;
    ros::Publisher imu_pub_;
    std::string socket_path_;
    std::string publish_topic_;
    int server_fd_;

    // Ring buffer and threading
    std::deque<ImuData> imu_buffer_;
    std::mutex buffer_mutex_;
    std::condition_variable buffer_cv_;
    std::thread receiver_thread_;
    std::thread publisher_thread_;
    std::atomic<bool> running_;
    size_t buffer_max_size_;

    // Statistics
    std::atomic<uint64_t> msg_received_;
    std::atomic<uint64_t> msg_published_;
};

int main(int argc, char** argv)
{
    ros::init(argc, argv, "imu_receiver_node");

    ros::NodeHandle nh;
    ros::NodeHandle pnh("~");

    ImuReceiver receiver(nh, pnh);
    receiver.spin();

    return 0;
}
