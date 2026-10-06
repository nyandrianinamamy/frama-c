##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Recursively meld a and b, concatenating arrays and merging objects,
# favoring b when there is a conflict
# From <https://stackoverflow.com/a/53666584>
def meld(a; b):
  a as $a | b as $b
  | if ($a|type) == "object" and ($b|type) == "object"
    then reduce ([$a,$b]|add|keys_unsorted[]) as $k ({};
      .[$k] = meld($a[$k]; $b[$k]) )
    elif ($a|type) == "array" and ($b|type) == "array"
    then $a+$b
    elif $b == null then $a
    else $b
    end;

# Remove the `__comment` key from the object a if it exists
def remove_comment(a):
  a | if has("__comment") then del(.__comment) else . end;

# Meld all input files together. The first file is the original Oui
# file, the other input files are the patches. Remove the `__comment`
# key from the patches.
reduce inputs as $i (.; meld(. ; remove_comment($i)))
