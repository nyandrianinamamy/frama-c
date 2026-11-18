#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Rejects cram commands that pipe the output of frama-c into another command:
# the test then records the exit status of the last command only. Redirect the
# output to a file and inspect the file in the next command.
#
# Usage: check-cram-pipes.sh [git diff arguments]   (default: --cached)
# Only lines added by the diff are checked.

set -u

if [ $# -eq 0 ]; then set -- --cached; fi

found=$(git diff -U0 "$@" -- '*.t' \
  | awk '/^\+\+\+ /{file=substr($2,3)} /^\+  \$ .*frama-c[^|]*\|/{print file": "substr($0,2)}')

if [ -n "$found" ]; then
  echo "check-cram-pipes: frama-c piped into another command:" >&2
  echo "$found" >&2
  echo "Redirect its output to a file, then inspect the file." >&2
  exit 1
fi
exit 0
