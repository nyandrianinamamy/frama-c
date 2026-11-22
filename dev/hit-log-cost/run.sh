#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Campaign of ticket #100: the wall-clock and processor time that the
# recording of option -eva-hit-log adds to Eva, where it goes, and how much
# each candidate optimization could save at most. It measures, it changes
# nothing in the branch.
#
# Corpus: gzip 1.2.4 and monocypher, from the open-source case studies, with
# the parse and Eva options of their .frama-c/GNUmakefile (see
# [program_args]), the default domain alone, memexec on. Configurations:
#   - dev: a build of dev at the base of the branch;
#   - off, on: the build of this checkout, recording off and on.
# Each run loads the probe phases.ml, which notes the time and the counters
# of the GC at the boundaries of the phases through public hooks only.
#
# A measurement build, never part of the branch, is this checkout with
# measure.patch applied, built apart. Its environment variables time the
# parts of the iteration and the passes after it (HIT_LOG_COST_TIMERS), and
# skip one part of the recording, with wrong answers (HIT_LOG_COST_ABLATE).
#
# Stages, in this order unless -s is given:
#   build    builds this checkout, the measurement build, the dev build if
#            -d is not given, and the probe for each;
#   timing   runs, in each repetition and for each program, as many times
#            as its specification says (-p): with recording off, dev, off
#            and the measurement build with timers (meter); with recording
#            on, on and meter; the measurement build without any variable
#            (plain), off and on; each ablation, with the timers;
#   hits     one run per program and configuration with the progress
#            messages, counted on the fly and not kept;
#   perf     one profile per program, recording off and on, of this
#            checkout, with perf record; only its summary is kept;
#   report   writes the tables, see report.py.
#
# The specification of a program is
#   NAME:OFF:ON:PLAIN:ABLATION-RUNS:ABLATIONS:PERF-FREQUENCY
# with the number of repetitions of the runs with recording off, of those
# with recording on, of the plain runs, and of each ablation; ABLATIONS is a
# comma-separated list, or "all" for those of -a. An ablation A+B skips the
# parts A and B; its saving is taken against the run of ablation A. The
# default is the campaign of #100: monocypher runs for more than 30 minutes
# with recording on, so these runs and its ablations are not repeated; its
# ablations are state-bases, which removes most of the time on its profile,
# projection, and each other part on top of state-bases; its plain runs are
# left to gzip.
# A run whose directory holds a status file with status 0 is not run again:
# the campaign resumes where it stopped.
#
# The commands run are those of an agent shell: the opam switch of the main
# checkout must be active (see AGENTS.md); its path is taken from
# OPAM_SWITCH_PREFIX.

set -euo pipefail

THIS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(git -C "$THIS_DIR" rev-parse --show-toplevel)

OSCS=
DEV_INSTALL=
DEV_REV=375ab36aa5
WORK=/dev/shm/hit-log-cost
OUT=
PROGRAMS="gzip:3:3:3:3:all:99"
MONO_ABLATIONS=state-bases,projection
for ab in footprint footprint-call projection call-starts hits legacy \
          zone-bases; do
  MONO_ABLATIONS+=",state-bases+$ab"
done
PROGRAMS+=" monocypher:3:1:0:1:$MONO_ABLATIONS:25"
STAGES="build timing hits perf report"
ABLATIONS="footprint footprint-call projection call-starts hits legacy"
ABLATIONS+=" state-bases zone-bases"
CPU=4
MEASURE_SRC=
MEASURE_BUILD=
PERF_STACK=16384
TIMEOUT=150m
JOBS=8

usage () {
  cat <<EOF
Usage: $0 -c OSCS [options]
  -c DIR   checkout of the open-source case studies (read only)
  -d DIR   install directory (install/default) of a build of dev at the
           base of the branch; built from -r otherwise
  -r REV   revision of dev at the base of the branch (default $DEV_REV)
  -w DIR   work directory for builds, runs and profiles (default $WORK)
  -o DIR   results directory (default WORK/results)
  -p LIST  specifications of the programs, among gzip and monocypher
           (default "$PROGRAMS")
  -s LIST  stages among "$STAGES" (default all)
  -a LIST  ablations (default "$ABLATIONS")
  -u CPU   processor the runs are pinned to (default $CPU)
  -m DIR   source tree of the measurement build (default: a worktree
           hit-log-cost-measure beside this checkout, made if missing)
  -b DIR   build directory of the measurement build (default WORK/measure)
  -k SIZE  perf stack dump size in bytes (default $PERF_STACK)
  -t TIME  timeout of a run (default $TIMEOUT)
EOF
}

