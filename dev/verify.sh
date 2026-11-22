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
#
# It stops before the first step when the checkout or TMPDIR has less than
# FC_MIN_FREE_GB GiB free (default 5).

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

# A full disk makes builds and tests fail in ways that read as regressions:
# stop at once when the checkout or the logs have less than FC_MIN_FREE_GB
# (default 5) GiB free.
MIN_FREE=${FC_MIN_FREE_GB:-5}
for dir in . "${TMPDIR:-/tmp}"; do
  free=$(df -Pk "$dir" | awk 'NR == 2 { print int($4 / 1048576) }')
  if [ "$free" -lt "$MIN_FREE" ]; then
    echo "only $free GiB free on the volume of $dir (FC_MIN_FREE_GB=$MIN_FREE)" >&2
    exit 2
  fi
done

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
  git diff --name-only --diff-filter=d -z "$BASE" HEAD | git check-attr --stdin -z -a \
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
