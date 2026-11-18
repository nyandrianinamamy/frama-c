#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Run the Eva ptests with the collector enabled and aggregate its statistics.
# Invoke from the worktree with its opam environment active. The optional
# argument selects one Dune test alias. Restore the ordinary rules on exit.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
bash dev/check-env.sh

export TERM=xterm
export FC_FORCE_PTESTS=$(date +%s)
dir=$(mktemp -d)
echo "statistics and run log in $dir"

timeout 35m dune build -j 8 @install > "$dir/build.log" 2>&1
trap 'dune exec -j 8 -- frama-c-ptests plugins/eva/tests > "$dir/restore.log" 2>&1' EXIT

# Export one file per computation, preserving the tests' own statistics files.
# Use the existing statistics, including completed bodies in aborted analyses.
cat > "$dir/dune-project" <<'DUNE'
(lang dune 3.15)
(name collector_statistics)
DUNE
cat > "$dir/dune" <<'DUNE'
(executable
 (name collector_statistics)
 (modes plugin)
 (libraries frama-c.kernel frama-c-eva.core)
 (flags :standard -open Frama_c_kernel))
DUNE
cat > "$dir/collector_statistics.ml" <<ML
let () =
  Eva.Analysis.register_computation_hook (function
      | Computed | Aborted as status ->
        let prefix = if status = Computed then "computed" else "aborted" in
        let csv = Filename.temp_file ~temp_dir:"$dir" prefix ".tsv" in
        Eva.Statistics.export_as_csv ~filename:(Filepath.of_string csv) ()
      | NotComputed | Computing -> ())
ML
OCAMLPATH="$PWD/_build/install/default/lib" \
  dune build -j 8 --root "$dir" collector_statistics.cmxs
collector="$dir/_build/default/collector_statistics.cmxs"
dune exec -j 8 -- frama-c-ptests \
  -macro-frama-c-exe "frama-c -load-module eva,$collector -eva-cache-collect" \
  plugins/eva/tests > "$dir/rules.log" 2>&1

code=0
timeout 45m dune build -j 8 --cache=disabled "${1:-@plugins/eva/tests/ptests}" \
  > "$dir/run.log" 2>&1 || code=$?
echo "dune exit $code"

shopt -s nullglob
completed=("$dir"/computed*.tsv)
aborted=("$dir"/aborted*.tsv)
echo "analyses-completed ${#completed[@]}"
echo "analyses-aborted ${#aborted[@]}"
if (( ${#completed[@]} + ${#aborted[@]} > 0 )); then
  awk -F '\t' '
    /^collector-/ { counts[$1] += $4 }
    END { for (reason in counts) print reason, counts[reason] }
  ' "${completed[@]}" "${aborted[@]}" | sort
fi
exit "$code"
