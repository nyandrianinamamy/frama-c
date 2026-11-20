##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Sourced by the prototype runners from the repository root. Activates the
# main checkout's switch, checks the environment and builds @install.

main_checkout=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
eval "$(opam env --switch="$main_checkout" --set-switch)"
export PATH="$main_checkout/_opam/setup-venv/bin:$PATH"

bash dev/check-env.sh
dune build -j 8 @install
