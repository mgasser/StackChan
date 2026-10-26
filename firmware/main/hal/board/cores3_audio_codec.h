#ifndef _BOX_AUDIO_CODEC_H
#define _BOX_AUDIO_CODEC_H

#include "audio_codec.h"

#include <sdkconfig.h>
#include <esp_codec_dev.h>
#include <esp_codec_dev_defaults.h>

#include <atomic>
#include <cstdint>
#include <vector>

class CoreS3AudioCodec : public AudioCodec {
private:
    const audio_codec_data_if_t* data_if_ = nullptr;
    const audio_codec_ctrl_if_t* out_ctrl_if_ = nullptr;
    const audio_codec_if_t* out_codec_if_ = nullptr;
    const audio_codec_ctrl_if_t* in_ctrl_if_ = nullptr;
    const audio_codec_if_t* in_codec_if_ = nullptr;
    const audio_codec_gpio_if_t* gpio_if_ = nullptr;

    esp_codec_dev_handle_t output_dev_ = nullptr;
    esp_codec_dev_handle_t input_dev_ = nullptr;

    void CreateDuplexChannels(gpio_num_t mclk, gpio_num_t bclk, gpio_num_t ws, gpio_num_t dout, gpio_num_t din);

    // Full-duplex test build: every volume is capped (speaker next to the mics).
    static int CapVolume(int volume);

#if CONFIG_STACKCHAN_AEC_REF_4SLOT
    // 16-bit speaker samples widened for the 32-bit slots of the 4-slot layout.
    std::vector<int32_t> out32_;
#endif
#if CONFIG_STACKCHAN_AEC_LEVEL_LOG
    // Once a second: how loud the microphone and the echo reference were.
    int64_t level_sum_[2] = {0, 0};
    int level_peak_[2] = {0, 0};
    int level_frames_ = 0;
    int64_t level_last_us_ = 0;
    std::atomic<int> level_played_{0};  // speaker samples written since the last line
    void LogLevels(const int16_t* data, int samples);
#endif

    virtual int Read(int16_t* dest, int samples) override;
    virtual int Write(const int16_t* data, int samples) override;

public:
    CoreS3AudioCodec(void* i2c_master_handle, int input_sample_rate, int output_sample_rate,
        gpio_num_t mclk, gpio_num_t bclk, gpio_num_t ws, gpio_num_t dout, gpio_num_t din,
        uint8_t aw88298_addr, uint8_t es7210_addr, bool input_reference);
    virtual ~CoreS3AudioCodec();

    virtual void SetOutputVolume(int volume) override;
    virtual void EnableInput(bool enable) override;
    virtual void EnableOutput(bool enable) override;
};

#endif // _BOX_AUDIO_CODEC_H
