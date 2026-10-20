RNNoise v0.2, upstream https://github.com/xiph/rnnoise
Commit 904a876dce1f9ab8860c0a5000ed151f9f6eef58.
Pristine library C sources and headers; upstream compile-time SIMD selection.
Model rnnoise_data-0b50c45.tar.gz from https://media.xiph.org/rnnoise/models/
Archive SHA256 4ac81c5c0884ec4bd5907026aaae16209b7b76cd9d7f71af582094a2f98f4b43.
Model C data/header copied unchanged. No model download at runtime.
See COPYING and per-file notices for redistribution terms.

compat/os_support.h is a ClearMic compatibility shim, not an upstream file.
The v0.2 vector headers include a missing os_support.h and use OPUS_CLEAR;
the shim maps it to the upstream RNN_CLEAR with identical semantics.
