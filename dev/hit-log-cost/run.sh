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
# Corpus: gzip 1.2.4, monocypher, polarssl and chrony, from the open-source
# case studies, with the parse and Eva options of their .frama-c/GNUmakefile
# (see [program_args]), the default domain alone, memexec on. Every analysis
# runs with -cache-size 8, the setting of
# share/analysis-scripts/analysis.mk:125 used by the case studies.
# Configurations:
#   - dev: a build of dev at the base of the branch;
#   - off, on: the build of this checkout, recording off and on;
#   - base: a build of the branch at an earlier revision (-B), recording on,
#     to compare this checkout with it in the same campaign.
# Each run loads the probe phases.ml, which notes the time and the counters
# of the GC at the boundaries of the phases through public hooks only.
#
# A measurement build, never part of the branch, is this checkout with
# measure.patch applied, built apart; option -M leaves it out, as when the
# patch does not apply to this checkout. Its environment variables time the
# parts of the iteration and the passes after it (HIT_LOG_COST_TIMERS), and
# skip one part of the recording, with wrong answers (HIT_LOG_COST_ABLATE).
# The revision of each build is noted when it is built, in revisions.tsv and
# in the file revision of each run, with the cache size in cache-size.
#
# Stages, in this order unless -s is given:
#   build    builds this checkout, the measurement build, the dev build if
#            -d is not given, and the probe for each;
#   timing   runs, in each repetition and for each program, as many times
#            as its specification says (-p): with recording off, dev, off
#            and the measurement build with timers (meter); with recording
#            on, on and meter; the measurement build without any variable
#            (plain), off and on; each ablation, with the timers; the base
#            build, recording on (base);
#   hits     one run per program and configuration with the progress
#            messages, counted on the fly and not kept: the hits (Reusing
#            old results), the calls analysed by their body (Recording
#            results), and the calls analysed by their body or specification
#            that are not hits (computing for function);
#   perf     one profile per program, recording off and on, of this
#            checkout, with perf record; only its summary is kept;
#   report   writes the tables, see report.py.
#
# The specification of a program is
#   NAME:OFF:ON:PLAIN:ABLATION-RUNS:ABLATIONS:PERF-FREQUENCY[:BASE]
# with the number of repetitions of the runs with recording off, of those
# with recording on, of the plain runs, of each ablation, and of the runs of
# the base build (0 if omitted); ABLATIONS is a comma-separated list, or
# "all" for those of -a. With -M, the runs with recording on have no meter
# runs, and PLAIN and ABLATION-RUNS must be 0. An ablation A+B skips the
# parts A and B; its saving is taken against the run of ablation A. The
# default is the campaign of #100: three repetitions of every run on both
# programs, and each ablation of -a taken against the control (see
# [ABLATIONS] for the choice).
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
BASE_INSTALL=
BASE_REV=
NO_MEASURE=
WORK=/dev/shm/hit-log-cost
OUT=
PROGRAMS="gzip:3:3:3:3:all:99 monocypher:3:3:3:3:all:25"
STAGES="build timing hits perf report"
# The ablations of the campaign, chosen on a first profile at 0f19534e56
# (one run of each program with the timers, recording off and on, and one
# run of each ablation on gzip): one for each part of the recording that
# #100 names (footprint, projection, call-starts, hits, legacy), the walk of
# the created and removed blocks (walk), and the largest part on both
# programs, the set of the blocks of the footprint at each point
# (zone-bases). footprint-call is left out: the footprint itself (parts
# hooks and footprint) adds at most 1.6 s, which footprint bounds, and the
# iteration with footprint-call was 1.5 s slower than without it on gzip.
ABLATIONS="footprint projection call-starts hits legacy walk zone-bases"
CPU=4
MEASURE_SRC=
MEASURE_BUILD=
PERF_STACK=16384
# Frames read from each call chain of a profile. perf script reads 127 by
# default (kernel.perf_event_max_stack), and the chains of the iteration are
# deeper: at 127, 5 % of the samples of gzip had a chain that reaches the
# start of the program; at 4096, 80 %, with a dump of 16 or 64 KiB alike.
PERF_MAX_STACK=4096
TIMEOUT=20m
JOBS=8
# Option -cache-size of every analysis, see [command_of].
CACHE_SIZE=8

