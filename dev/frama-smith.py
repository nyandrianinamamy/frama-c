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

# Mini-fuzzer for the Frama-C command line. Also works with ptests.

import asyncio
import glob
import json
import math
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MIN_PYTHON = (3, 6) # for glob(recursive) and automatic Path conversions
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

if len(sys.argv) >= 2 and sys.argv[1] == "--help":
    print("""
Frama-Smith: a mini-fuzzer for the Frama-C command-line

Usage: currently, almost all arguments are passed via environment variables.
       Arguments in the command line are passed as extra options
       to all generated command lines.

##### Important options

SOURCES_GLOB: a glob expression (may contain '*', '**', '[]', etc) matching
    all source files to be used as inputs for fuzzying.
    Note: curly braces ({}) are _not_ accepted.
    E.g. : SOURCES_GLOB="src/plugins/wp/tests/**/*.[ci]"
    Default: "tests/**/*.[ci]"

AUTOCOMPLETE_FILTER: filter given to option -autocomplete to determine which
    options will be used.
    E.g.: use AUTOCOMPLETE_FILTER="<shortname>" to only generate
    options for plugin <shortname>, or
    AUTOCOMPLETE_FILTER="@all,-<shortname>" to generate options for
    all plugins _except_ <shortname>.
    Default: @all

Also, take a look at the "mandatory_args" entry in the JSON template, for
options that will be always inserted in the command line. See option
TEMPLATES below for more details.

##### Secondary options

CPP_EXTRA_ARGS: preprocessing flags to be passed to option '-cpp-extra-args'.
    Default: "" (empty string)

N_TRIES: number of test runs.
    Default: 100

QUIET: set to 1 to avoid outputting messages in stdout.
    Messages are still logged to a temporary file.
    Default: 0 (off)

PTESTS_MODE: set to 1 to enable the 'ptests mode', which fuzzes using
    the existing test options (to ensure better coverage) and
    adds random options via -add-options and -add-options-pre.
    Note that this mode _always_ enables -autoload-plugins, otherwise
    many tests simply fail due to missing modules.
    Default: 0 (off)

TEMPLATES: the JSON file containing the templates for option generation,
    options to be excluded, etc.
    Default: <directory containing this script>/frama-smith-templates.json

TIMEOUT: timeout (in seconds) before terminating execution of a test.
    Note: timeout is currently buggy and does not work in all cases;
          some processes may keep executing longer than they should.
    Default: 10
""")
    sys.exit(0)

script_dir = Path(os.path.dirname(os.path.realpath(__file__)))

# Currently, all options are passed via environment variables
quiet = os.getenv("QUIET")
ptests_mode = bool(os.getenv("PTESTS_MODE"))
sources_glob = os.getenv("SOURCES_GLOB")
n_tries = int(os.getenv("N_TRIES", "100"))
autocomplete_filter = os.getenv("AUTOCOMPLETE_FILTER", "@all")
timeout = int(os.getenv("TIMEOUT", "10"))
templates_json = script_dir / "frama-smith-templates.json"
templates_json = Path(os.getenv("TEMPLATES", script_dir / "frama-smith-templates.json"))
cpp_extra_args = os.getenv("CPP_EXTRA_ARGS", "")

extra_args = " ".join(sys.argv[1:])

framac = "bin/frama-c"

with open(templates_json, encoding='utf-8') as template_file:
    json_obj = json.loads(template_file.read())
    options_to_ignore_wildcards = json_obj["options_to_ignore_wildcards"]
    options_to_ignore = json_obj["options_to_ignore"]
    templates = json_obj["templates"]
    mandatory_args = json_obj["mandatory_args"]

re_argtype = re.compile(' (-[^ ]+): ([^ ]+)( \((.*)\))?')
lines = subprocess.check_output([framac, f"-autocomplete={autocomplete_filter}"],
                                stderr=subprocess.STDOUT, encoding="UTF-8").splitlines()

substrings_to_ignore = []
prefixes_to_ignore = []
suffixes_to_ignore = []

for entry in options_to_ignore_wildcards:
    if entry[0] == '*' and entry[-1] == '*':
        # substring
        substrings_to_ignore.append(entry[1:-1])
    elif entry[0] == '*':
        # option suffix
        suffixes_to_ignore.append(entry[1:])
    elif entry[-1] == '*':
        # option prefix
        prefixes_to_ignore.append(entry[:-1])

#print(f"substrings_to_ignore: {substrings_to_ignore}")
#print(f"prefixes_to_ignore: {prefixes_to_ignore}")
#print(f"suffixes_to_ignore: {suffixes_to_ignore}")

