#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Example of installation of this pre-commit hook (client side):
# - (cd .git/hooks/ && ln -s ../../dev/git-hooks/pre-commit.sh pre-commit)

ROOT=$(git rev-parse --show-toplevel)

echo "Pre-commit Hook..."

# The lint tools come from the local switch: without it the checks fail on a
# missing library.
bash "$ROOT/dev/check-env.sh" || exit 1

STAGED=$(git diff --diff-filter ACMR --name-only --cached | sort)

if [ "$STAGED" = "" ];
then
  echo "Empty commit, nothing to do"
  exit 0
fi

"$ROOT/dev/check-cram-pipes.sh" --cached || exit 1
"$ROOT/dev/check-files.sh" -c || exit 1