usage () {
  cat <<EOF
Usage: $0 -c OSCS [options]
  -c DIR   checkout of the open-source case studies (read only)
  -d DIR   install directory (install/default) of a build of dev at the
           base of the branch; built from -r otherwise
  -r REV   revision of dev at the base of the branch (default $DEV_REV)
  -B DIR   install directory (install/default) of a build of the branch at
           an earlier revision, for the base runs
  -R REV   revision of the build of -B, noted with its runs
  -M       no measurement build: no meter, plain or ablation runs
  -w DIR   work directory for builds, runs and profiles (default $WORK)
  -o DIR   results directory (default WORK/results)
  -p LIST  specifications of the programs, among gzip, monocypher, polarssl
           and chrony
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

while getopts "c:d:r:B:R:Mw:o:p:s:a:u:m:b:k:t:h" opt; do
  case $opt in
    c) OSCS=$OPTARG;;
    d) DEV_INSTALL=$OPTARG;;
    r) DEV_REV=$OPTARG;;
    B) BASE_INSTALL=$OPTARG;;
    R) BASE_REV=$OPTARG;;
    M) NO_MEASURE=yes;;
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
DEV_GIVEN=$DEV_INSTALL
DEV_INSTALL=${DEV_INSTALL:-$DEV_BUILD/install/default}
mkdir -p "$WORK" "$OUT/runs"

has_stage () { [[ " $STAGES " == *" $1 "* ]]; }

# Fields of the specification $1: name, repetitions off, on, plain, of the
# ablations, of the base runs, perf frequency, the ablations
# (space-separated).
spec () {
  local name off on plain abl_reps abl freq base
  IFS=: read -r name off on plain abl_reps abl freq base <<< "$1"
  [ "$abl" != all ] || abl=$ABLATIONS
  echo "$name" "$off" "$on" "$plain" "$abl_reps" "${base:-0}" "$freq" \
       "${abl//,/ }"
}
NAMES=$(for p in $PROGRAMS; do spec "$p" | cut -d' ' -f1; done | xargs)
for p in $PROGRAMS; do
  read -r prog _ _ plain abl_reps base _ <<< "$(spec "$p")"
  if [ -n "$NO_MEASURE" ] && [ "$plain$abl_reps" != 00 ]; then
    echo "$prog: plain and ablation runs need the measurement build (-M)" >&2
    exit 2
  fi
  if [ "$base" != 0 ] && [ -z "$BASE_INSTALL" ]; then
    echo "$prog: base runs need the base build (-B)" >&2
    exit 2
  fi
done
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
    base) echo "$BASE_INSTALL";;
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

# The revision of each build, noted when it is built, see [stamp].
REVS=$WORK/revisions
mkdir -p "$REVS"

if has_stage build; then
  if ! git -C "$REPO" diff --quiet HEAD -- src plugins; then
    log "the checkout has changes in src or plugins: commit them first"
    exit 1
  fi
  build_tree "$REPO" "" branch
  echo "$HEAD" > "$REVS/branch"
  builds="dev branch"
  if [ -z "$NO_MEASURE" ]; then
    [ -d "$MEASURE_SRC" ] || worktree "$MEASURE_SRC" "$HEAD"
    # The measurement build is the analyzer of this checkout: its revision
    # may be an earlier one whose src and plugins are those of HEAD.
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
    patch_id=$(git hash-object "$THIS_DIR/measure.patch")
    echo "$mrev + measure.patch $patch_id" > "$REVS/measure"
    builds+=" measure"
  else
    echo "none (option -M)" > "$REVS/measure"
  fi
  if [ -n "$BASE_INSTALL" ]; then
    echo "${BASE_REV:-unknown} (stated with -R, install $BASE_INSTALL" \
         "given with -B)" > "$REVS/base"
    builds+=" base"
  fi
  if [ -z "$DEV_GIVEN" ]; then
    worktree "$DEV_SRC" "$DEV_REV"
    build_tree "$DEV_SRC" "$DEV_BUILD" dev
    git -C "$DEV_SRC" rev-parse HEAD > "$REVS/dev"
  else
    echo "$(git -C "$REPO" rev-parse "$DEV_REV") (stated with -r, install" \
         "$DEV_INSTALL given with -d)" > "$REVS/dev"
  fi
  for b in $builds; do build_probe "$b"; done
  # Revisions of the campaign.
  {
    echo "branch	$(cat "$REVS/branch")"
    echo "dev	$(cat "$REVS/dev")"
    echo "measure	$(cat "$REVS/measure")"
    [ -z "$BASE_INSTALL" ] || echo "base	$(cat "$REVS/base")"
    echo "oscs	$(git -C "$OSCS" rev-parse HEAD)"
    echo "cpu	$CPU	$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
    echo "perf	--call-graph dwarf,$PERF_STACK," \
         "perf script --max-stack $PERF_MAX_STACK"
    echo "programs	$PROGRAMS"
    echo "ablations	$ABLATIONS"
    echo "cache	-cache-size $CACHE_SIZE" \
         "(share/analysis-scripts/analysis.mk:125)"
    echo "built	$(date -Iseconds)"
  } > "$OUT/revisions.tsv"