while getopts "c:d:r:w:o:p:s:a:u:m:b:k:t:h" opt; do
  case $opt in
    c) OSCS=$OPTARG;;
    d) DEV_INSTALL=$OPTARG;;
    r) DEV_REV=$OPTARG;;
    w) WORK=$OPTARG;;
    o) OUT=$OPTARG;;
    p) PROGRAMS=$OPTARG;;
    s) STAGES=$OPTARG;;
    a) ABLATIONS=$OPTARG;;
    u) CPU=$OPTARG;;
    m) MEASURE_SRC=$OPTARG;;
    b) MEASURE_BUILD=$OPTARG;;
    k) PERF_STACK=$OPTARG;;
    t) TIMEOUT=$OPTARG;;
    h) usage; exit 0;;
    *) usage; exit 2;;
  esac
done

[ -n "$OSCS" ] || { usage; exit 2; }
[ -n "${OPAM_SWITCH_PREFIX:-}" ] ||
  { echo "activate the opam switch first, see AGENTS.md" >&2; exit 2; }
OUT=${OUT:-$WORK/results}
MEASURE_SRC=${MEASURE_SRC:-$(dirname "$REPO")/hit-log-cost-measure}
MEASURE_BUILD=${MEASURE_BUILD:-$WORK/measure}
BRANCH_INSTALL=$REPO/_build/install/default
MEASURE_INSTALL=$MEASURE_BUILD/install/default
DEV_SRC=$(dirname "$REPO")/hit-log-cost-dev
DEV_BUILD=$WORK/dev
DEV_INSTALL=${DEV_INSTALL:-$DEV_BUILD/install/default}
mkdir -p "$WORK" "$OUT/runs"

has_stage () { [[ " $STAGES " == *" $1 "* ]]; }

# Fields of the specification $1: name, repetitions off, on, plain, of the
# ablations, the ablations (space-separated), perf frequency.
spec () {
  local name off on plain abl_reps abl freq
  IFS=: read -r name off on plain abl_reps abl freq <<< "$1"
  [ "$abl" != all ] || abl=$ABLATIONS
  echo "$name" "$off" "$on" "$plain" "$abl_reps" "$freq" "${abl//,/ }"
}
NAMES=$(for p in $PROGRAMS; do spec "$p" | cut -d' ' -f1; done | xargs)
log () { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/campaign.log"; }

# Sets the environment that runs the frama-c of the install directory $1.
activate () {
  local install=$1
  export OCAMLPATH="$install/lib:$OPAM_SWITCH_PREFIX/lib"
  local locations="frama-c:share:$install/share/frama-c"
  locations+=":frama-c:lib:$install/lib/frama-c"
  locations+=":frama-c:libexec:$install/lib/frama-c"
  export DUNE_DIR_LOCATIONS=$locations
  export FRAMAC_SHARE="$install/share/frama-c"
  export FRAMAC_PLUGIN="$install/lib/frama-c/plugins"
  export DUNE_OCAML_HARDCODED="$OPAM_SWITCH_PREFIX/lib"
  export DUNE_OCAML_STDLIB="$OPAM_SWITCH_PREFIX/lib/ocaml"
}

install_of () {
  case $1 in
    dev) echo "$DEV_INSTALL";;
    branch) echo "$BRANCH_INSTALL";;
    measure) echo "$MEASURE_INSTALL";;
  esac
}

# ----- Build -------------------------------------------------------------

HEAD=$(git -C "$REPO" rev-parse HEAD)

build_tree () { # source directory, build directory or "", log name
  local src=$1 dir=$2 name=$3
  local args=(-j "$JOBS")
  [ -z "$dir" ] || args+=(--build-dir="$dir")
  log "build $name in $src"
  (cd "$src" && DUNE_CACHE=disabled dune build "${args[@]}" @install) \
    > "$OUT/build-$name.log" 2>&1 ||
    { log "build $name failed, see $OUT/build-$name.log"; exit 1; }
}

