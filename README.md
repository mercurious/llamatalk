# llamatalk

The local AI runtime that retro handheld apps share: llama.cpp's `llama-server` (language and speech
recognition models) and Pocket TTS's `tts-server` (speech), built for aarch64 ROCKNIX at pinned commits, and one
models directory on the device that every app uses, so the gigabytes download once.

Apps that bundle it:

| app | what it is | model sets |
|---|---|---|
| [retro-voice-chat](https://github.com/mercurious/retro-voice-chat) | push-to-talk voice chat, puzzles and Zork | `asr e2b tts`, `e4b` for smart mode |
| [autogamer](https://github.com/mercurious/autogamer) | a language model plays retro games in RetroArch while you watch | `e2b e4b tts` |

Everything runs on the device: no cloud, no account, no network once the models are downloaded. It runs on the
CPU. Built and tested on a **Retroid Pocket Flip 2** (Snapdragon 865 / SM8250, 8 and 12 GB) running **ROCKNIX**.

> **AI disclosure.** This project was written with Claude Code (Anthropic's Claude Opus 5.5). Most of the code
> and this README are model output, produced under the author's direction. The author chose what to build and
> ran it on the hardware. Treat it as a working prototype, not a finished product.

## What is in a release

```
llamatalk/
  bin/llama-server     llama.cpp, unpatched, CPU only (armv8.2-a + dotprod + fp16)
  bin/tts-server       pockettts.cpp, + PT_THREADS (the thread count; taskset pinning does not lower it)
  models.sh            finds, checks and downloads the models into the shared directory
  models.txt           the models, in sets
  BUILD.txt            the version and the pinned commits
  VERSION, README.md, LICENSE, THIRD_PARTY.md
```

The binaries are about 17 MB. The models are the big part:

| set | files | size | used for |
|---|---|---|---|
| `asr` | Qwen3-ASR-0.6B Q8_0 + its audio projector | 1.0 GB | speech recognition |
| `e2b` | Gemma 4 E2B, QAT Q4_0 | 3.4 GB | the fast language model |
| `e4b` | Gemma 4 E4B, QAT Q4_0 | 5.2 GB | the larger language model |
| `tts` | Pocket TTS English + its voices | 0.3 GB | speech |

## The shared models directory

On the handheld, `~/.config/llamatalk/models-dir` holds the path of the models directory. The first app installed
creates it; every app after that finds the models already there and downloads only the sets it adds.

```sh
llamatalk/models.sh path                      # where the models are (exit 1: none yet)
llamatalk/models.sh list                      # every model: have or missing
llamatalk/models.sh check e2b tts             # what these sets still miss (exit 1 if anything)
llamatalk/models.sh fetch e4b                 # download a set into the shared directory (resumes)
llamatalk/models.sh fetch --dir DIR e2b tts   # the first time, or to move it: DIR becomes the shared one
llamatalk/models.sh use DIR                   # point at a directory that already has the models
```

`LLAMATALK_MODELS=DIR` overrides the shared directory for one command or one launch. Put the directory where there
is room, for example on the SD card: all four sets take 9.9 GB.

## For app authors

An app's release carries `dist/llamatalk/` from a pinned llamatalk version as its own `llamatalk/` folder, so the
app and the runtime it was tested with travel together and two apps on one device never share binaries. The
installer finds or makes the shared directory and fetches the sets the app needs:

```sh
M=$("$H/llamatalk/models.sh" path) || M=${MY_APP_MODELS:-$H/models}
"$H/llamatalk/models.sh" fetch --dir "$M" e2b tts
```

The launcher runs `$H/llamatalk/bin/llama-server` and `$H/llamatalk/bin/tts-server` with the models in
`$("$H/llamatalk/models.sh" path)`. Pinning, ports and flags are the app's business: on the SM8250 the apps keep
the servers on the big cores (4-7) and leave 0-3 to the rest. Start servers with `ulimit -c 0`: a crashed server
must not leave a multi-GB core file behind.

## The GPU

llamatalk is CPU only on purpose: on an 8 GB Flip 2 the Adreno 650 gave no gain for conversation. An app can still
offer the GPU as an option by pointing its launcher at an Adreno build of `llama-server`; that build and its
drivers are a separate kit (llamadreno), which no app needs.

## Building

On an arm64 Linux host with podman and git:

```sh
build/build.sh        # -> dist/llamatalk/ and dist/llamatalk-<version>-aarch64.tar.gz
build/release.sh      # builds main, checks the tarball, uploads a draft GitHub release v<VERSION> (DRY=1: no upload)
test/test_models.sh   # models.sh against a local mirror; also runs on the handheld
```

The build fetches each source at its pinned commit and compiles in an Ubuntu 24.04 container (glibc 2.39; ROCKNIX
has 2.41). About 5 minutes at `JOBS=3` with a 3 GB memory cap (`MEM`, `MEMSWAP`). `ENGINE=docker` builds with docker
instead of podman. To release from a build server: `DRY=1 build/release.sh` there, copy the tarball into `dist/`, then
`PREBUILT=1 build/release.sh` where gh can upload.

## Licence

MIT, see `LICENSE`. The binaries and models are third-party: see `THIRD_PARTY.md`.
