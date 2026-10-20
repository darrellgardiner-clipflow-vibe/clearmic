#include "ClearMicAudio.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <new>

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr uint32_t maxFrames = 8192;
static_assert(std::atomic<float>::is_always_lock_free);
static_assert(std::atomic<uint64_t>::is_always_lock_free);
float amplitude(float db) { return std::pow(10.0f, db / 20.0f); }
float decibels(float value) { return 20.0f * std::log10(std::max(value, 0.000001f)); }
float bounded(float value, float low, float high, float fallback) {
    return std::isfinite(value) ? std::clamp(value, low, high) : fallback;
}

struct Biquad {
    std::array<double, 5> coefficients{1, 0, 0, 0, 0}, target{1, 0, 0, 0, 0}, increment{};
    double z1 = 0, z2 = 0;
    uint32_t remaining = 0;
    void set(double b0, double b1, double b2, double a1, double a2) {
        target = {b0, b1, b2, a1, a2};
        remaining = 240;
        for (size_t i = 0; i < target.size(); ++i) increment[i] = (target[i] - coefficients[i]) / remaining;
    }
    void snap() { coefficients = target; remaining = 0; }
    float process(float input) {
        if (remaining) {
            for (size_t i = 0; i < target.size(); ++i) coefficients[i] += increment[i];
            if (--remaining == 0) coefficients = target;
        }
        const double output = coefficients[0] * input + z1;
        z1 = coefficients[1] * input - coefficients[3] * output + z2;
        z2 = coefficients[2] * input - coefficients[4] * output;
        if (std::abs(z1) < 1e-25) z1 = 0;
        if (std::abs(z2) < 1e-25) z2 = 0;
        return static_cast<float>(output);
    }
    void highPass(double rate, float hz) {
        if (hz == 0) { set(1, 0, 0, 0, 0); return; }
        const double w = 2 * pi * hz / rate, c = std::cos(w), alpha = std::sin(w) / std::sqrt(2.0);
        const double a0 = 1 + alpha;
        const double b0 = (1 + c) / (2 * a0);
        set(b0, -(1 + c) / a0, b0, -2 * c / a0, (1 - alpha) / a0);
    }
    void bell(double rate, float hz, float gainDB, float q) {
        const double a = std::pow(10.0, gainDB / 40.0), w = 2 * pi * hz / rate;
        const double alpha = std::sin(w) / (2 * q), a0 = 1 + alpha / a;
        const double b1 = -2 * std::cos(w) / a0;
        set((1 + alpha * a) / a0, b1, (1 - alpha * a) / a0, b1, (1 - alpha / a) / a0);
    }
};
}

struct CMProcessor {
    const double rate;
    std::array<std::atomic<float>, 8> parameters;
    std::atomic<uint32_t> flags{0}, sequence{0};
    uint32_t appliedSequence = UINT32_MAX;
    CMControls controls = CMDefaultControls();
    uint32_t inputChannel = 0, outputOffset = 0;
    uint32_t monitorOffset = UINT32_MAX, monitorChannels = 0;
    Biquad highPass, mud, presence;
    float inputGain = 1, makeup = 1, reduction = 0, limiter = 1;
    float bypassMix = 0, muteGain = 1, bypassStep = 0, muteStep = 0;
    uint32_t bypassRemaining = 0, muteRemaining = 0;
    const float gainSmoothing, attack, release, limiterRelease;
    std::atomic<float> inputPeak{-120}, outputPeak{-120}, gainReduction{0};
    std::atomic<uint64_t> processed{0}, routingErrors{0};
    std::array<float, maxFrames> scratch{};

    explicit CMProcessor(double sampleRate)
        : rate(sampleRate), gainSmoothing(std::exp(-1.0 / (0.005 * sampleRate))),
          attack(std::exp(-1.0 / (0.010 * sampleRate))),
          release(std::exp(-1.0 / (0.120 * sampleRate))),
          limiterRelease(std::exp(-1.0 / (0.050 * sampleRate))) {}