fi

# ----- Programs ----------------------------------------------------------

# The options of the targets of .frama-c/GNUmakefile at the revision of the
# case studies used for #100 (3dcefdb6), parse and Eva steps in one command:
# MACHDEP, CPPFLAGS (where $(DIR), the directory of analysis.mk, is the
# analysis-scripts directory of the share path), FCFLAGS, the sources, and
# the EVAFLAGS that the GNUmakefile adds. Of the defaults of EVAFLAGS in
# analysis.mk, [command_of] keeps -cache-size 8 only. Not kept:
#   - the other defaults of EVAFLAGS in analysis.mk (no progress, no initial
#     and final states, no alarms as warnings), so that the passes print the
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
    polarssl)
      # Target polarssl-server. The header fc_stubs.h is a prerequisite of
      # the parse rule, and thus one of its sources.
      p=$OSCS/polarssl
      echo -machdep; echo x86_32
      echo "-cpp-extra-args=-CC -I$p"
      echo -compilation-db; echo "$p"
      echo "-add-symbolic-path=$p:."
      echo -kernel-warn-key; echo annot:missing-spec=abort
      echo -kernel-warn-key; echo typing:implicit-function-declaration=abort
      echo "$p/.frama-c/fc_stubs.h"
      for f in "$p"/library/*.c; do echo "$f"; done | LC_ALL=C sort
      echo "$p/programs/ssl/ssl_server.c"
      local spec=my_set_session,my_get_session,aes_setkey_enc,aes_setkey_dec
      spec+=,aes_crypt_cbc,des3_crypt_ecb,des3_crypt_cbc,des_setkey,arc4_crypt
      spec+=,ssl_free,x509_free,x509parse_crt,x509parse_key
      spec+=,x509parse_verifycrl,hardclock,sha4_update,sha4_process
      spec+=,sha1_process,sha1_finish,aes_crypt_ecb,md5_process
      spec+=,ctr_drbg_random,dhm_check_range,dhm_make_params,mpi_free
      spec+=,mpi_exp_mod,mpi_fill_random,mpi_read_string,mpi_read_binary
      spec+=,mpi_msb,mpi_write_binary,mpi_cmp_mpi,mpi_cmp_abs,mpi_copy
      spec+=,mpi_sub_mpi,mpi_mod_mpi,mpi_mul_mpi,mpi_add_abs,mpi_sub_abs
      spec+=,camellia_crypt_cbc,camellia_feistel,sha4,error_strerror
      echo -eva
      echo -eva-subdivide-non-linear; echo 16
      echo -eva-ilevel; echo 13
      echo -eva-no-alloc-returns-null
      echo -eva-use-spec; echo "$spec"
      echo -eva-slevel; echo 2;;
    chrony)
      # Target chrony-ntp-core. Not kept: the options -eva-domains and
      # -eva-domains-function, which enable domains other than cvalue, which
      # -eva-hit-log refuses.
      p=$OSCS/chrony
      echo -machdep; echo x86_64
      echo "-cpp-extra-args=-D_XOPEN_SOURCE=200112L -DNB_TESTS=3"
      echo "-cpp-command=gcc -E -C -I$p"
      echo -cpp-frama-c-compliant
      echo "-add-symbolic-path=$p:."
      echo -kernel-warn-key; echo typing:implicit-function-declaration=abort
      echo -warn-special-float; echo none
      echo "$p/test/unit/test.c"
      for f in string stdlib stdio glob netdb; do echo "$share/libc/$f.c"; done
      for f in addrfilt array clientlog cmdparse conf hash_intmd5 keys local \
               memory nameserv ntp_io reference regress sched smooth sources \
               sourcestats util stubs; do
        echo "$p/$f.c"
      done
      echo "$p/.frama-c/fc_stubs.c"; echo "$p/test/unit/ntp_core.c"
      echo -eva
      echo -eva-mlevel; echo 1
      echo -eva-use-spec; echo atoi,malloc,free,calloc,Transform,SCH_AddTimeout
      echo -eva-warn-key=alarm
      echo -eva-malloc-functions
      echo malloc,realloc,Malloc,Malloc2,Realloc,Realloc2
      echo -eva-warn-key; echo builtins:missing-spec=abort
      echo -eva-warn-key; echo malloc:weak
      echo -main; echo eva_main;;
    *) echo "unknown program $1" >&2; exit 2;;
  esac
}

# The command of program $1 in mode $2 (off, on) with the frama-c of build $3,
# with the cache setting of the case studies.
command_of () {
  local prog=$1 mode=$2 build=$3 install share
  install=$(install_of "$build")
  share=$(activate "$install" && "$install/bin/frama-c" -print-share-path)
  echo "$install/bin/frama-c"
  echo -no-autoload-plugins; echo -load-plugin=eva,inout,scope
  echo -load-module; echo "$WORK/probe/$build/phases.cmxs"
  program_args "$prog" "$share"
  echo -cache-size; echo "$CACHE_SIZE"
  echo -eva-memexec
  [ "$mode" = off ] || echo -eva-hit-log
}

# ----- Runs --------------------------------------------------------------

# Notes in run directory $1 the revision of build $2, as noted when it was
# built, and the cache size of the analyses.
stamp () {
  local dir=$1 build=$2
  cat "$REVS/$build" > "$dir/revision" 2> /dev/null ||
    echo "unknown: build $build not noted in $REVS" > "$dir/revision"
  echo "$CACHE_SIZE" > "$dir/cache-size"
}

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
  stamp "$dir" "$build"
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
  max=$(for p in $PROGRAMS; do spec "$p" | cut -d' ' -f2-6 | tr ' ' '\n'; done |
          sort -n | tail -1)
  for rep in $(seq 1 "$max"); do
    for p in $PROGRAMS; do
      read -r prog off on plain abl_reps base _ abl <<< "$(spec "$p")"
      if [ "$rep" -le "$off" ]; then
        timed "dev-$prog-$rep" dev "$prog" off
        timed "off-$prog-$rep" branch "$prog" off
        [ -n "$NO_MEASURE" ] ||
          timed "meter-off-$prog-$rep" measure "$prog" off \
            "$(meter "meter-off-$prog-$rep")"
      fi
      if [ "$rep" -le "$base" ]; then
        timed "base-$prog-$rep" base "$prog" on
      fi
      if [ "$rep" -le "$on" ]; then
        timed "on-$prog-$rep" branch "$prog" on
        [ -n "$NO_MEASURE" ] ||
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
      stamp "$dir" "$build"
      log "run hits-$cfg-$prog"
      status=0
      (activate "$(install_of "$build")" && cd "$dir" &&
         set -o pipefail &&
         timeout "$TIMEOUT" "${cmd[@]}" 2>&1 |
           awk '/Reusing old results for call to/ { hits++ }
                /Recording results for/ { recorded++ }
                /computing for function/ { computing++ }
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
    read -r prog _ _ _ _ _ freq _ <<< "$(spec "$p")"
    for mode in off on; do
      dir=$OUT/runs/perf-$mode-$prog
      if [ -f "$dir/status" ] && [ "$(cat "$dir/status")" = 0 ]; then
        continue
      fi
      rm -rf "$dir"; mkdir -p "$dir"
      data=$WORK/perf/$mode-$prog.data
      mapfile -t cmd < <(command_of "$prog" "$mode" branch)
      printf '%q ' "${cmd[@]}" > "$dir/command"
      stamp "$dir" branch
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
           perf script -i "$data" -F time,ip,sym --no-inline \
             --max-stack "$PERF_MAX_STACK" 2> /dev/null |
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
    --specs "$PROGRAMS" --ablations "$ABLATIONS" > "$OUT/tables.md"
  log "tables written to $OUT/tables.md"
fi
