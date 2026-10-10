#!/bin/sh
# llamatalk models: one models directory on the handheld, shared by every app that bundles llamatalk, so the
# gigabytes download once. Runs ON the handheld (or any Linux with curl).
#   models.sh path                       the shared models directory (nothing and exit 1 if there is none yet)
#   models.sh list                       every model in models.txt: have or missing
#   models.sh check SET...               the files these sets still miss, one a line (exit 1 if any)
#   models.sh fetch [--dir DIR] SET...   download what these sets miss (resumes a broken download) and make the
#                                        directory the shared one
#   models.sh use DIR                    make DIR the shared models directory (the files already there count)
# Which directory: LLAMATALK_MODELS if set, else the one in ~/.config/llamatalk/models-dir (written by fetch and
# use), else none: fetch then needs --dir (an app's installer passes its own default, e.g. ./models).
# Sets are the first column of models.txt (asr, e2b, e4b, tts). Env: LT_HF (default https://huggingface.co).
set -u
LT=$(cd "$(dirname "$0")" && pwd); CAT=$LT/models.txt; HF=${LT_HF:-https://huggingface.co}
PTR=${XDG_CONFIG_HOME:-${HOME:-/storage}/.config}/llamatalk/models-dir

die() { echo "llamatalk: $*" >&2; exit 2; }
shared() {
  if [ -n "${LLAMATALK_MODELS:-}" ]; then echo "$LLAMATALK_MODELS"; return 0; fi
  [ -s "$PTR" ] || return 1
  d=$(cat "$PTR"); [ -d "$d" ] && echo "$d"
}
remember() { mkdir -p "${PTR%/*}" && echo "$1" > "$PTR"; }
# the catalogue lines of these sets (all with none): "set repo file saved-as"; an unknown set is an error
entries() {
  for s in "$@"; do
    awk -v s="$s" '!/^#/ && $1 == s { f = 1 } END { exit !f }' "$CAT" || die "unknown model set: $s"
  done
  awk -v want=" $* " '!/^#/ && NF >= 3 && (want == "  " || index(want, " " $1 " ")) { print $1, $2, $3, (NF > 3 ? $4 : $3) }' "$CAT"
}
# bytes of a download (0 when the server does not say)
size() { curl -sIL --max-time 20 "$1" 2>/dev/null | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }'; }

cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  path) shared ;;
  list)
    d=$(shared) || d=""; echo "models directory: ${d:-none yet}"
    entries | while read -r set repo file as; do
      [ -n "$d" ] && [ -f "$d/$as" ] && st=have || st=missing; printf '%-8s %-4s %s\n' $st "$set" "$as"
    done ;;
  check)
    [ $# -gt 0 ] || die "check: which sets? ($(awk '!/^#/ && NF >= 3 { print $1 }' "$CAT" | uniq | tr '\n' ' '))"
    d=$(shared) || d=""; L=$(entries "$@") || exit 2; miss=0
    echo "$L" | { while read -r set repo file as; do
      [ -n "$d" ] && [ -f "$d/$as" ] || { echo "$as"; miss=1; }
    done; exit $miss; } ;;
  use)
    [ $# = 1 ] && [ -d "$1" ] || die "use: needs an existing directory"
    d=$(cd "$1" && pwd) && remember "$d" && echo "shared models directory: $d" ;;
  fetch)
    d=""; [ "${1:-}" = --dir ] && { [ $# -ge 2 ] || die "fetch: --dir needs a directory"; d=$2; shift 2; }
    [ $# -gt 0 ] || die "fetch: which sets?"
    L=$(entries "$@") || exit 2
    old=$(shared) || old=""; [ -n "$d" ] || d=$old
    [ -n "$d" ] || die "no shared models directory yet: fetch --dir DIR SET..."
    mkdir -p "$d" && d=$(cd "$d" && pwd) || die "cannot make $d"
    [ -n "$old" ] && [ "$old" != "$d" ] && echo "note: the shared models directory moves from $old to $d (the files there stay)"
    remember "$d"
    need=0; todo=""
    for as in $(echo "$L" | awk '{ print $4 }'); do [ -f "$d/$as" ] || todo="$todo $as"; done
    if [ -n "$todo" ]; then
      for as in $todo; do
        set -- $(echo "$L" | awk -v a="$as" '$4 == a { print $2, $3; exit }')
        need=$((need + $(size "$HF/$1/resolve/main/$2")))
      done
      free=$(df -Pk "$d" | awk 'NR == 2 { print $4 * 1024 }')
      [ "$need" -gt 0 ] && [ "$need" -gt "$free" ] && \
        echo "warning: the downloads need $((need >> 30)) GB, $d has $((free >> 30)) GB free"
    fi
    fail=0
    for as in $(echo "$L" | awk '{ print $4 }'); do
      [ -f "$d/$as" ] && { echo "have $as"; continue; }
      set -- $(echo "$L" | awk -v a="$as" '$4 == a { print $2, $3; exit }')
      echo "get  $as"
      if curl -fL --retry 5 -C - -o "$d/$as.part" "$HF/$1/resolve/main/$2" </dev/null; then mv "$d/$as.part" "$d/$as"
      else echo "FAILED $as (run again to resume)"; fail=1; fi
    done
    echo "models directory: $d"; exit $fail ;;
  *) sed -n '2,13s/^# \{0,1\}//p' "$0"; [ -z "$cmd" ] || [ "$cmd" = help ] || exit 2 ;;
esac
