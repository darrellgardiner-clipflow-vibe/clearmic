#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
CF_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CMProcessor CMProcessor;
typedef struct {
    float inputGainDB;
    float highPassHz;
    float mudGainDB;
    float presenceGainDB;
    float thresholdDB;
    float ratio;
    float makeupDB;
    uint32_t bypass;
    uint32_t muted;
    uint32_t compressionEnabled;
    float monitorGainDB;
    uint32_t noiseReductionEnabled;
    float bassGainDB;
    float airGainDB;
    float deEssAmount;
    float reverbMix;
} CMControls;

typedef struct {
    float inputPeakDB;
    float outputPeakDB;
    float reductionDB;
    uint64_t processedFrames;
    uint64_t routingErrors;
} CMMeters;

CMControls CMDefaultControls(void);
CMProcessor * _Nullable CMProcessorCreate(double sampleRate);
void CMProcessorDestroy(CMProcessor *processor);
void CMProcessorSetControls(CMProcessor *processor, CMControls controls);
// UINT32_MAX disables the virtual or monitor destination. Call before starting I/O.
void CMProcessorSetRouting(CMProcessor *processor, uint32_t inputChannel, uint32_t outputOffset,
                           uint32_t monitorOffset, uint32_t monitorChannels);
CMMeters CMProcessorGetMeters(const CMProcessor *processor);
void CMProcessorProcessMono(CMProcessor *processor, float *samples, uint32_t frames);
OSStatus CMRender(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
                  const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
                  AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime,
                  void * _Nullable context);

#ifdef __cplusplus
}
#endif
CF_ASSUME_NONNULL_END
