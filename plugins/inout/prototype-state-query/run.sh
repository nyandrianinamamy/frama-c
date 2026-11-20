#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

set -euo pipefail

# Run from any directory in this checkout.
prototype="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$prototype/../../.."
prototype=plugins/inout/prototype-state-query
evidence="${1:-$prototype/evidence}"
mkdir -p -- "$evidence"

source "$prototype/setup.sh"

frama_c=(dune exec --no-build -- frama-c -no-autoload-plugins
  -load-module eva,inout -eva-domains cvalue -eva-slevel 30
  -eva-show-progress -eva-no-remove-redundant-alarms)
cases=(original loop read-before-write guard unreachable partial-base
  maybe-write maybe-write-goto maybe-write-upstream)
{
  git rev-parse HEAD
  printf '%q ' "${frama_c[@]}"
  printf '\n'
  "${frama_c[@]}" -plugins
} > "$evidence/environment.txt" 2>&1

for name in "${cases[@]}"; do
  "${frama_c[@]}" -inout-state-query-prototype fresh "$prototype/$name.c" \
    -then -inout-state-query-prototype hit > "$evidence/$name.log" 2>&1
  printf 'Recorded %s\n' "$name"
done

"${frama_c[@]}" -eva-no-results-function f -inout-state-query-prototype missing \
  "$prototype/original.c" > "$evidence/missing.log" 2>&1
printf 'Recorded missing\n'

python3 "$prototype/render.py" "$prototype" "$evidence"

bash "$prototype/acceptance.sh" "$evidence/acceptance"
