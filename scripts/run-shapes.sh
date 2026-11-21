#!/bin/bash
# run-shapes.sh UDID OUTROOT TAG [SHAPE…] — one measure.sh run (3 remounts) per shape on a booted simulator, with the
# build already in build/dd. A SHAPE is "<remount>-<wrapper>", e.g. same-alternate; default: every remount
# (same, gap, interlude) with every wrapper (none, view, alternate). Results: OUTROOT/TAG-<shape>.txt and OUTROOT/TAG-<shape>/.
set -u
UDID=${1:?udid}
OUT=${2:?outroot}
TAG=${3:?tag}
shift 3
S=$(cd "$(dirname "$0")" && pwd)
SHAPES=("$@")
[ "${#SHAPES[@]}" -gt 0 ] || SHAPES=(same-none gap-none interlude-none same-view gap-view interlude-view same-alternate gap-alternate interlude-alternate)
mkdir -p "$OUT"
for shape in "${SHAPES[@]}"; do
  remount=${shape%%-*}
  wrapper=${shape#*-}
  name="$TAG-$shape"
  LAUNCH_ARGS="-remount $remount -wrapper $wrapper" "$S/measure.sh" "$UDID" "$OUT/$name" 3 > "$OUT/$name.txt" 2>&1
  echo "$name rc=$? $(grep -E '^(q1|r[0-9]) hierarchy' "$OUT/$name.txt" | awk '{print $1":"$3":"$4":"$NF}' | tr '\n' ' ') stale=$(grep -c '^STALE' "$OUT/$name.txt") $(grep '^result=' "$OUT/$name.txt")"
done
