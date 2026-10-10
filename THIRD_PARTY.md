# Third-party software and models

This repository holds its own code (MIT, see `LICENSE`): the build script, `models.sh`, `models.txt` and the
tests. A release tarball built by `build/build.sh` also contains two binaries, each built from the pinned commit
named in that script (and in the tarball's `BUILD.txt`):

| component | in the tarball as | upstream | licence |
|---|---|---|---|
| llama.cpp (with ggml) | `bin/llama-server` | https://github.com/ggml-org/llama.cpp | MIT |
| pockettts.cpp (with its ggml submodule) | `bin/tts-server` | https://github.com/ServeurpersoCom/pockettts.cpp | MIT |

- **llama.cpp** is built unmodified, CPU only.
- **pockettts.cpp** is built with one small patch, `build/pockettts-pt-threads.patch` (the thread count can be
  set with `PT_THREADS`).

## Models

`models.sh` downloads the models from Hugging Face (`models.txt`); none are redistributed here. Each has its own
licence or terms of use on its model card, which you accept by downloading it. As the model cards stated them on
2026-10-09:

| repository | licence |
|---|---|
| `google/gemma-4-E2B-it-qat-q4_0-gguf`, `google/gemma-4-E4B-it-qat-q4_0-gguf` | Apache-2.0 |
| `ggml-org/Qwen3-ASR-0.6B-GGUF` | not stated on the GGUF card: see the original Qwen3-ASR model card |
| `Serveurperso/pocket-tts-GGUF` | CC-BY-4.0 |
