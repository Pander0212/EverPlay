#include "SdlAudio.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#define STB_VORBIS_NO_STDIO
#include "../../third_party/stb/stb_vorbis.c"
#undef L
#undef C
#undef R

#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#include "../../third_party/dr_libs/dr_mp3.h"

#define DR_WAV_IMPLEMENTATION
#define DR_WAV_NO_STDIO
#include "../../third_party/dr_libs/dr_wav.h"

#define TSF_IMPLEMENTATION
#include "../../third_party/tinysoundfont/tsf.h"
#define TML_IMPLEMENTATION
#include "../../third_party/tinysoundfont/tml.h"

namespace wolf {

namespace {

std::string extOf(const std::string& name) {
    size_t dot = name.find_last_of('.');
    std::string e = dot == std::string::npos ? std::string() : name.substr(dot + 1);
    for (auto& c : e) c = char(std::tolower(static_cast<unsigned char>(c)));
    return e;
}

class VorbisDecoder : public Decoder {
public:
    explicit VorbisDecoder(std::shared_ptr<std::vector<uint8_t>> d) : data_(std::move(d)) {
        int err = 0;
        v_ = stb_vorbis_open_memory(data_->data(), int(data_->size()), &err, nullptr);
        if (v_) {
            info_ = stb_vorbis_get_info(v_);
            length_ = stb_vorbis_stream_length_in_samples(v_);
        }
    }
    ~VorbisDecoder() override { if (v_) stb_vorbis_close(v_); }
    bool ok() const { return v_ != nullptr; }
    int sampleRate() const override { return int(info_.sample_rate); }
    int read(float* out, int frames) override {
        int n = stb_vorbis_get_samples_float_interleaved(v_, 2, out, frames * 2);
        if (info_.channels == 1) {
            // stb duplicates mono into both channels already.
        }
        return n;
    }
    bool seekFrame(uint64_t frame) override { return stb_vorbis_seek(v_, unsigned(frame)) != 0; }
    uint64_t lengthFrames() const override { return length_; }

private:
    std::shared_ptr<std::vector<uint8_t>> data_;
    stb_vorbis* v_ = nullptr;
    stb_vorbis_info info_{};
    uint64_t length_ = 0;
};

class Mp3Decoder : public Decoder {
public:
    explicit Mp3Decoder(std::shared_ptr<std::vector<uint8_t>> d) : data_(std::move(d)) {
        ok_ = drmp3_init_memory(&mp3_, data_->data(), data_->size(), nullptr);
        if (ok_) length_ = drmp3_get_pcm_frame_count(&mp3_), drmp3_seek_to_pcm_frame(&mp3_, 0);
    }
    ~Mp3Decoder() override { if (ok_) drmp3_uninit(&mp3_); }
    bool ok() const { return ok_; }
    int sampleRate() const override { return int(mp3_.sampleRate); }
    int read(float* out, int frames) override {
        if (mp3_.channels == 2) return int(drmp3_read_pcm_frames_f32(&mp3_, drmp3_uint64(frames), out));
        tmp_.resize(size_t(frames) * mp3_.channels);
        int n = int(drmp3_read_pcm_frames_f32(&mp3_, drmp3_uint64(frames), tmp_.data()));
        for (int i = 0; i < n; i++) out[i * 2] = out[i * 2 + 1] = tmp_[size_t(i) * mp3_.channels];
        return n;
    }
    bool seekFrame(uint64_t frame) override { return drmp3_seek_to_pcm_frame(&mp3_, frame); }
    uint64_t lengthFrames() const override { return length_; }

private:
    std::shared_ptr<std::vector<uint8_t>> data_;
    drmp3 mp3_{};
    bool ok_ = false;
    uint64_t length_ = 0;
    std::vector<float> tmp_;
};

class WavDecoder : public Decoder {
public:
    explicit WavDecoder(std::shared_ptr<std::vector<uint8_t>> d) : data_(std::move(d)) {
        ok_ = drwav_init_memory(&wav_, data_->data(), data_->size(), nullptr);
    }
    ~WavDecoder() override { if (ok_) drwav_uninit(&wav_); }
    bool ok() const { return ok_; }
    int sampleRate() const override { return int(wav_.sampleRate); }
    int read(float* out, int frames) override {
        int ch = wav_.channels;
        if (ch == 2) return int(drwav_read_pcm_frames_f32(&wav_, drwav_uint64(frames), out));
        tmp_.resize(size_t(frames) * size_t(ch));
        int n = int(drwav_read_pcm_frames_f32(&wav_, drwav_uint64(frames), tmp_.data()));
        for (int i = 0; i < n; i++) {
            out[i * 2] = tmp_[size_t(i * ch)];
            out[i * 2 + 1] = tmp_[size_t(i * ch + (ch > 1 ? 1 : 0))];
        }
        return n;
    }
    bool seekFrame(uint64_t frame) override { return drwav_seek_to_pcm_frame(&wav_, frame); }
    uint64_t lengthFrames() const override { return wav_.totalPCMFrameCount; }

private:
    std::shared_ptr<std::vector<uint8_t>> data_;
    drwav wav_{};
    bool ok_ = false;
    std::vector<float> tmp_;
};

class MidiDecoder : public Decoder {
public:
    MidiDecoder(const std::vector<uint8_t>& data, const std::string& soundFont) {
        static std::shared_ptr<tsf> base;
        static std::string basePath;
        if (!base || basePath != soundFont) {
            tsf* t = tsf_load_filename(soundFont.c_str());
            if (!t) return;
            base = std::shared_ptr<tsf>(t, tsf_close);
            basePath = soundFont;
        }
        sf_ = tsf_copy(base.get());
        if (!sf_) return;
        tsf_set_output(sf_, TSF_STEREO_INTERLEAVED, 44100, 0.0f);
        tsf_channel_set_bank_preset(sf_, 9, 128, 0);
        midi_ = tml_load_memory(data.data(), int(data.size()));
        cur_ = midi_;
        if (midi_) {
            unsigned int length = 0;
            tml_get_info(midi_, nullptr, nullptr, nullptr, nullptr, &length);
            lengthMs_ = length;
        }
    }
    ~MidiDecoder() override {
        if (midi_) tml_free(midi_);
        if (sf_) tsf_close(sf_);
    }
    bool ok() const { return sf_ && midi_; }
    int sampleRate() const override { return 44100; }
    int read(float* out, int frames) override {
        if (!cur_ && tsf_active_voice_count(sf_) == 0) return 0;
        int done = 0;
        while (done < frames) {
            int block = std::min(64, frames - done);
            msec_ += block * (1000.0 / 44100.0);
            while (cur_ && msec_ >= cur_->time) {
                switch (cur_->type) {
                    case TML_PROGRAM_CHANGE: tsf_channel_set_presetnumber(sf_, cur_->channel, cur_->program, cur_->channel == 9); break;
                    case TML_NOTE_ON: tsf_channel_note_on(sf_, cur_->channel, cur_->key, cur_->velocity / 127.0f); break;
                    case TML_NOTE_OFF: tsf_channel_note_off(sf_, cur_->channel, cur_->key); break;
                    case TML_PITCH_BEND: tsf_channel_set_pitchwheel(sf_, cur_->channel, cur_->pitch_bend); break;
                    case TML_CONTROL_CHANGE: tsf_channel_midi_control(sf_, cur_->channel, cur_->control, cur_->control_value); break;
                }
                cur_ = cur_->next;
            }
            tsf_render_float(sf_, out + done * 2, block, 0);
            done += block;
            if (!cur_ && tsf_active_voice_count(sf_) == 0) break;
        }
        return done;
    }
    bool seekFrame(uint64_t frame) override {
        tsf_reset(sf_);
        tsf_channel_set_bank_preset(sf_, 9, 128, 0);
        cur_ = midi_;
        msec_ = 0;
        double target = frame * 1000.0 / 44100.0;
        // Replay the controller state up to the target, without notes.
        while (cur_ && cur_->time < target) {
            switch (cur_->type) {
                case TML_PROGRAM_CHANGE: tsf_channel_set_presetnumber(sf_, cur_->channel, cur_->program, cur_->channel == 9); break;
                case TML_PITCH_BEND: tsf_channel_set_pitchwheel(sf_, cur_->channel, cur_->pitch_bend); break;
                case TML_CONTROL_CHANGE: tsf_channel_midi_control(sf_, cur_->channel, cur_->control, cur_->control_value); break;
            }
            cur_ = cur_->next;
        }
        msec_ = target;
        return true;
    }
    uint64_t lengthFrames() const override { return uint64_t(lengthMs_) * 44100 / 1000; }

private:
    tsf* sf_ = nullptr;
    tml_message* midi_ = nullptr;
    tml_message* cur_ = nullptr;
    double msec_ = 0;
    unsigned lengthMs_ = 0;
};

}  // namespace

std::unique_ptr<Decoder> openDecoder(const std::string& name, std::shared_ptr<std::vector<uint8_t>> data,
                                     const std::string& soundFont) {
    std::string ext = extOf(name);
    const auto& d = *data;
    bool isOgg = d.size() > 4 && std::memcmp(d.data(), "OggS", 4) == 0;
    bool isWav = d.size() > 12 && std::memcmp(d.data(), "RIFF", 4) == 0 && std::memcmp(d.data() + 8, "WAVE", 4) == 0;
    bool isMidi = d.size() > 4 && std::memcmp(d.data(), "MThd", 4) == 0;
    if (isOgg || ext == "ogg") {
        auto v = std::make_unique<VorbisDecoder>(data);
        if (v->ok()) return v;
    }
    if (isWav || ext == "wav") {
        auto v = std::make_unique<WavDecoder>(data);
        if (v->ok()) return v;
    }
    if (isMidi || ext == "mid" || ext == "midi") {
        if (soundFont.empty()) return nullptr;
        auto v = std::make_unique<MidiDecoder>(*data, soundFont);
        if (v->ok()) return v;
        return nullptr;
    }
    auto v = std::make_unique<Mp3Decoder>(data);
    if (v->ok()) return v;
    return nullptr;
}

SdlAudio::SdlAudio(std::string soundFont) : soundFont_(std::move(soundFont)) {
    if (!(SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO)) SDL_InitSubSystem(SDL_INIT_AUDIO);
    SDL_AudioSpec want{}, have{};
    want.freq = 44100;
    want.format = AUDIO_F32SYS;
    want.channels = 2;
    want.samples = 1024;
    want.callback = &SdlAudio::callback;
    want.userdata = this;
    device_ = SDL_OpenAudioDevice(nullptr, 0, &want, &have, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
    if (device_) {
        rate_ = have.freq;
        SDL_PauseAudioDevice(device_, 0);
    }
}

SdlAudio::~SdlAudio() {
    if (device_) SDL_CloseAudioDevice(device_);
}

void SdlAudio::pause(bool paused) {
    if (device_) SDL_PauseAudioDevice(device_, paused ? 1 : 0);
}

void SdlAudio::play(Channel ch, const std::string& name, const std::vector<uint8_t>& data, int volume, int pitch,
                    int startMs, int loopMs, int fadeMs) {
    auto shared = std::make_shared<std::vector<uint8_t>>(data);
    auto dec = openDecoder(name, shared, soundFont_);
    if (!dec) return;
    auto v = std::make_unique<Voice>();
    v->ch = ch;
    v->volume = std::clamp(volume, 0, 500) / 100.0;
    int srcRate = std::max(dec->sampleRate(), 1);
    v->rate = double(srcRate) / rate_ * std::clamp(pitch, 10, 400) / 100.0;
    v->loop = ch != Channel::SE;
    v->loopFrame = uint64_t(std::max(loopMs, 0)) * uint64_t(srcRate) / 1000;
    if (startMs > 0) {
        dec->seekFrame(uint64_t(startMs) * uint64_t(srcRate) / 1000);
        v->played = uint64_t(startMs) * uint64_t(srcRate) / 1000;
    }
    v->dec = std::move(dec);
    if (fadeMs > 0) {
        v->fade = 0;
        v->fadeStep = 1.0 / (fadeMs * rate_ / 1000.0);
    }
    std::lock_guard<std::mutex> guard(lock_);
    if (ch != Channel::SE) {
        // The previous music fades out quickly or stops.
        for (auto& o : voices_)
            if (o->ch == ch && !o->stopAtFadeOut) {
                o->stopAtFadeOut = true;
                o->fadeStep = -1.0 / (std::max(fadeMs, 1) * rate_ / 1000.0);
            }
    } else {
        int count = 0;
        for (auto& o : voices_) if (o->ch == Channel::SE) count++;
        if (count >= 24) {
            for (auto it = voices_.begin(); it != voices_.end(); ++it)
                if ((*it)->ch == Channel::SE) { voices_.erase(it); break; }
        }
    }
    voices_.push_back(std::move(v));
}

void SdlAudio::stop(Channel ch, int fadeMs) {
    std::lock_guard<std::mutex> guard(lock_);
    for (auto& v : voices_) {
        if (v->ch != ch) continue;
        v->stopAtFadeOut = true;
        v->fadeStep = fadeMs > 0 ? -1.0 / (fadeMs * rate_ / 1000.0) : -1.0;
    }
}

int SdlAudio::positionMs(Channel ch) {
    std::lock_guard<std::mutex> guard(lock_);
    for (auto it = voices_.rbegin(); it != voices_.rend(); ++it)
        if ((*it)->ch == ch && !(*it)->stopAtFadeOut)
            return int((*it)->played * 1000 / uint64_t(std::max((*it)->dec->sampleRate(), 1)));
    return 0;
}

int SdlAudio::lengthMs(Channel ch) {
    std::lock_guard<std::mutex> guard(lock_);
    for (auto it = voices_.rbegin(); it != voices_.rend(); ++it)
        if ((*it)->ch == ch && !(*it)->stopAtFadeOut)
            return int((*it)->dec->lengthFrames() * 1000 / uint64_t(std::max((*it)->dec->sampleRate(), 1)));
    return -1;
}

void SdlAudio::setMasterVolume(Channel ch, int percent) {
    master_[int(ch)] = std::clamp(percent, 0, 200) / 100.0;
}

void SdlAudio::callback(void* self, Uint8* stream, int len) {
    auto* a = static_cast<SdlAudio*>(self);
    int frames = len / int(sizeof(float) * 2);
    a->mix(reinterpret_cast<float*>(stream), frames);
}

bool SdlAudio::nextFrame(Voice& v, float* frame) {
    if (v.bufIndex >= v.bufFrames) {
        v.buf.resize(2048 * 2);
        int n = v.dec->read(v.buf.data(), 2048);
        if (n <= 0) {
            if (v.loop) {
                v.dec->seekFrame(v.loopFrame);
                v.played = v.loopFrame;
                n = v.dec->read(v.buf.data(), 2048);
            }
            if (n <= 0) return false;
        }
        v.bufFrames = size_t(n);
        v.bufIndex = 0;
    }
    frame[0] = v.buf[v.bufIndex * 2];
    frame[1] = v.buf[v.bufIndex * 2 + 1];
    v.bufIndex++;
    v.played++;
    return true;
}

void SdlAudio::mix(float* out, int frames) {
    std::memset(out, 0, size_t(frames) * 2 * sizeof(float));
    std::lock_guard<std::mutex> guard(lock_);
    for (auto& vp : voices_) {
        Voice& v = *vp;
        if (v.ended) continue;
        if (!v.primed) {
            if (!nextFrame(v, v.prev) || !nextFrame(v, v.next)) { v.ended = true; continue; }
            v.primed = true;
        }
        double gain = v.volume * master_[int(v.ch)];
        for (int i = 0; i < frames; i++) {
            float l = float(v.prev[0] + (v.next[0] - v.prev[0]) * v.pos);
            float r = float(v.prev[1] + (v.next[1] - v.prev[1]) * v.pos);
            double g = gain * v.fade;
            out[i * 2] += float(l * g);
            out[i * 2 + 1] += float(r * g);
            if (v.fadeStep != 0) {
                v.fade = std::clamp(v.fade + v.fadeStep, 0.0, 1.0);
                if (v.fade >= 1.0 && v.fadeStep > 0) v.fadeStep = 0;
                if (v.fade <= 0.0 && v.stopAtFadeOut) { v.ended = true; break; }
            }
            v.pos += v.rate;
            while (v.pos >= 1.0) {
                v.pos -= 1.0;
                v.prev[0] = v.next[0];
                v.prev[1] = v.next[1];
                if (!nextFrame(v, v.next)) { v.ended = true; break; }
            }
            if (v.ended) break;
        }
    }
    voices_.erase(std::remove_if(voices_.begin(), voices_.end(), [](const auto& v) { return v->ended; }), voices_.end());
    for (int i = 0; i < frames * 2; i++) out[i] = std::clamp(out[i], -1.0f, 1.0f);
}

}  // namespace wolf