    void adoptControls() {
        const uint32_t before = sequence.load();
        if (before == appliedSequence || before & 1) return;
        CMControls next{};
        next.inputGainDB = parameters[0].load();
        next.highPassHz = parameters[1].load();
        next.mudGainDB = parameters[2].load();
        next.presenceGainDB = parameters[3].load();
        next.thresholdDB = parameters[4].load();
        next.ratio = parameters[5].load();
        next.makeupDB = parameters[6].load();
        next.monitorGainDB = parameters[7].load();
        const uint32_t bits = flags.load();
        next.bypass = bits & 1; next.muted = (bits >> 1) & 1; next.compressionEnabled = (bits >> 2) & 1;
        // No retry loop on the audio thread. Keep the previous snapshot if a UI write overlaps.
        // Sequentially consistent atomic fields keep the whole read between
        // the two sequence reads, including on ARM. No data race or RT fence loop.
        if (before != sequence.load()) return;
        const bool first = appliedSequence == UINT32_MAX;
        if (first) {
            bypassMix = next.bypass ? 1 : 0; muteGain = next.muted ? 0 : 1;
            inputGain = amplitude(next.inputGainDB); makeup = amplitude(next.makeupDB);
        } else {
            if (next.bypass != controls.bypass) {
                bypassRemaining = 240; bypassStep = ((next.bypass ? 1.0f : 0.0f) - bypassMix) / 240;
            }
            if (next.muted != controls.muted) {
                muteRemaining = 240; muteStep = ((next.muted ? 0.0f : 1.0f) - muteGain) / 240;
            }
        }
        controls = next; appliedSequence = before;
        highPass.highPass(rate, controls.highPassHz);
        mud.bell(rate, 280, controls.mudGainDB, 0.8);
        presence.bell(rate, 3500, controls.presenceGainDB, 0.7);
        if (first) { highPass.snap(); mud.snap(); presence.snap(); }
    }

    void process(float *samples, uint32_t count) {
        adoptControls();
        float peakIn = 0, peakOut = 0, maxReduction = 0;
        const float targetInput = amplitude(controls.inputGainDB), targetMakeup = amplitude(controls.makeupDB);
        const float ceiling = amplitude(-1);
        for (uint32_t i = 0; i < count; ++i) {
            const float raw = std::isfinite(samples[i]) ? std::clamp(samples[i], -8.0f, 8.0f) : 0;
            peakIn = std::max(peakIn, std::abs(raw));
            inputGain = gainSmoothing * inputGain + (1 - gainSmoothing) * targetInput;
            makeup = gainSmoothing * makeup + (1 - gainSmoothing) * targetMakeup;
            float value = presence.process(mud.process(highPass.process(raw * inputGain)));
            const float over = std::max(0.0f, decibels(std::abs(value)) - controls.thresholdDB);
            const float targetReduction = controls.compressionEnabled ? over * (1 - 1 / controls.ratio) : 0;
            const float smoothing = targetReduction > reduction ? attack : release;
            reduction = smoothing * reduction + (1 - smoothing) * targetReduction;
            maxReduction = std::max(maxReduction, reduction);
            value *= amplitude(-reduction) * makeup;
            const float desiredLimit = std::min(1.0f, ceiling / std::max(std::abs(value), 0.000001f));
            limiter = desiredLimit < limiter ? desiredLimit : limiterRelease * limiter + (1 - limiterRelease) * desiredLimit;
            value *= limiter;
            if (bypassRemaining) {
                bypassMix += bypassStep;
                if (--bypassRemaining == 0) bypassMix = controls.bypass ? 1 : 0;
            }
            if (muteRemaining) {
                muteGain += muteStep;
                if (--muteRemaining == 0) muteGain = controls.muted ? 0 : 1;
            }
            value = (value * (1 - bypassMix) + raw * bypassMix) * muteGain;
            samples[i] = value;
            peakOut = std::max(peakOut, std::abs(value));
        }
        inputPeak.store(decibels(peakIn), std::memory_order_relaxed);
        outputPeak.store(decibels(peakOut), std::memory_order_relaxed);
        gainReduction.store(controls.bypass ? 0 : maxReduction, std::memory_order_relaxed);
        processed.fetch_add(count, std::memory_order_relaxed);
    }
};

CMControls CMDefaultControls(void) { return {0, 80, -3, 2, -18, 3, 0, 0, 0, 1, -18}; }

CMProcessor *CMProcessorCreate(double rate) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 192000) return nullptr;
    auto *p = new (std::nothrow) CMProcessor(rate);
    if (p) CMProcessorSetControls(p, CMDefaultControls());
    return p;
}
void CMProcessorDestroy(CMProcessor *p) { delete p; }

