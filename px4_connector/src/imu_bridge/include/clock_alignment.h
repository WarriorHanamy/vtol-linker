#ifndef CLOCK_ALIGNMENT_H
#define CLOCK_ALIGNMENT_H

#include <cstdint>
#include <cstddef>

class ClockAlignment
{
public:
    ClockAlignment()
    : has_offset_(false),
      using_fallback_offset_(false),
      has_systematic_delta_(false),
      smoothed_offset_us_(0),
      systematic_delta_ns_(0),
      systematic_delta_sample_count_(0),
      systematic_delta_sum_ns_(0)
    {}

    // 接收 PX4 TimesyncStatus 的 offset (单位: 微秒)
    void update_timesync_offset(int64_t estimated_offset_us)
    {
        smoothed_offset_us_ = estimated_offset_us;
        has_offset_ = true;

        if (using_fallback_offset_)
        {
            using_fallback_offset_ = false;
            reset_systematic_delta("TimesyncStatus received, restarting systematic delta calibration");
        }
    }

    // 用首条 IMU 消息初始化 fallback offset
    void init_fallback_offset(int64_t timestamp_sample_us, int64_t ros_now_ns)
    {
        smoothed_offset_us_ = ros_now_ns / 1000 - timestamp_sample_us;
        has_offset_ = true;
        using_fallback_offset_ = true;
        reset_systematic_delta(nullptr);
    }

    // 对齐时间戳
    // 参数:
    //   timestamp_sample_us: PX4 timestamp_sample (微秒)
    //   ros_now_ns: 当前 ROS 时间 (纳秒)
    // 返回:
    //   Result{ros_time_ns, ready} - ready=false 表示仍在校准，调用方应跳过此帧
    struct Result
    {
        int64_t ros_time_ns;  // 对齐后的 ROS 时间戳 (纳秒)
        bool ready;           // false = 仍在校准采集中
    };

    Result align(int64_t timestamp_sample_us, int64_t ros_now_ns)
    {
        // 基础时间转换: (timestamp_sample + offset_us) * 1000
        const int64_t imu_ros_time_ns = (timestamp_sample_us + smoothed_offset_us_) * 1000;

        // 如果还没有系统偏差，进行采集
        if (!has_systematic_delta_)
        {
            if (systematic_delta_sample_count_ == 0)
            {
                // 首次进入校准，无需日志 (由调用方输出)
            }

            const int64_t delta_ns = ros_now_ns - imu_ros_time_ns;
            systematic_delta_sum_ns_ += static_cast<__int128>(delta_ns);
            systematic_delta_sample_count_++;

            if (systematic_delta_sample_count_ >= kSystematicDeltaSampleCount)
            {
                systematic_delta_ns_ = static_cast<int64_t>(
                    systematic_delta_sum_ns_ / systematic_delta_sample_count_);
                has_systematic_delta_ = true;
            }

            return {0, false};  // 尚未完成校准
        }

        // 校准完成，计算最终时间
        const int64_t final_imu_time_ns = imu_ros_time_ns + systematic_delta_ns_;

        // 安全检查: 非正时间跳过
        if (final_imu_time_ns <= 0)
        {
            return {0, false};
        }

        return {final_imu_time_ns, true};
    }

    // 诊断接口
    bool is_using_fallback() const { return using_fallback_offset_; }
    int64_t systematic_delta_ns() const { return systematic_delta_ns_; }
    int samples_collected() const { return systematic_delta_sample_count_; }
    bool has_systematic_delta() const { return has_systematic_delta_; }
    bool has_offset() const { return has_offset_; }

    // 重置系统偏差 (用于从 fallback 切换到 timesync 时)
    void reset_systematic_delta(const char* reason = nullptr)
    {
        has_systematic_delta_ = false;
        systematic_delta_ns_ = 0;
        systematic_delta_sample_count_ = 0;
        systematic_delta_sum_ns_ = 0;
        (void)reason;  // 本类不负责日志，reason 仅用于兼容
    }

private:
    static constexpr int kSystematicDeltaSampleCount = 100;

    bool has_offset_;                   // 是否已获得 offset (Timesync 或 fallback)
    bool using_fallback_offset_;        // 是否正在使用 fallback offset
    bool has_systematic_delta_;         // 是否已完成 systematic delta 校准

    int64_t smoothed_offset_us_;        // offset (微秒)
    int64_t systematic_delta_ns_;       // systematic delta (纳秒)
    int systematic_delta_sample_count_; // 已收集的样本数
    __int128 systematic_delta_sum_ns_;  // delta 总和 (使用 __int128 防止溢出)
};

#endif  // CLOCK_ALIGNMENT_H
