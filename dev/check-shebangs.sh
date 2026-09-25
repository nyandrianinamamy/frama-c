#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Find all bash files with either /usr/bin/bash or /bin/bash shebangs
wrong_shebangs=$(\
  git grep --files-with-matches \
    -e '#!\s*/usr/bin/bash' \
    -e '#!\s*/bin/bash' \
    -- '*.sh')

if [ -n "$wrong_shebangs" ]; then
  echo "Found the following files with limited portability shebangs:"
  echo "$wrong_shebangs"
  echo ""
  echo "Please use '#!/usr/bin/env bash' instead for better portability"
  exit 1
fi

