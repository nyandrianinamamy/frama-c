#!/usr/bin/env python3
# -*- coding: utf-8 -*-
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Receives a command line which crashes and removes as many command-line
# arguments as possible, while ensuring it still crashes.

import sys
import os
import subprocess

if len(sys.argv) < 2:
    print(
        f"usage: {sys.argv[0]} <test directory> <frama-c command line arguments (including files) causing a crash>"
    )
    print("alternative syntax (copied from frama-smith.py output):")
    print(
        "{sys.argv[0]} frama-c <test directory>/<source file> <frama-c command line options causing a crash>"
    )
    sys.exit(0)

# auxiliary function for iterating a list as a pair (cur, next);
# from SO: https://stackoverflow.com/questions/5434891
# This will likely be available in Python 3.10
import itertools


def pairwise(iterable):
    "s -> (s0,s1), (s1,s2), (s2, s3), ..."
    a, b = itertools.tee(iterable)
    next(b, None)
    return zip(a, b)


# we check if the first argument is the test directory (syntax 1)
# or 'frama-c' (syntax 2)
if sys.argv[1] == "frama-c":
    test_dir, test_file = sys.argv[2].rsplit("/", 1)
    if not os.path.exists(test_dir) or not os.path.isdir(test_dir):
        sys.exit(
            "error: first argument after 'frama-c' should point to a test directory: {test_dir}"
        )
    args = [test_file] + sys.argv[3:]
else:
    test_dir = sys.argv[1]
    if not os.path.exists(test_dir) or not os.path.isdir(test_dir):
        sys.exit("error: first argument should point to a test directory: {test_dir}")
    args = sys.argv[2:]


def check_cmdline_crashes(args):
    cmdline = ["frama-c"] + args
    try:
        proc = subprocess.run(cmdline, cwd=test_dir, timeout=30, capture_output=True)
        return proc.returncode == 4 or proc.returncode == 125, proc
    except subprocess.TimeoutExpired:
        sys.exit("TODO: timeout reached during execution")


# Returns 'true' if string s contains a comma that is between two quotes;
# used by normalize_commas.
def has_comma_between_quotes(s):
    try:
        i = s.index(",")
        return ('"' in s[: i - 1] and '"' in s[i + 1 :]) or (
            "'" in s[: i - 1] and "'" in s[i + 1 :]
        )
    except ValueError:
        return False


# Tries to split arguments of the form '-opt a1,a2,a3' into '-opt=a1 -opt=a2 -opt=a3'
# NOTE: this naively splits any arguments containing commas; if there are commas
#       inside quotes, thing will go BAD. So, we try to detect and avoid handling
#       cases where quotes could end up being split.
#       Also note that we MUST use the '-opt=arg' syntax instead of '-opt arg',
#       otherwise arguments starting with '-' will cause syntax errors
def normalize_commas(args):
    new_args = []
    skip_next = False
    for prev, cur in pairwise(args):
        if skip_next:
            skip_next = False
            continue
        if "," in cur and not has_comma_between_quotes(cur):
            # split arguments such as '-a=b,c' or '-a b,c'
            if "=" in cur:
                new_args.append(prev)
                # split arguments such as '-a=b,c' into '-a=b -a=c'
                cur_prefix, cur_rest = cur.split("=", 1)
                for opt in cur_rest.split(","):
                    new_args += [f"{cur_prefix}={opt}"]
            elif prev.startswith("-"):
                # do NOT append prev here! it will be duplicated otherwise
                # split arguments such as '-a b,c' into '-a=b -a=c'
                for opt in cur.split(","):
                    new_args += [f"{prev}={opt}"]
                skip_next = True
            else:
                # nothing to split, add prev and carry on
                new_args.append(prev)
                continue
            continue
        else:
            new_args.append(prev)
    if not skip_next:
        new_args.append(args[-1])
    return new_args


# Detects if an -eva-precision option has been given, and if so, replaces it
# with its elements
def normalize_eva_precision(args):
    pass  # TODO


# sanity check: initial run _must_ crash
crash, proc = check_cmdline_crashes(args)
if not crash:
    print(proc.stdout.decode("utf-8", errors="ignore"))
    print(
        f"error: supplied command line did not crash (expected return code 4, got {proc.returncode})!"
    )
    sys.exit(1)

args = normalize_commas(args)
# must try removing 1 and 2 consecutive arguments, to avoid issues with invalid command lines
progress = True
while progress:
    progress = False
    for i in range(len(args)):
        print(f"iterating... ({len(args)} options remaining)")
        new_args = args.copy()
        popped = new_args.pop(i)
        # print(f"trying '{popped}' ({len(new_args)} remaining)")
        crash, proc = check_cmdline_crashes(new_args)
        if not crash:
            # try removing successor
            if i < len(new_args):
                newer_args = new_args.copy()
                popped_succ = newer_args.pop(i)
                crash, proc = check_cmdline_crashes(newer_args)
                if crash:
                    # print(f"*** PROGRESS: removed unnecessary arguments: '{popped} {popped_succ}'")
                    progress = True
                    args = newer_args.copy()
                    break  # inner for
                else:
                    pass
                    # print(f"removed essential arguments ('{popped} {popped_succ}'), restoring")
            else:
                pass
                # print(f"removed essential argument '{popped}', restoring")
        else:
            # print(f"*** PROGRESS: removed unnecessary argument: '{popped}'")
            progress = True
            args = new_args.copy()
            break  # inner for

cmdline = [f'"{arg}"' for arg in args]
cmdline = "frama-c " + " ".join([f'"{arg}"' for arg in args])

# Now that ptests run tests inside the result directory, we need to add
# a 'cd' command to make the crash more easily reproducible
print(f"Minimized command line: (cd {test_dir} && {cmdline})")
