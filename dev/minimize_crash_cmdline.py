#!/usr/bin/env python3
#-*- coding: utf-8 -*-
##########################################################################
#                                                                        #
#  This file is part of Frama-C.                                         #
#                                                                        #
#  Copyright (C) 2007-2020                                               #
#    CEA (Commissariat à l'énergie atomique et aux énergies              #
#         alternatives)                                                  #
#                                                                        #
#  you can redistribute it and/or modify it under the terms of the GNU   #
#  Lesser General Public License as published by the Free Software       #
#  Foundation, version 2.1.                                              #
#                                                                        #
#  It is distributed in the hope that it will be useful,                 #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#  GNU Lesser General Public License for more details.                   #
#                                                                        #
#  See the GNU Lesser General Public License version 2.1                 #
#  for more details (enclosed in the file licenses/LGPLv2.1).            #
#                                                                        #
##########################################################################

# Receives a command line which crashes and removes as many command-line
# arguments as possible, while ensuring it still crashes.

import sys
import os
import subprocess
import random

MIN_PYTHON = (3, 5) # for subprocess.run
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

if len(sys.argv) < 2:
    print(f"usage: {sys.argv[0]} <frama-c command line causing a crash>")
    sys.exit(0)

# we assume the first argument is always the frama-c binary
framac = sys.argv[1]
args = sys.argv[2:]

def check_cmdline_crashes(framac, args):
    cmdline = [framac] + args
    #print(f"running: {' '.join(cmdline)}")
    proc = subprocess.run(cmdline, timeout=10, capture_output=True)
    #print(f"finished subprocess, returncode = {proc.returncode}")
    return proc.returncode == 4 or proc.returncode == 125, proc

# sanity check: initial run _must_ crash
crash, proc = check_cmdline_crashes(framac, args)
if not crash:
    print(proc.stdout.decode("utf-8", errors="ignore"))
    print(f"error: supplied command line did not crash (expected return code 4, got {proc.returncode})!")
    sys.exit(1)

# must try removing 1 and 2 consecutive arguments, to avoid issues with invalid command lines
progress = True
while progress:
    progress = False
    for i in range(len(args)):
        print(f"iterating... ({len(args)} options remaining)")
        new_args = args.copy()
        popped = new_args.pop(i)
        #print(f"trying '{popped}' ({len(new_args)} remaining)")
        crash, proc = check_cmdline_crashes(framac, new_args)
        if not crash:
            # try removing successor
            if i < len(new_args):
                newer_args = new_args.copy()
                popped_succ = newer_args.pop(i)
                crash, proc = check_cmdline_crashes(framac, newer_args)
                if crash:
                    #print(f"*** PROGRESS: removed unnecessary arguments: '{popped} {popped_succ}'")
                    progress = True
                    args = newer_args.copy()
                    break # inner for
                else:
                    pass
                    #print(f"removed essential arguments ('{popped} {popped_succ}'), restoring")
            else:
                pass
                #print(f"removed essential argument '{popped}', restoring")
        else:
            #print(f"*** PROGRESS: removed unnecessary argument: '{popped}'")
            progress = True
            args = new_args.copy()
            break # inner for

cmdline = [f'"{arg}"' for arg in args]
cmdline = framac + " " + " ".join([f'"{arg}"' for arg in args])
print(f"Minimized command line: {cmdline}")