void CMProcessorSetControls(CMProcessor *p, CMControls c) {
    if (!p) return;
    const std::array<float, 8> values = {
        bounded(c.inputGainDB, -24, 24, 0), bounded(c.highPassHz, 0, 200, 80),
        bounded(c.mudGainDB, -12, 6, 0), bounded(c.presenceGainDB, -6, 9, 0),
        bounded(c.thresholdDB, -48, 0, -18), bounded(c.ratio, 1, 8, 3), bounded(c.makeupDB, -12, 18, 0),
        bounded(c.monitorGainDB, -60, 0, -18)
    };
    p->sequence.fetch_add(1);
    for (size_t i = 0; i < values.size(); ++i) p->parameters[i].store(values[i]);
    p->flags.store((!!c.bypass) | ((!!c.muted) << 1) | ((!!c.compressionEnabled) << 2));
    p->sequence.fetch_add(1);
}

void CMProcessorSetRouting(CMProcessor *p, uint32_t input, uint32_t offset, uint32_t monitorOffset, uint32_t monitorChannels) {
    p->inputChannel = input; p->outputOffset = offset;
    p->monitorOffset = monitorOffset; p->monitorChannels = std::min(monitorChannels, 2u);
}
CMMeters CMProcessorGetMeters(const CMProcessor *p) {
    return {p->inputPeak.load(), p->outputPeak.load(), p->gainReduction.load(), p->processed.load(), p->routingErrors.load()};
}
void CMProcessorProcessMono(CMProcessor *p, float *samples, uint32_t frames) { p->process(samples, frames); }

OSStatus CMRender(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *input,
                  const AudioTimeStamp *, AudioBufferList *output, const AudioTimeStamp *, void *context) {
    auto *p = static_cast<CMProcessor *>(context);
    for (uint32_t i = 0; i < output->mNumberBuffers; ++i) {
        if (output->mBuffers[i].mData) std::memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
    uint32_t channel = p->inputChannel;
    const AudioBuffer *source = nullptr;
    for (uint32_t i = 0; i < input->mNumberBuffers; ++i) {
        const auto &buffer = input->mBuffers[i];
        if (channel < buffer.mNumberChannels) { source = &buffer; break; }
        channel -= buffer.mNumberChannels;
    }
    if (!source || !source->mData || !source->mNumberChannels) {
        p->routingErrors.fetch_add(1, std::memory_order_relaxed); return noErr;
    }
    const uint32_t frames = source->mDataByteSize / (sizeof(float) * source->mNumberChannels);
    if (frames > maxFrames) { p->routingErrors.fetch_add(1, std::memory_order_relaxed); return noErr; }
    const auto *data = static_cast<const float *>(source->mData);
    for (uint32_t i = 0; i < frames; ++i) p->scratch[i] = data[i * source->mNumberChannels + channel];
    p->process(p->scratch.data(), frames);
    uint32_t flatChannel = 0, written = 0, monitored = 0;
    const float monitorGain = amplitude(p->controls.monitorGainDB);
    for (uint32_t b = 0; b < output->mNumberBuffers; ++b) {
        auto &buffer = output->mBuffers[b];
        for (uint32_t c = 0; c < buffer.mNumberChannels; ++c, ++flatChannel) {
            const bool toVirtual = p->outputOffset != UINT32_MAX && flatChannel >= p->outputOffset && flatChannel < p->outputOffset + 2;
            const bool toMonitor = p->monitorOffset != UINT32_MAX && flatChannel >= p->monitorOffset && flatChannel < p->monitorOffset + p->monitorChannels;
            if ((!toVirtual && !toMonitor) || !buffer.mData) continue;
            const uint32_t available = buffer.mDataByteSize / (sizeof(float) * buffer.mNumberChannels);
            auto *destination = static_cast<float *>(buffer.mData);
            for (uint32_t i = 0; i < std::min(frames, available); ++i) destination[i * buffer.mNumberChannels + c] = p->scratch[i] * (toMonitor ? monitorGain : 1);
            if (toVirtual) ++written;
            if (toMonitor) ++monitored;
        }
    }
    if (written != (p->outputOffset == UINT32_MAX ? 0 : 2) || monitored != p->monitorChannels) p->routingErrors.fetch_add(1, std::memory_order_relaxed);
    return noErr;
}
