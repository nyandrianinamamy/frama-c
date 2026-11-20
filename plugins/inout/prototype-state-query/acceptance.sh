#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Acceptance driver for Eva result queries. For each fixture, a reference
# process runs fresh-only Eva on the legacy path with the legacy-read guard
# off, and a separate candidate process records every legacy read and every
# answer of the hit-log resolver. A third process compares the models of
# both in memory. The controls run in their own processes. compare.py then
# compares the answers and writes the report.
# Usage: acceptance.sh [evidence-dir]

set -euo pipefail

prototype="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$prototype/../../.."
prototype=plugins/inout/prototype-state-query
evidence="${1:-$prototype/evidence/acceptance}"
mkdir -p -- "$evidence"

source "$prototype/setup.sh"

base=(dune exec --no-build -- frama-c -no-autoload-plugins
  -load-module eva,inout -eva-domains cvalue -eva-slevel 30)
# This slice compares fresh-only executions; later tickets change the
# candidate's options.
candidate_options=(${CANDIDATE_OPTIONS:--eva-no-memexec})
fixtures=(legacy-reads assign stages original loop read-before-write guard
  unreachable partial-base maybe-write maybe-write-goto maybe-write-upstream
  pre-label precondition selection)
# The fixture of the plug-in readers, which runs the plugins- modes.
plugin_fixture=plugins

{
  printf 'revision %s\n' "$(git rev-parse HEAD)"
  if [ -z "$(git status --porcelain)" ]
  then printf 'worktree clean\n'
  else printf 'worktree modified\n'
  fi
  printf 'command %s\n' "$(printf '%q ' "${base[@]}")"
  printf 'candidate-options %s\n' "${candidate_options[*]}"
  "${base[@]}" -plugins | sed 's/^/plugins /'
} > "$evidence/environment.txt" 2>&1

run() {
  local name=$1 mode=$2 output=$3
  shift 3
  "${base[@]}" "$@" -inout-state-query-acceptance "$mode" \
    -inout-state-query-acceptance-output "$output.jsonl" \
    "$prototype/$name.c" > "$output.log" 2>&1
}

for name in "${fixtures[@]}"; do
  run "$name" reference "$evidence/$name.reference"
  run "$name" candidate "$evidence/$name.candidate" "${candidate_options[@]}"
  # Fresh-only reference and candidate in one process, compared natively.
  run "$name" native "$evidence/$name.native"
  printf 'Recorded %s\n' "$name"
done

# Plug-in readers and Eva's semantic reports: Callgraph, InOut, Server's
# filters and properties, statuses and statistics.
run "$plugin_fixture" plugins-reference "$evidence/$plugin_fixture.reference"
run "$plugin_fixture" plugins-candidate "$evidence/$plugin_fixture.candidate" \
  "${candidate_options[@]}"
run "$plugin_fixture" plugins-native "$evidence/$plugin_fixture.native"
printf 'Recorded %s\n' "$plugin_fixture"

# Resolver controls. A resolver that rebuilds each visit from the wrong
# producer must be reported; on the legacy path, InOut's collection reads
# the store. With memexec, InOut's answers and the analyses of f in
# pre-label.c and precondition.c must be the same on the legacy path and
# with the hit log.
run legacy-reads wrong-producer "$evidence/control-wrong-producer" \
  "${candidate_options[@]}"
run selection wrong-producer "$evidence/control-wrong-producer-selection" \
  "${candidate_options[@]}"
run "$plugin_fixture" plugins-wrong-producer \
  "$evidence/control-wrong-producer-plugins" "${candidate_options[@]}"
run legacy-reads candidate "$evidence/control-legacy-path" \
  "${candidate_options[@]}" -eva-no-hit-log
for name in pre-label precondition; do
  run "$name" candidate "$evidence/control-parity-$name.legacy" \
    -eva-memexec -eva-msg-key progress -eva-no-hit-log
  run "$name" candidate "$evidence/control-parity-$name.hit-log" \
    -eva-memexec -eva-msg-key progress
done
printf 'Recorded resolver controls\n'

# Positive controls: the trap must abort the run with exit status 1. The
# resolver serves the known request and the marking of postconditions:
# their controls run on the legacy path.
for phase in request analysis collection post-analysis initialization; do
  status=0
  legacy_path=()
  case "$phase" in
    request|post-analysis) legacy_path=(-eva-no-hit-log) ;;
  esac
  run legacy-reads "trap:$phase" "$evidence/control-$phase" \
    "${candidate_options[@]}" "${legacy_path[@]}" || status=$?
  printf '%s\n' "$status" > "$evidence/control-$phase.status"
  printf 'Recorded control %s (exit %s)\n' "$phase" "$status"
done

# The plug-in battery under the trap of every read but those of the readers
# that other changes migrate: the candidate must complete it; on the legacy
# path, the trap must abort the run.
for path in hit-log legacy; do
  status=0
  legacy_path=()
  if [ "$path" = legacy ]; then legacy_path=(-eva-no-hit-log); fi
  run "$plugin_fixture" plugins-trap "$evidence/control-plugins-trap-$path" \
    "${candidate_options[@]}" "${legacy_path[@]}" || status=$?
  printf '%s\n' "$status" > "$evidence/control-plugins-trap-$path.status"
  printf 'Recorded control plugins-trap on %s (exit %s)\n' "$path" "$status"
done

# The zero-read gate must fail while legacy reads remain: record the exit
# status of the gate alone, which compare.py checks against the evidence.
status=0
python3 -I "$prototype/compare.py" --require-zero-reads --no-write \
  "$evidence" "${fixtures[@]}" "$plugin_fixture" \
  > "$evidence/zero-read-gate.log" || status=$?
printf '%s\n' "$status" > "$evidence/zero-read-gate.status"

python3 -I "$prototype/compare.py" "$evidence" "${fixtures[@]}" "$plugin_fixture"
