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
# off, and a separate candidate process runs under the continuous trap:
# armed once before the analysis, every legacy read, in any phase, aborts
# Eva. A third process compares the models of both in memory. The controls
# run in their own processes. compare.py then compares the answers and
# writes the report. Every process runs anew: the evidence directory must
# be new or empty; the default one is emptied first.
# Usage: acceptance.sh [evidence-dir]

set -euo pipefail

prototype="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$prototype/../../.."
prototype=plugins/inout/prototype-state-query
default_evidence=$prototype/evidence/acceptance
evidence="${1:-$default_evidence}"
if [ "$evidence" = "$default_evidence" ]; then rm -rf -- "$evidence"; fi
if [ -n "$(ls -A -- "$evidence" 2>/dev/null)" ]; then
  printf 'acceptance.sh: %s is not empty\n' "$evidence" >&2
  exit 2
fi
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
# producer must be reported, and so must a hit log that exports wrong
# statuses and callers; on the legacy path, InOut's collection reads the
# store. With memexec, InOut's answers and the analyses of f in
# pre-label.c and precondition.c must be the same on the legacy path and
# with the hit log. These controls log the reads without trapping them.
run legacy-reads wrong-producer "$evidence/control-wrong-producer" \
  "${candidate_options[@]}"
run selection wrong-producer "$evidence/control-wrong-producer-selection" \
  "${candidate_options[@]}"
run "$plugin_fixture" plugins-wrong-producer \
  "$evidence/control-wrong-producer-plugins" "${candidate_options[@]}"
run "$plugin_fixture" plugins-perturb-calls \
  "$evidence/control-perturb-calls-plugins" "${candidate_options[@]}"
run legacy-reads record "$evidence/control-legacy-path" \
  "${candidate_options[@]}" -eva-no-hit-log
for name in pre-label precondition; do
  run "$name" record "$evidence/control-parity-$name.legacy" \
    -eva-memexec -eva-msg-key progress -eva-no-hit-log
  run "$name" record "$evidence/control-parity-$name.hit-log" \
    -eva-memexec -eva-msg-key progress
done
printf 'Recorded resolver controls\n'

# The legacy store that the analysis writes from the hit log: the hit log
# then declines every request, which reads that store.
for name in "${fixtures[@]}"; do
  run "$name" store-check "$evidence/control-store-check-$name" \
    "${candidate_options[@]}"
done
run "$plugin_fixture" plugins-store-check \
  "$evidence/control-store-check-$plugin_fixture" "${candidate_options[@]}"
printf 'Recorded legacy-store controls\n'

# Sensitivity: the same batteries on the legacy path, with every read
# logged, show the reads that the guard sees in each phase.
run legacy-reads record "$evidence/control-sensitivity-legacy-reads" \
  "${candidate_options[@]}" -eva-no-hit-log
run "$plugin_fixture" plugins-record \
  "$evidence/control-sensitivity-$plugin_fixture" \
  "${candidate_options[@]}" -eva-no-hit-log
printf 'Recorded sensitivity controls\n'

# Positive controls: the trap must abort the run with exit status 1. The
# hit log serves every read: the controls of a phase run on the legacy
# path, where Eva reads its legacy store. No read happens during the
# initialization on either path.
for phase in request analysis collection post-analysis initialization; do
  status=0
  legacy_path=()
  case "$phase" in
    request | analysis | collection | post-analysis)
      legacy_path=(-eva-no-hit-log) ;;
  esac
  run legacy-reads "trap:$phase" "$evidence/control-$phase" \
    "${candidate_options[@]}" "${legacy_path[@]}" || status=$?
  printf '%s\n' "$status" > "$evidence/control-$phase.status"
  printf 'Recorded control %s (exit %s)\n' "$phase" "$status"
done

# The continuous trap of the candidates: the same command on the legacy
# path must abort; after the battery, a request on cleared results must
# abort with no read logged before it.
for name in legacy-reads "$plugin_fixture"; do
  prefix=
  if [ "$name" = "$plugin_fixture" ]; then prefix=plugins-; fi
  status=0
  run "$name" "${prefix}candidate" "$evidence/control-continuous-legacy-$name" \
    "${candidate_options[@]}" -eva-no-hit-log || status=$?
  printf '%s\n' "$status" > "$evidence/control-continuous-legacy-$name.status"
  status=0
  run "$name" "${prefix}tail-probe" "$evidence/control-tail-probe-$name" \
    "${candidate_options[@]}" || status=$?
  printf '%s\n' "$status" > "$evidence/control-tail-probe-$name.status"
  printf 'Recorded continuous-trap controls on %s\n' "$name"
done

# The zero-read gate: record the exit status of the gate alone, which
# compare.py checks against the evidence.
status=0
python3 -I "$prototype/compare.py" --require-zero-reads --no-write \
  "$evidence" "${fixtures[@]}" "$plugin_fixture" \
  > "$evidence/zero-read-gate.log" || status=$?
printf '%s\n' "$status" > "$evidence/zero-read-gate.status"

python3 -I "$prototype/compare.py" "$evidence" "${fixtures[@]}" "$plugin_fixture"
