#!/usr/bin/env bash
# Run under the selected instrumented build's dune exec environment.
set -euo pipefail
: "${CASES:?absolute case-studies checkout}" "${OUT:?absolute output directory}"
bin="${DUNE_SOURCEROOT:?run with dune exec --}/_build/install/default/bin/frama-c"
sites="$DUNE_SOURCEROOT/_build/install/default"
cd "$CASES/gzip124/.frama-c"
mkdir -p "$OUT"
if [[ ! -f "$OUT/parsed.sav" ]]; then
  "$bin" -add-symbolic-path=..:. -nonterm-ignore do_exit -main eva_main -machdep x86_32 \
    "-cpp-extra-args=-include$sites/share/frama-c/share/libc/string.h -DSTDC_HEADERS=1 -DHAVE_UNISTD_H=1 -DDIRENT=1 -DNO_UTIME=1 -I$sites/share/frama-c/share/libc -I$sites/lib/frama-c/lib/analysis-scripts/" \
    "$sites/share/frama-c/share/libc/stdlib.c" fc_stubs.c \
    ../{bits,crypt,deflate,getopt,gzip,inflate,lzw,trees,unlzh,unlzw,unpack,unzip,util,zip}.c \
    -save "$OUT/parsed.sav" > "$OUT/parse.log" 2>&1
fi
for mode in "${@:-first}"; do
  out="$OUT/$mode"
  mkdir "$out"
  (
    unset OCAMLRUNPARAM FRAMAC_DETERMINISTIC MATCH_ORDER EVA_WAYFINDER_ENTRY_LOG
    case "$mode" in
      first) ;;
      small) export OCAMLRUNPARAM=s=64k ;;
      oldest|newest) export MATCH_ORDER="$mode" ;;
      oldest-small) export MATCH_ORDER=oldest OCAMLRUNPARAM=s=64k ;;
      *) echo "Unknown mode $mode" >&2; exit 2 ;;
    esac
    export EVA_WAYFINDER_HEAP_LOG="$out/heap" DUMP_OBS="$out/obs"
    "$bin" -load "$OUT/parsed.sav" -eva -main eva_main -calldeps -from-verbose 0 \
      -cache-size 8 -eva-slevel 2 -eva-no-alloc-returns-null -eva-msg-key callstacks \
      -eva-warn-key alarm=inactive -eva-warn-key garbled-mix=warning,garbled-mix:write=warning \
      -eva-statistics-file "$out/stats" -then -report-csv "$out/alarms" -report-no-proven \
      -metrics-eva-cover > "$out/log" 2>&1
  )
  awk '$1=="body_analysed"' "$out/heap"
  awk '$1 ~ /^memexec-/ && $2=="huft_free"' "$out/stats"
  sha256sum "$out/obs" "$out/alarms"
done