worktree () { # directory, revision
  local dir=$1 rev=$2
  if [ ! -d "$dir" ]; then
    git -C "$REPO" worktree add --detach "$dir" "$rev" \
      >> "$OUT/campaign.log" 2>&1
  fi
  local at want
  at=$(git -C "$dir" rev-parse HEAD)
  want=$(git -C "$REPO" rev-parse "$rev")
  [ "$at" = "$want" ] || { log "$dir is not at $rev"; exit 1; }
}

build_probe () { # build name
  local install dir
  install=$(install_of "$1")
  dir=$WORK/probe/$1
  mkdir -p "$dir"
  cp "$THIS_DIR/phases.ml" "$dir/"
  (activate "$install" && cd "$dir" &&
     ocamlfind ocamlopt -shared -package frama-c-eva.core,unix \
       -open Frama_c_kernel phases.ml -o phases.cmxs) \
    > "$OUT/build-probe-$1.log" 2>&1 ||
    { log "probe for $1 failed, see $OUT/build-probe-$1.log"; exit 1; }
}

if has_stage build; then
  if ! git -C "$REPO" diff --quiet HEAD -- src plugins; then
    log "the checkout has changes in src or plugins: commit them first"
    exit 1
  fi
  build_tree "$REPO" "" branch
  [ -d "$MEASURE_SRC" ] || worktree "$MEASURE_SRC" "$HEAD"
  # The measurement build is the analyzer of this checkout: its revision may
  # be an earlier one whose src and plugins are those of HEAD.
  mrev=$(git -C "$MEASURE_SRC" rev-parse HEAD)
  if ! git -C "$REPO" diff --quiet "$mrev" "$HEAD" -- src plugins; then
    log "$MEASURE_SRC at $mrev differs from $HEAD in src or plugins"
    exit 1
  fi
  if git -C "$MEASURE_SRC" diff --quiet; then
    git -C "$MEASURE_SRC" apply "$THIS_DIR/measure.patch"
  elif ! git -C "$MEASURE_SRC" apply --reverse --check \
         "$THIS_DIR/measure.patch" 2> /dev/null; then
    log "$MEASURE_SRC has changes other than measure.patch"
    exit 1
  fi
  build_tree "$MEASURE_SRC" "$MEASURE_BUILD" measure
  if [ ! -x "$DEV_INSTALL/bin/frama-c" ]; then
    worktree "$DEV_SRC" "$DEV_REV"
    build_tree "$DEV_SRC" "$DEV_BUILD" dev
  fi
  for b in dev branch measure; do build_probe $b; done
fi

# Revisions of the campaign.
{
  echo "branch	$HEAD"
  echo "dev	$(git -C "$REPO" rev-parse "$DEV_REV")"
  mrev=$(git -C "$MEASURE_SRC" rev-parse HEAD 2> /dev/null || true)
  echo "measure	$mrev + dev/hit-log-cost/measure.patch"
  echo "oscs	$(git -C "$OSCS" rev-parse HEAD)"
  echo "cpu	$CPU	$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
  echo "perf	--call-graph dwarf,$PERF_STACK"
  echo "programs	$PROGRAMS"
} > "$OUT/revisions.tsv"

# ----- Programs ----------------------------------------------------------

