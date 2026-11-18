#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Runs the checks of an Eva change and prints one line per step with its exit
# status. Ptests are forced to rerun. Logs are kept in a temporary directory.
#
# Usage: verify.sh [-q] [-b REV]
#   -q      quick: build, default Eva ptests and Eva native tests only
#   -b REV  base revision for the lint of changed files (default origin/dev)

set -u

QUICK=no
BASE=origin/dev
while getopts "qb:" opt; do
  case $opt in
    q) QUICK=yes ;;
    b) BASE=$OPTARG ;;
    *) echo "usage: $0 [-q] [-b REV]" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)" || exit 2
bash dev/check-env.sh || exit 2

export TERM=xterm
FC_FORCE_PTESTS="$(date +%s)"
export FC_FORCE_PTESTS

LOGS=$(mktemp -d)
failed=0

step () {
  local name=$1; shift
  local log="$LOGS/$name.log"
  if "$@" > "$log" 2>&1; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s (exit %s, %s)\n' "$name" "$?" "$log"
    failed=1
  fi
}

lint_changed () {
  git diff --name-only -z "$BASE" HEAD | git check-attr --stdin -z -a \
    | dune exec --root tools/lint -- frama-c-lint -s
}

echo "revision $(git rev-parse --short HEAD), dune $(dune --version)"
echo "logs in $LOGS"

step build dune build -j 8 @install
if [ $QUICK = yes ]; then
  step ptests-rules dune exec -- frama-c-ptests plugins/eva/tests
  step eva-ptests-default dune build -j 8 @plugins/eva/tests/ptests_config
  step eva-native dune runtest -j 8 plugins/eva
else
  step ptests-rules make run-ptests
  step ptests-default dune build -j 8 @ptests_config
  step eva-ptests-all-configs dune build -j 8 @plugins/eva/tests/ptests
  step eva-native dune runtest -j 8 plugins/eva
  step kernel-native dune runtest -j 8 tests
  step headers make check-headers
  step lint-changed lint_changed
fi

exit $failed
