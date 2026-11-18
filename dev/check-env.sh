#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Checks that the active OCaml and Dune are the versions this checkout is
# tested with. See docs/agents/setup.md to create or repair the switch.

set -u

EXPECTED_OCAML=5.2.1
EXPECTED_DUNE=3.21.1

status=0

check () {
  local name=$1 expected=$2 actual=$3
  if [ "$actual" != "$expected" ]; then
    echo "check-env: $name is '${actual:-not found}', expected $expected" >&2
    status=1
  fi
}

check OCaml "$EXPECTED_OCAML" "$(ocamlc -version 2>/dev/null)"
check Dune "$EXPECTED_DUNE" "$(dune --version 2>/dev/null)"

if [ $status -ne 0 ]; then
  echo "check-env: activate the local switch, or see docs/agents/setup.md" >&2
fi
exit $status