# The options of the targets of .frama-c/GNUmakefile at the revision of the
# case studies used for #100 (3dcefdb6), parse and Eva steps in one command:
# MACHDEP, CPPFLAGS (where $(DIR), the directory of analysis.mk, is the
# analysis-scripts directory of the share path), FCFLAGS, the sources, and
# the EVAFLAGS that the GNUmakefile adds. Not kept:
#   - the defaults of EVAFLAGS in analysis.mk (no progress, no initial and
#     final states, no alarms as warnings), so that the passes print the
#     values at the end of each function, as in the measurement of #98;
#   - for gzip, -nonterm-ignore do_exit: an option of the nonterm plugin,
#     which the configuration of #87 does not load and the target does not
#     run;
#   - the outputs of the target (-save, -eva-flamegraph, the reports after
#     -then).
program_args () { # program, share directory
  local p share=$2
  case $1 in
    gzip)
      p=$OSCS/gzip124
      echo -machdep; echo x86_32
      local cpp="-include$share/libc/string.h -DSTDC_HEADERS=1"
      cpp+=" -DHAVE_UNISTD_H=1 -DDIRENT=1 -DNO_UTIME=1"
      cpp+=" -I$share/libc -I$share/analysis-scripts/"
      echo "-cpp-extra-args=$cpp"
      echo "-add-symbolic-path=$p:."
      echo -main; echo eva_main
      echo "$share/libc/stdlib.c"; echo "$p/.frama-c/fc_stubs.c"
      for f in bits crypt deflate getopt gzip inflate lzw trees unlzh unlzw \
               unpack unzip util zip; do
        echo "$p/$f.c"
      done
      echo -eva; echo -eva-slevel; echo 2; echo -eva-no-alloc-returns-null;;
    monocypher)
      p=$OSCS/monocypher
      echo -machdep; echo x86_64
      echo "-cpp-extra-args=-I$p/src -I$p/src/optional"
      echo "-add-symbolic-path=$p:."
      echo -kernel-warn-key; echo annot:missing-spec=abort
      echo -kernel-warn-key; echo typing:implicit-function-declaration=abort
      echo -no-warn-signed-overflow
      echo "$p/src/monocypher.c"; echo "$p/src/optional/sha512.c"
      echo "$p/tests/test.c"
      echo -eva; echo -eva-slevel; echo 8; echo -eva-split-return; echo auto
      echo -eva-warn-key; echo signed-overflow=inactive
      echo -eva-warn-key; echo builtins:missing-spec=abort;;
    *) echo "unknown program $1" >&2; exit 2;;
  esac
}

# The command of program $1 in mode $2 (off, on) with the frama-c of build $3.
command_of () {
  local prog=$1 mode=$2 build=$3 install share
  install=$(install_of "$build")
  share=$(activate "$install" && "$install/bin/frama-c" -print-share-path)
  echo "$install/bin/frama-c"
  echo -no-autoload-plugins; echo -load-plugin=eva,inout,scope
  echo -load-module; echo "$WORK/probe/$build/phases.cmxs"
  program_args "$prog" "$share"
  echo -eva-memexec
  [ "$mode" = off ] || echo -eva-hit-log
}

# ----- Runs --------------------------------------------------------------

# [timed ID BUILD PROGRAM MODE VAR=VALUE...] runs program in mode with build,
# pinned, with the given environment, in directory runs/ID.
timed () {
  local id=$1 build=$2 prog=$3 mode=$4; shift 4
  local dir=$OUT/runs/$id
  if [ -f "$dir/status" ] && [ "$(cat "$dir/status")" = 0 ]; then return; fi
  rm -rf "$dir"; mkdir -p "$dir"
  local cmd=()
  mapfile -t cmd < <(command_of "$prog" "$mode" "$build")
  cmd+=(-eva-statistics-file "$dir/stats.csv")
  printf '%s\n' "$@" > "$dir/env"
  printf '%q ' "${cmd[@]}" > "$dir/command"
  log "run $id"
  local status=0
  (activate "$(install_of "$build")" &&
     cd "$dir" &&
     env HIT_LOG_COST_PHASES="$dir/phases.tsv" "$@" \
       /usr/bin/time -o "$dir/time" \
       -f 'elapsed=%e user=%U sys=%S maxrss=%M majfl=%F minfl=%R exit=%x' \
       taskset -c "$CPU" timeout "$TIMEOUT" "${cmd[@]}" > "$dir/log" 2>&1) ||
    status=$?
  echo "$status" > "$dir/status"
  [ "$status" = 0 ] || log "run $id failed with status $status"
}

meter () { # id
  echo "HIT_LOG_COST_TIMERS=$OUT/runs/$1/timers.tsv"
}

