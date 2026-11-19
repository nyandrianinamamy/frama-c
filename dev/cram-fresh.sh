#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Runs cram tests from scratch: builds the installed artifacts, which the
# test modules load, removes the generated directory of each test, and runs
# them with the Dune cache disabled. Dune can otherwise answer from an
# earlier run, also with --force.
#
# usage: dev/cram-fresh.sh DIR.t...
#   DIR.t: a cram test directory, relative to the root of the checkout
#
# Prints the number of generated directories recreated; a test that did not
# run leaves none. The exit status is that of the tests.

set -u

if [ $# -eq 0 ]; then
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '9,18p'
  exit 2
fi

generated=()
for t in "$@"; do
  t=${t%/}
  if [ ! -d "$t" ]; then
    echo "cram-fresh: no such test directory: $t" >&2
    exit 2
  fi
  generated+=("_build/default/$(dirname "$t")/.cram.$(basename "$t")")
done

dune build -j 8 @install || exit 1
rm -rf "${generated[@]}"
TERM=xterm dune runtest -j 8 --cache=disabled "$@"
status=$?

recreated=0
for g in "${generated[@]}"; do
  [ -d "$g" ] && recreated=$((recreated + 1))
done
echo "cram-fresh: $recreated of ${#generated[@]} tests ran, exit $status"
[ "$recreated" -eq "${#generated[@]}" ] || exit 1
exit $status
