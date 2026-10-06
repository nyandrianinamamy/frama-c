#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Script intended to be used by dev/build-bundle.sh
# Install Frama-C's dependencies in current opam switch, located at
# $OPAM

set -euo pipefail

# Path to the current script directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z ${OPAM+x} ]; then
    echo "Variable OPAM should be provided"
    exit 1
fi

# Install Frama-C dependencies except Why3
opam install -y --confirm-level=unsafe-yes \
  dune \
  dune-configurator \
  dune-site \
  camlzip \
  menhir \
  ocaml \
  ocamlgraph \
  unionFind \
  yaml \
  yojson \
  zarith \
  ppx_deriving \
  ppx_deriving_yojson \
  ppx_deriving_yaml \
  ppx_inline_test

# Manually build relocatable why3
WHY3_VERSION="$(jq --raw-output '.why3.version' "$SCRIPT_DIR/../nix/sources.json")"
WHY3="why3-$WHY3_VERSION"
echo "### Found Why3 version '$WHY3_VERSION'"

rm -rf "$WHY3*"
WHY3_URL="https://why3.gitlabpages.inria.fr/releases/$WHY3.tar.gz"
echo "### Downloading '$WHY3_URL'"
curl "$WHY3_URL" -o "$WHY3.tar.gz"
tar xzf "$WHY3.tar.gz"

cd "$WHY3" || exit 1 ;

echo "### Compiling Why3"
./configure \
  --enable-relocation \
  --disable-frama-c \
  --disable-coq-libs \
  --disable-js-of-ocaml \
  --disable-re \
  --enable-ocamlfind \
  --disable-mpfr \
  --disable-zip \
  --disable-hypothesis-selection \
  --disable-stackify \
  --disable-ide \
  --prefix="$OPAM"
make -j
make install install-lib