if has_stage timing; then
  max=$(for p in $PROGRAMS; do spec "$p" | cut -d' ' -f2-5 | tr ' ' '\n'; done |
          sort -n | tail -1)
  for rep in $(seq 1 "$max"); do
    for p in $PROGRAMS; do
      read -r prog off on plain abl_reps _ abl <<< "$(spec "$p")"
      if [ "$rep" -le "$off" ]; then
        timed "dev-$prog-$rep" dev "$prog" off
        timed "off-$prog-$rep" branch "$prog" off
        timed "meter-off-$prog-$rep" measure "$prog" off \
          "$(meter "meter-off-$prog-$rep")"
      fi
      if [ "$rep" -le "$on" ]; then
        timed "on-$prog-$rep" branch "$prog" on
        timed "meter-on-$prog-$rep" measure "$prog" on \
          "$(meter "meter-on-$prog-$rep")"
      fi
      if [ "$rep" -le "$plain" ]; then
        timed "plain-off-$prog-$rep" measure "$prog" off
        timed "plain-on-$prog-$rep" measure "$prog" on
      fi
      if [ "$rep" -le "$abl_reps" ]; then
        for ab in $abl; do
          timed "ablate-$ab-$prog-$rep" measure "$prog" on \
            "$(meter "ablate-$ab-$prog-$rep")" HIT_LOG_COST_ABLATE="${ab//+/,}"
        done
      fi
    done
  done
fi

# ----- Hits from the progress messages -----------------------------------

if has_stage hits; then
  for prog in $NAMES; do
    for cfg in dev off on; do
      dir=$OUT/runs/hits-$cfg-$prog
      if [ -f "$dir/status" ] && [ "$(cat "$dir/status")" = 0 ]; then
        continue
      fi
      rm -rf "$dir"; mkdir -p "$dir"
      build=branch; [ "$cfg" != dev ] || build=dev
      mode=$cfg; [ "$cfg" != dev ] || mode=off
      mapfile -t cmd < <(command_of "$prog" "$mode" "$build")
      cmd+=(-eva-msg-key=progress)
      printf '%q ' "${cmd[@]}" > "$dir/command"
      log "run hits-$cfg-$prog"
      status=0
      (activate "$(install_of "$build")" && cd "$dir" &&
         set -o pipefail &&
         timeout "$TIMEOUT" "${cmd[@]}" 2>&1 |
           awk '/Reusing old results for call to/ { hits++ }
                /Recording results for/ { recorded++ }
                /Computing for function/ { computing++ }
                END { printf "hits\t%d\nrecorded\t%d\ncomputing\t%d\n",
                        hits, recorded, computing }' > "$dir/counts.tsv") ||
        status=$?
      echo "$status" > "$dir/status"
      [ "$status" = 0 ] || log "run hits-$cfg-$prog failed with status $status"
    done
  done
fi

# ----- Profiles ----------------------------------------------------------

if has_stage perf; then
  mkdir -p "$WORK/perf"
  for p in $PROGRAMS; do
    read -r prog _ _ _ _ freq _ <<< "$(spec "$p")"
    for mode in off on; do
      dir=$OUT/runs/perf-$mode-$prog
      if [ -f "$dir/status" ] && [ "$(cat "$dir/status")" = 0 ]; then
        continue
      fi
      rm -rf "$dir"; mkdir -p "$dir"
      data=$WORK/perf/$mode-$prog.data
      mapfile -t cmd < <(command_of "$prog" "$mode" branch)
      printf '%q ' "${cmd[@]}" > "$dir/command"
      log "run perf-$mode-$prog"
      status=0
      (activate "$BRANCH_INSTALL" && cd "$dir" &&
         HIT_LOG_COST_PHASES="$dir/phases.tsv" \
           perf record -e cpu-clock -F "$freq" -k CLOCK_REALTIME \
             --call-graph "dwarf,$PERF_STACK" -o "$data" -- \
             taskset -c "$CPU" timeout "$TIMEOUT" "${cmd[@]}" \
             > "$dir/log" 2> "$dir/perf-record.log") || status=$?
      if [ "$status" = 0 ]; then
        log "summary of perf-$mode-$prog"
        (set -o pipefail &&
           perf script -i "$data" -F time,ip,sym --no-inline 2> /dev/null |
             python3 "$THIS_DIR/report.py" perf-summary \
               --phases "$dir/phases.tsv" --freq "$freq" \
               > "$dir/perf.tsv") || status=$?
      fi
      rm -f "$data"
      echo "$status" > "$dir/status"
      [ "$status" = 0 ] || log "run perf-$mode-$prog failed with status $status"
    done
  done
fi

# ----- Tables ------------------------------------------------------------

if has_stage report; then
  python3 "$THIS_DIR/report.py" tables --results "$OUT" \
    --programs "$NAMES" --ablations "$ABLATIONS" > "$OUT/tables.md"
  log "tables written to $OUT/tables.md"
fi
