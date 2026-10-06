#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Script intended to be used by dev/build-bundle.sh
# Copy Frama-C's runtime dependencies from opam switch located at $OPAM
# to the bundle directory located at $BUNDLE

set -euo pipefail

# Path to the current script directory (uncomment if necessary)
#SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z ${OPAM+x} ]; then
    echo "Variable OPAM should be provided"
    exit 1
fi

if [ -z ${BUNDLE+x} ]; then
    echo "Variable BUNDLE should be provided"
    exit 1
fi

cp -r "$OPAM/lib/unionFind" "$BUNDLE/lib"
cp -r "$OPAM/lib/store" "$BUNDLE/lib"
cp -r "$OPAM/lib/ppx_deriving_yojson" "$BUNDLE/lib"
cp -r "$OPAM/lib/ocamlgraph" "$BUNDLE/lib"
cp -r "$OPAM/lib/why3" "$BUNDLE/lib"
cp -r "$OPAM/share/why3" "$BUNDLE/share"

