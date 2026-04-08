#include <cstring>
#include <string>

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
      client_fd_(-1)
    {
        pnh_.param<std::string>("socket_path", socket_path_, kDefaultSocketPath);
        pnh_.param<std::string>("publish_topic", publish_topic_, kDefaultPublishTopic);

        imu_pub_ = nh_.advertise<sensor_msgs::Imu>(publish_topic_, 100);

        setup_socket();

        ROS_INFO("IMU receiver ready");
        ROS_INFO("  Socket: %s", socket_path_.c_str());
        ROS_INFO("  Topic:  %s", publish_topic_.c_str());
    }

    ~ImuReceiver()
    {
        if (client_fd_ >= 0)
        {
            close(client_fd_);
        }
        if (server_fd_ >= 0)
        {
            close(server_fd_);
        }
        unlink(socket_path_.c_str());
    }

    void spin()
    {
        ros::Rate rate(1000);  // 1kHz polling

        while (ros::ok())
        {
            if (client_fd_ < 0)
            {
                accept_client();
            }
            else
            {
                receive_data();
            }

            ros::spinOnce();
            rate.sleep();
        }
    }

private:
    void setup_socket()
    {
        // Remove existing socket file
        unlink(socket_path_.c_str());

        server_fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
        if (server_fd_ < 0)
        {
            ROS_ERROR("Failed to create server socket: %s", strerror(errno));
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
            ROS_ERROR("Failed to bind socket: %s", strerror(errno));
            close(server_fd_);
            server_fd_ = -1;
            return;
        }

        if (listen(server_fd_, 1) < 0)
        {
            ROS_ERROR("Failed to listen on socket: %s", strerror(errno));
            close(server_fd_);
            server_fd_ = -1;
            return;
        }

        ROS_INFO("Unix socket server listening");
    }

    void accept_client()
    {
        if (server_fd_ < 0)
        {
            return;
        }

        client_fd_ = accept(server_fd_, nullptr, nullptr);
        if (client_fd_ >= 0)
        {
            ROS_INFO("Client connected");

            // Set non-blocking
            int flags = fcntl(client_fd_, F_GETFL, 0);
            fcntl(client_fd_, F_SETFL, flags | O_NONBLOCK);
        }
    }

    void receive_data()
    {
        ImuData data;
        ssize_t received = recv(client_fd_, &data, sizeof(data), 0);

        if (received == sizeof(data))
        {
            publish_imu(data);
        }
        else if (received == 0)
        {
            ROS_INFO("Client disconnected");
            close(client_fd_);
            client_fd_ = -1;
        }
        else if (received < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
        {
            ROS_WARN("Receive error: %s", strerror(errno));
            close(client_fd_);
            client_fd_ = -1;
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
    int client_fd_;
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
