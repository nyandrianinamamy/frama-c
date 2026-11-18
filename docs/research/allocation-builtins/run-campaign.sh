#!/usr/bin/env bash
set -euo pipefail
source "${W28:?set W28 to the measurement root}/env.sh"
export LC_ALL=C TERM=dumb
manifest=${1:?manifest}
result_dir=${2:?fresh result dir}
mkdir "$result_dir"
cp "$manifest" "$result_dir/manifest"
sha256sum "$instrumented/frama-c" "$build_root/_build/default/plugins/eva/src/eva.cmxs" > "$result_dir/hashes"
"$instrumented/frama-c" -version > "$result_dir/frama-version"
cp "$w28/oscs-revision" "$w28/frama-revision" "$w28/sites.env" "$result_dir/"
{ uname -a; lscpu; free -m; ocamlc -version; dune --version; gcc --version; } > "$result_dir/machine"
printf 'case\tmake_exit\tanalysis_complete\n' > "$result_dir/outcomes.tsv"
while IFS= read -r target; do
  case_dir="$result_dir/$target"
  mkdir -p "$case_dir"
  analysis_dir="$w28/oscs/${target%/*}/.frama-c/${target##*/}"
  export EVA_WAYFINDER_HEAP_LOG="$case_dir/heap.tsv"
  unset EVA_WAYFINDER_ENTRY_LOG
  args=(/usr/bin/time -o "$case_dir/time" -f '%e\t%U\t%S\t%M\t%x' timeout 3600
        make -C "$w28/oscs" -B --trace "FRAMAC_DIR=$instrumented" "$target")
  printf '%q ' "${args[@]}" > "$case_dir/command.sh"; printf '\n' >> "$case_dir/command.sh"
  code=0
  "${args[@]}" > "$case_dir/make.log" 2>&1 || code=$?
  printf '%s\n' "$code" > "$case_dir/exit"
  for artifact in command eva.log stats.txt alarms.csv metrics.log nonterm.log eva-stats.csv; do
    if [[ -f "$analysis_dir/$artifact" ]]; then cp "$analysis_dir/$artifact" "$case_dir/$artifact"; fi
  done
  gzip "$case_dir/make.log"
  if [[ -f "$case_dir/eva.log" ]]; then gzip "$case_dir/eva.log"; fi
  find "$w28/oscs/${target%/*}/.frama-c" -name framac.sav -type f -delete
  completion=missing
  if [[ -f "$case_dir/heap.tsv" ]]; then completion=$(awk -F '\t' '$1=="complete"{print $2}' "$case_dir/heap.tsv"); fi
  printf '%s\t%s\t%s\n' "$target" "$code" "$completion" >> "$result_dir/outcomes.tsv"
done < "$manifest"