# generates a random integer between a and b, biased towards a
def random_biased_towards_lower(a, b):
    dist = b - a
    if dist > 1000:
        # generate a number VERY biased towards a
        if random.random() <= 0.97:
            return a + math.trunc(random.random() * 10)
        else:
            return a + math.trunc(random.random() * (b - a))
    else:
        # generate a number slightly biased towards a
        return a + math.trunc(random.random() * (b - a)) >> random.randint(0, math.trunc(math.log(b - a,2)))

def option_to_ignore(opt):
    if opt in options_to_ignore:
        return True
    for pre in prefixes_to_ignore:
        if opt.startswith(pre):
            return True
    for suf in suffixes_to_ignore:
        if opt.endswith(suf):
            return True
    for f in substrings_to_ignore:
        if f in opt:
            return True
    return False

not_yet_implemented = ["function", "functions", "variable"]

must_exist_dir = "/tmp/frama-smith-dir1-always-exists"
must_exist_input_file = must_exist_dir + "/garbage-in"

subtypes = {}
subtypes["directory"] = [must_exist_dir, "/tmp/frama-smith-dir2-may-exist"]
subtypes["output_file"] = [must_exist_dir + "/out1", must_exist_dir + "/out2", "/tmp/frama-smith-dir2-may-exist/out3"]
subtypes["input_file"] = [must_exist_input_file, must_exist_dir + "/non-existing-file", "/tmp/non-existing-dir/non-existing-file"]

if not (os.path.exists(must_exist_dir)):
    os.mkdir(must_exist_dir)

with open(must_exist_input_file, 'w') as out_file:
    out_file.write("[{(\n")

all_options = {}
n_opts = 0
missing_templates = 0
for line in lines:
    m = re_argtype.search(line)
    if m:
        n_opts += 1
        option = m.group(1)
        if option_to_ignore(option):
            # ignore option
            continue
        if option in templates:
            # some templates are 'dual': made of a list of keys and a list of values
            if "keys" in templates[option]:
                all_options[option] = "template_dual"
            elif templates[option] in not_yet_implemented:
                # not yet implemented; ignore
                continue
            else:
                #print(f"option {option} has a template: {templates[option]}")
                all_options[option] = "template"
        else:
            # no template : a bool, an integer range, a list of strings,
            # a subtype, or something needing a template
            option_type = m.group(2)
            if option_type == "bool":
                all_options[option] = ""
            elif option_type == "int":
                irange = m.group(4)
                if irange:
                    [imin, imax] = irange.split(", ")
                    all_options[option] = {"range":[imin, imax]}
                else:
                    print(f"missing template for option: {option} (int)")
                    missing_templates += 1
            elif option_type == "string":
                values = m.group(4)
                if values:
                    values_list = values.split(", ")
                    # remove key 'help' if present, since it leads to early termination
                    if "help" in values_list:
                        values_list.remove("help")
                    all_options[option] = {"values":values_list}
                else:
                    print(f"missing template for option: {option} (string)")
                    missing_templates += 1
            elif option_type == "directory":
                all_options[option] = {"values":subtypes["directory"]}
            elif option_type == "input_file":
                all_options[option] = {"values":subtypes["input_file"]}
            elif option_type == "output_file":
                all_options[option] = {"values":subtypes["output_file"]}
            else:
                sys.exit(f"invalid option_type: {option_type}")

if missing_templates > 0:
    sys.exit(f"{missing_templates} missing template(s) found, quitting")

if sources_glob == "":
    sys.exit(f"error: no sources (use environment variable SOURCES_GLOB or sources_glob entry in {templates_json})")
sources = glob.glob(sources_glob)
if sources == []:
    sys.exit(f"error: no files matching sources_glob: {sources_glob}")

### END OF COMMAND-LINE CHECKS; EXECUTION WILL TAKE PLACE

print(f"Autocomplete filter: '{autocomplete_filter}'. Fuzzing {len(all_options)}/{n_opts} Frama-C command-line options.")

