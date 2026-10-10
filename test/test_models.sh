#!/bin/sh
# models.sh against a local file:// mirror of models.txt (small fake files): no network, nothing outside a temp dir.
# Usage: test/test_models.sh [path/to/models.sh]     (runs on the host or on the handheld)
LT=${1:-$(cd "$(dirname "$0")/.." && pwd)/models.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home LT_HF=file://$T/hf; unset LLAMATALK_MODELS XDG_CONFIG_HOME
grep -v '^#' "$(dirname "$LT")/models.txt" | while read -r set repo file as; do
  [ -n "$set" ] && mkdir -p "$T/hf/$repo/resolve/main" && echo "$file" > "$T/hf/$repo/resolve/main/$file"
done
n=0; bad=0
ok() { n=$((n + 1)); if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }

"$LT" path >/dev/null; [ $? = 1 ]; ok $? "path: none before the first fetch"
"$LT" fetch e2b >/dev/null 2>&1; [ $? = 2 ]; ok $? "fetch without --dir and no shared dir: refused"
"$LT" check nosuchset >/dev/null 2>&1; [ $? = 2 ]; ok $? "unknown set: exit 2"
"$LT" fetch --dir "$T/a/models" e2b tts >/dev/null 2>&1; ok $? "fetch --dir e2b tts"
[ "$("$LT" path)" = "$T/a/models" ]; ok $? "path: the fetched dir is now shared"
[ "$(ls "$T/a/models" | wc -l)" = 3 ]; ok $? "three files, no .part left"
"$LT" check e2b tts >/dev/null; ok $? "check e2b tts: complete"
[ "$("$LT" check asr e2b | wc -l)" = 2 ]; ok $? "check asr e2b: the two asr files missing"
"$LT" check asr >/dev/null; [ $? = 1 ]; ok $? "check asr: exit 1"
"$LT" fetch e4b >/dev/null 2>&1; ok $? "fetch e4b: into the shared dir without --dir"
[ -f "$T/a/models/gemma-4-E4B_q4_0-it.gguf" ]; ok $? "e4b landed in the shared dir"
f=$T/a/models/Qwen3-ASR-0.6B-Q8_0.gguf; printf 'Qwen3' > "$f.part"
"$LT" fetch asr >/dev/null 2>&1; ok $? "fetch asr over a partial download"
[ "$(cat "$f")" = Qwen3-ASR-0.6B-Q8_0.gguf ]; ok $? "the partial download resumed to the whole file"
[ "$("$LT" list | grep -c '^have')" = 6 ]; ok $? "list: all six have"
mkdir -p "$T/b"; "$LT" use "$T/b" >/dev/null; [ "$("$LT" path)" = "$T/b" ]; ok $? "use moves the shared dir"
[ "$(LLAMATALK_MODELS=$T/a/models "$LT" path)" = "$T/a/models" ]; ok $? "LLAMATALK_MODELS wins"
"$LT" check tts >/dev/null; [ $? = 1 ]; ok $? "check after use: the new dir is empty"
echo "$((n - bad))/$n passed"; [ $bad = 0 ]
