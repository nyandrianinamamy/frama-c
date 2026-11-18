#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Checks the revisions cited by the correspondence record,
# docs/eva/reuse-correspondence/. Each 40-digit identifier must be either a
# commit in the history of HEAD, or the tree of lean/ at a commit of that
# history. A rebase changes the commits and keeps the trees: this finds the
# citations it left behind. Lines saying that a CI run is pending are listed
# as a reminder and do not fail the check.
#
# Usage: check-record.sh

set -u

cd "$(git rev-parse --show-toplevel)" || exit 2
RECORD=docs/eva/reuse-correspondence

trees=$(git log --format=%H -- lean | while read -r c; do
          git rev-parse --quiet --verify "$c:lean"
        done | sort -u)

failed=0
while IFS=: read -r file line id; do
  if git merge-base --is-ancestor "$id" HEAD 2>/dev/null; then
    continue
  fi
  if printf '%s\n' "$trees" | grep -qx "$id"; then
    continue
  fi
  echo "$file:$line: $id is neither a commit of this history nor a tree of lean/ in it"
  failed=1
done < <(grep -noE '\b[0-9a-f]{40}\b' "$RECORD"/*.md)

grep -nE 'CI[^.]*pending' "$RECORD"/*.md | sed 's/^/pending: /'

exit $failed