def generate_random_args(min_args, max_args):
    n_args = random.randint(min_args, max_args)
    chosen_opts = random.sample(all_options.keys(), n_args)
    args = ""
    #print(f"chosen_opts = {chosen_opts}")
    for opt in chosen_opts:
        entry = all_options[opt]
        #print(f"opt = {opt}, all_options[opt] = '{all_options[opt]}', type(entry) = {type(entry)}")
        if entry == "":
            #print(f"OPTION {opt}: no argument");
            args += f" {opt}"
        elif type(entry) is dict:
            # range
            if "range" in entry:
                rmin = int(entry["range"][0])
                rmax = int(entry["range"][1])
                rand = random_biased_towards_lower(rmin, rmax)
                args += f" {opt} {rand}"
            elif "values" in entry:
                args += f" {opt} {random.choice(entry['values'])}"
            else:
                sys.exit(f"error: unknown entry for option '{opt}': '{entry}'")
                #print(f"OPTION {opt}: TEMPLATE! choices: {templates[opt]}");
        elif entry == "template":
            #print(f"OPTION {opt}: TEMPLATE! choices: {templates[opt]}");
            template = templates[opt]
            if "range" in template:
                rmin = int(template["range"][0])
                rmax = int(template["range"][1])
                rand = random_biased_towards_lower(rmin, rmax)
                args += f" {opt} {rand}"
            else:
                args += f" {opt} {random.choice(template)}"
        elif entry == "template_dual":
            #print(f"OPTION {opt}: DUAL TEMPLATE!");
            key = random.choice(templates[opt]["keys"])
            value = random.choice(templates[opt]["values"])
            args += f" {opt}={key}:{value}"
        elif entry == "string" or entry == "int":
            sys.exit(f"error: option '{opt}' of type '{entry}' is unbounded and has no template")
        else:
            sys.exit(f"error: invalid argument? {opt} has type {entry}")
    #print(f"final command line ({n_args} arguments):")
    #print(f"{args}")
    return args

re_possible_values = re.compile("Possible values are: (.*)")
re_invalid_input = re.compile("invalid input .* for option (-.*)\.")

ok_tries = 0

# Timer for test execution timeout
class Timer:
    def __init__(self, timeout, callback, process):
        self._timeout = timeout
        self._callback = callback
        self._task = asyncio.ensure_future(self._job())
        self._process = process

    async def _job(self):
        await asyncio.sleep(self._timeout)
        await self._callback(self._process)

    def cancel(self):
        self._task.cancel()

async def timeout_callback(process):
    print(f"### TIMEOUT ({self._timeout} seconds) running process, ignoring...")
    process.kill() # timeout

async def run_and_log_command(args, timeout):
    process = await asyncio.create_subprocess_shell(args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    # read line asynchronously
    _logfd, logname = tempfile.mkstemp(prefix="frama_smith_")
    with open (logname, "bw") as logfile:
        try:
            if quiet:
                print(f"*** logging output to: {logname}")
            timer = Timer(timeout, timeout_callback, process)
            while True:
                try:
                    line = await asyncio.wait_for(process.stdout.readline(), timeout)
                except (asyncio.TimeoutError, asyncio.exceptions.TimeoutError) as e:
                    print(f"### TIMEOUT ({timeout} seconds) reading process, ignoring...")
                    process.kill() # timeout
                    retcode = 124
                    return (retcode, "")
                else:
                    if not line: # EOF
                        break
                    else:
                        logfile.write(line)
                        if not quiet:
                            sys.stdout.buffer.write(line)
                            sys.stdout.flush()
                        continue
                    process.kill() # timeout
                    break
            retcode = await process.wait() # wait for the child process to exit
            timer.cancel()
        except Exception as e:
            print("killing subprocess before re-raising exception...")
            process.kill()
            raise e
    with open(logname, "r") as logfile:
        output = logfile.read()
    os.remove(logname)
    return (retcode, output)

loop = asyncio.get_event_loop()

for i in range(1, n_tries+1):
    print(f"*** Generating command {i}/{n_tries}...")
    if ptests_mode:
        pre_options = generate_random_args(0, 10)
        post_options = generate_random_args(0, 10)
        cmdline = f"bin/ptests.opt -j 12 {random.choice(sources)} -add-options-pre='{pre_options}' -add-options-post='{post_options} -autoload-plugins' {extra_args}"
    else:
        cmdline = f"{framac} {mandatory_args} {random.choice(sources)} -cpp-extra-args=\"{cpp_extra_args}\" {extra_args}"
        cmdline += generate_random_args(2, 15)
    print(f"running: {cmdline}")
    (retcode, res_stdout) = loop.run_until_complete(run_and_log_command(cmdline, timeout))
    if retcode == 4:
        sys.exit(f"Crash detected in Frama-C, stopping analysis")
    else:
        if retcode == 0:
            ok_tries += 1
        if res_stdout.find("Please report") != -1:
            sys.exit("Detected fatal crash, interrupting execution.")
            if quiet:
                print("### Output from fatal crash:")
                print(res_stdout)

loop.close()

print(f"*** Executions ended without error: {ok_tries}/{n_tries}")
