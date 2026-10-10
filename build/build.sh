#!/usr/bin/env bash
# Builds llamatalk for an aarch64 ROCKNIX handheld: dist/llamatalk/ and a tarball of it. Needs an arm64 Linux host
# with podman and git. Every source is fetched at a pinned commit and built in the container (build/Containerfile):
#   llama.cpp      -> bin/llama-server   CPU only, unpatched
#   pockettts.cpp  -> bin/tts-server     + build/pockettts-pt-threads.patch (thread count from PT_THREADS)
# An app bundles dist/llamatalk as its own llamatalk/ folder (see README).
# Env: JOBS (default 3), MEM / MEMSWAP (container memory cap, default 3g / 8g), ENGINE (podman, default, or docker:
#   docker runs the container as this user, so build/work stays ours).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$ROOT/build/work"; OUT="$ROOT/dist/llamatalk"; IMAGE=llamatalk-build; VER=$(cat "$ROOT/VERSION")
ENGINE=${ENGINE:-podman}; RUNAS=; [ "$ENGINE" = docker ] && RUNAS="--user $(id -u):$(id -g)"
LLAMA=https://github.com/ggml-org/llama.cpp          LLAMA_COMMIT=6c7a87f7e5e5cd75b8a641c3471f2dee84a6ed17
POCKET=https://github.com/ServeurpersoCom/pockettts.cpp POCKET_COMMIT=e6215096f35cdb4c81c6be452ce7b31225fed8ff

fetch() {   # fetch <url> <commit> <dir>: that one commit, nothing else
  [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" = "$2" ] && return 0
  mkdir -p "$3"; git -C "$3" init -q
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q --detach FETCH_HEAD
}

mkdir -p "$W"
fetch $LLAMA $LLAMA_COMMIT "$W/llama.cpp"
fetch $POCKET $POCKET_COMMIT "$W/pockettts.cpp"
git -C "$W/pockettts.cpp" submodule update -q --init --depth 1
git -C "$W/pockettts.cpp" apply --check "$ROOT/build/pockettts-pt-threads.patch" 2>/dev/null \
  && git -C "$W/pockettts.cpp" apply "$ROOT/build/pockettts-pt-threads.patch"
grep -q PT_THREADS "$W/pockettts.cpp/src/backend.h" || { echo "PT_THREADS patch did not apply" >&2; exit 1; }

$ENGINE image inspect $IMAGE >/dev/null 2>&1 || $ENGINE build -q -t $IMAGE -f "$ROOT/build/Containerfile" "$ROOT/build"
$ENGINE run --rm $RUNAS --memory "${MEM:-3g}" --memory-swap "${MEMSWAP:-8g}" -e JOBS="${JOBS:-3}" -v "$W":/w:Z -w /w $IMAGE bash -c '
  set -e
  ARCH="-DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 -DGGML_OPENMP=ON -DBUILD_SHARED_LIBS=OFF"
  [ -f b-llama/build.ninja ] || cmake -S llama.cpp -B b-llama -G Ninja -DCMAKE_BUILD_TYPE=Release $ARCH \
    -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_TESTS=OFF >/dev/null
  cmake --build b-llama -j$JOBS --target llama-server
  [ -f b-pocket/build.ninja ] || cmake -S pockettts.cpp -B b-pocket -G Ninja -DCMAKE_BUILD_TYPE=Release $ARCH >/dev/null
  cmake --build b-pocket -j$JOBS --target tts-server
  strip b-llama/bin/llama-server
  strip "$(find b-pocket -name tts-server -type f | head -1)"
'

rm -rf "$OUT"; mkdir -p "$OUT/bin"
cp "$W/b-llama/bin/llama-server" "$OUT/bin/"
cp "$(find "$W/b-pocket" -name tts-server -type f | head -1)" "$OUT/bin/"
cp "$ROOT"/models.sh "$ROOT"/models.txt "$ROOT"/VERSION "$ROOT"/README.md "$ROOT"/LICENSE "$ROOT"/THIRD_PARTY.md "$OUT/"
{ echo "llamatalk $VER $(git -C "$ROOT" rev-parse HEAD)"; echo "llama.cpp $LLAMA_COMMIT (unpatched, CPU only)"
  echo "pockettts.cpp $POCKET_COMMIT (+ pockettts-pt-threads.patch)"; } > "$OUT/BUILD.txt"
chmod +x "$OUT"/models.sh "$OUT"/bin/*
tar -C "$ROOT/dist" -czf "$ROOT/dist/llamatalk-$VER-aarch64.tar.gz" llamatalk
ls -la "$OUT" "$OUT/bin"; du -sh "$ROOT/dist/llamatalk-$VER-aarch64.tar.gz"
