// Audio with SDL2's audio device and a small mixer: BGM, BGS and sound effects from OGG, MP3,
// WAV and MIDI (TinySoundFont with EverPlay's SoundFont).
#pragma once

#include <SDL.h>

#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "../engine/Platform.hpp"

namespace wolf {

class Decoder {
public:
    virtual ~Decoder() = default;
    virtual int sampleRate() const = 0;
    // Reads interleaved stereo float frames; returns how many were read (0 at the end).
    virtual int read(float* out, int frames) = 0;
    virtual bool seekFrame(uint64_t frame) = 0;
    virtual uint64_t lengthFrames() const = 0;  // 0 if unknown
};

std::unique_ptr<Decoder> openDecoder(const std::string& name, std::shared_ptr<std::vector<uint8_t>> data,
                                     const std::string& soundFont);

class SdlAudio : public Audio {
public:
    explicit SdlAudio(std::string soundFont);
    ~SdlAudio() override;
    bool ok() const { return device_ != 0; }

    void play(Channel ch, const std::string& name, const std::vector<uint8_t>& data, int volume, int pitch, int startMs,
              int loopMs, int fadeMs) override;
    void stop(Channel ch, int fadeMs) override;
    int positionMs(Channel ch) override;
    int lengthMs(Channel ch) override;
    void setMasterVolume(Channel ch, int percent) override;
    void pause(bool paused);

private:
    struct Voice {
        std::unique_ptr<Decoder> dec;
        Channel ch;
        double volume = 1, fade = 1, fadeStep = 0;  // fade: 0..1 multiplier, fadeStep per output frame
        bool stopAtFadeOut = false;
        double rate = 1;        // source frames per output frame
        double pos = 0;         // fractional position between buf frames
        std::vector<float> buf; // decoded frames (stereo)
        size_t bufFrames = 0, bufIndex = 0;
        uint64_t played = 0;    // source frames consumed
        uint64_t loopFrame = 0;
        bool loop = false;
        bool ended = false;
        float prev[2] = {0, 0}, next[2] = {0, 0};
        bool primed = false;
    };
    static void callback(void* self, Uint8* stream, int len);
    void mix(float* out, int frames);
    bool nextFrame(Voice& v, float* frame);

    SDL_AudioDeviceID device_ = 0;
    int rate_ = 44100;
    std::mutex lock_;
    std::vector<std::unique_ptr<Voice>> voices_;
    std::string soundFont_;
    double master_[3] = {1, 1, 1};
};

}  // namespace wolf
