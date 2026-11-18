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
export EVA_COLLECTOR_STATS_DIR="$dir"
echo "statistics and run log in $dir"

timeout 35m dune build -j 8 @install > "$dir/build.log" 2>&1
trap 'dune exec -j 8 -- frama-c-ptests plugins/eva/tests > "$dir/restore.log" 2>&1' EXIT

# Keep the last cumulative snapshot of each analysis, including aborted
# analyses. Mthread also reports Computed for intermediate thread results.
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
cp dev/collector_statistics.ml "$dir/"
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
started=("$dir"/analysis*.tsv)
statuses=("$dir"/analysis*.status)
echo "analyses-started ${#started[@]}"
for status in completed aborted; do
  count=0
  if (( ${#statuses[@]} )); then
    count=$(awk -v status="$status" '$0 == status { count++ }
      END { print count+0 }' "${statuses[@]}")
  fi
  echo "analyses-$status $count"
done
if (( ${#started[@]} )); then
  awk -F '\t' '
    BEGIN {
      reasons = "indirect-call builtin sweep contract annotation nested-call allocated-block footprint-top side-table"
      split(reasons, reason, " ")
      for (i in reason) counts["collector-refused-" reason[i]] = 0
      counts["collector-would-store"] = 0
    }
    /^collector-/ { counts[$1] += $4 }
    END { for (key in counts) print key, counts[key] }
  ' "${started[@]}" | sort
fi
exit "$code"
