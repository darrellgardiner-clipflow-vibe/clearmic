#include "ClearMicAudio.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <vector>

int main() {
    for (int run = 0; run < 5; ++run) {
        auto *processor = CMProcessorCreate(48000);
        if (!processor) return 1;
        auto controls = CMDefaultControls();
        controls.noiseReductionEnabled = 1;
        CMProcessorSetControls(processor, controls);
        std::vector<double> times;
        times.reserve(1000);
        double energy = 0;
        unsigned random = 731;
        std::array<float, 480> samples;
        for (int frame = 0; frame < 1100; ++frame) {
            for (int i = 0; i < 480; ++i) {
                random = random * 1664525 + 1013904223;
                const double time = (frame * 480 + i) / 48000.0;
                samples[i] = 0.08 * std::sin(time * 2 * 3.141592653589793 * 180)
                    + 0.03 * std::sin(time * 2 * 3.141592653589793 * 720)
                    + (float(random >> 8) / 16777215 - 0.5f) * 0.02f;
            }
            const auto start = std::chrono::steady_clock::now();
            CMProcessorProcessMono(processor, samples.data(), 480);
            const double elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            if (frame >= 100) times.push_back(elapsed);
            for (float value : samples) {
                if (!std::isfinite(value) || std::abs(value) > 1) return 2;
                energy += value * value;
            }
        }
        const auto meters = CMProcessorGetMeters(processor);
        if (meters.processedFrames != 1100 * 480 || energy <= 0) return 3;
        std::sort(times.begin(), times.end());
        std::printf("run=%d blocks=%zu p50_ms=%.3f p99_ms=%.3f max_ms=%.3f frames=%llu energy=%.3f\n", run + 1, times.size(), times[500], times[990], times.back(), meters.processedFrames, energy);
        CMProcessorDestroy(processor);
    }
}
