#!/usr/bin/env python3
# -*- coding: utf-8 -*-
##########################################################################
#                                                                        #
#  This file is part of Frama-C.                                         #
#                                                                        #
#  Copyright (C) 2007-2023                                               #
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

# Usage examples:
#
########## 'NORMAL' MODE #######
# Opens one of the files in SOURCES_GLOB and adds a number of random
# options:
#
# SOURCES_GLOB="tests/**/*.[ci]" devel_tools/frama-smith.py
#
# Works better with stand-alone programs; when using Frama-C
# non-regression test suites, due to lack of the specific flags used in
# many tests (e.g. -cpp-extra-args), many tests fail early. Prefer
# PTESTS_MODE in this case.
#
########## PTESTS_MODE #######
# Uses existing tests and existing options, and fuzzes by adding other
# options:
#
# PTESTS_MODE=1 SOURCES_GLOB="tests/**/*.[ci]" SOURCES_EXCLUDE="tests/syntax/asm_with_contracts.i,tests/slicing/*" N_TRIES=10000 devel_tools/frama-smith.py
#
# SOURCES_GLOB: typically use "tests/**/*.[ci]" for the "main" Frama-C tests,
# "src/plugins/*/tests/**/*.[ci]" for plugin-specific tests, or both, separated
# by a comma.
#
# SOURCES_EXCLUDE: to temporarily exclude problematic tests (e.g. those which
# tend to crash too often for uninteresting reasons).
#
# You can also add ptests options, such as `-add-options="-bla"` to force
# their inclusion. Note that, if your option requires a plugin to be loaded,
# you will often need `-add-options=-autoload-plugins` at the end.


import asyncio
import glob
import json
import logging
import math
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path
import psutil

MIN_PYTHON = (3, 6)  # for glob(recursive) and automatic Path conversions
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

if len(sys.argv) >= 2 and sys.argv[1] == "--help":
    print(
        """
Frama-Smith: a mini-fuzzer for the Frama-C command-line

Usage: currently, almost all arguments are passed via environment variables.
       Arguments in the command line are passed as extra options
       to all generated command lines.

##### Important options

SOURCES_GLOB: a glob expression (may contain '*', '**', '[]', etc) matching
    all source files to be used as inputs for fuzzying.
    In this mode, a _single_ file among the globbed ones is used for each test.
    Note: curly braces ({}) are _not_ accepted.
    Incompatible with MULTI_SOURCES_GLOB and LOAD_SAVE.
    E.g. : SOURCES_GLOB="src/plugins/wp/tests/**/*.[ci]"
    Default: "tests/**/*.[ci]", unless MULTI_SOURCES_GLOB is set.

MULTI_SOURCES_GLOB: a glob expression (may contain '*', '**', '[]', etc)
    matching all source files to be used as inputs for fuzzying.
    In this mode, _all_ globbed files are used at each test.
    Note: curly braces ({}) are _not_ accepted.
    Incompatible with SOURCES_GLOB and LOAD_SAVE.
    E.g. : MULTI_SOURCES_GLOB="tests/idct/*.c"
    Default: "" (off)

LOAD_SAVE: a glob expression (may contain '*', '**', '[]', etc) matching
    Frama-C save files (.sav) to be used as inputs for fuzzying (via -load).
    Replaces (and is incompatible with) SOURCES_GLOB and MULTI_SOURCES_GLOB.
    Default: "" (off)

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

LIST_OPTIONS: do not run; list all options that could be generated, then quit.
    Default: 0 (off)

LOG_AND_KEEP: for every crash, append the faulty command line to a file,
    and keep generating commands. Otherwise, stop at first generated crash.
    Default: "" (empty string; off)

MUST_SUCCEED: stops whenever a Frama-C run gives _any_ errors
    (return code != 0). Disables some fuzzying to avoid too many
    false positives.

N_TRIES: number of test runs.
    Default: 100

PTESTS_MODE: set to 1 to enable the 'ptests mode', which fuzzes using
    the existing test options (to ensure better coverage) and
    adds random options via -add-options and -add-options-pre.
    Note that this mode _always_ enables -autoload-plugins, otherwise
    many tests simply fail due to missing modules.
    Default: 0 (off)

QUIET: set to 1 to avoid outputting messages in stdout.
    Messages are still logged to a temporary file.
    Default: 0 (off)

SOURCES_EXCLUDE: a comma-separated list of glob expressions (may contain
    '*', '**', '[]', etc) matching all source files to be _excluded_ from
    being fuzzying inputs.
    Default: "" (empty string; off).

TEMPLATES: the JSON file containing the templates for option generation,
    options to be excluded, etc.
    Default: <directory containing this script>/frama-smith-templates.json

TIMEOUT: timeout (in seconds) before terminating execution of a test.
    Note: timeout is currently buggy and does not work in all cases;
          some processes may keep executing longer than they should.
    Default: 10
"""
    )
    sys.exit(0)

script_dir = Path(os.path.dirname(os.path.realpath(__file__)))

# Currently, all options are passed via environment variables
sources_glob = os.getenv("SOURCES_GLOB", "")
multi_sources_glob = os.getenv("MULTI_SOURCES_GLOB", "")
load_save = os.getenv("LOAD_SAVE", "")
autocomplete_filter = os.getenv("AUTOCOMPLETE_FILTER", "@all")
cpp_extra_args = os.getenv("CPP_EXTRA_ARGS", "")
list_options = bool(os.getenv("LIST_OPTIONS"))
log_and_keep_value = os.getenv("LOG_AND_KEEP", "")
log_and_keep = Path(log_and_keep_value) if log_and_keep_value else None
must_succeed = bool(os.getenv("MUST_SUCCEED"))
n_tries = int(os.getenv("N_TRIES", "100"))
ptests_mode = bool(os.getenv("PTESTS_MODE"))
quiet = os.getenv("QUIET")
sources_exclude = os.getenv("SOURCES_EXCLUDE", "")
timeout = int(os.getenv("TIMEOUT", "10"))
templates_json = Path(os.getenv("TEMPLATES", script_dir / "frama-smith-templates.json"))

# add double quotes around extra arguments to be forwarded to the
# 'new' command line; this compensates their 'loss' by the shell when passed
# to this Python process.
extra_args = " ".join('"%s"' % arg for arg in sys.argv[1:])

framac = "frama-c"
fc_script = f"{framac}-script"

if log_and_keep:
    print(f"Logging commands causing crashes to: '{log_and_keep}'")
    logging.basicConfig(
        format="[%(asctime)s] %(message)s",
        filename=log_and_keep,
        # (for Python 3.9) encoding='utf-8',
        level=logging.INFO,
        datefmt="%Y-%m-%d %H:%M:%S",
    )

with open(templates_json, encoding="utf-8") as template_file:
    json_obj = json.loads(template_file.read())
    options_to_ignore_wildcards = json_obj["options_to_ignore_wildcards"]
    options_to_ignore = list(json_obj["options_to_ignore"].keys())
    templates = json_obj["templates"]
    mandatory_args = json_obj["mandatory_args"]
    sources_blacklist = json_obj["sources_blacklist"]
    del sources_blacklist["<LIST_TERMINATOR>"]

re_argtype = re.compile(" (-[^ ]+): ([^ ]+)( \((.*)\))?")
lines = subprocess.check_output(
    [framac, f"-autocomplete={autocomplete_filter}"], stderr=subprocess.STDOUT, encoding="UTF-8"
).splitlines()

substrings_to_ignore = []
prefixes_to_ignore = []
suffixes_to_ignore = []

for entry in options_to_ignore_wildcards:
    if entry[0] == "*" and entry[-1] == "*":
        # substring
        substrings_to_ignore.append(entry[1:-1])
    elif entry[0] == "*":
        # option suffix
        suffixes_to_ignore.append(entry[1:])
    elif entry[-1] == "*":
        # option prefix
        prefixes_to_ignore.append(entry[:-1])

# print(f"substrings_to_ignore: {substrings_to_ignore}")
# print(f"prefixes_to_ignore: {prefixes_to_ignore}")
# print(f"suffixes_to_ignore: {suffixes_to_ignore}")


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
        return a + math.trunc(random.random() * (b - a)) >> random.randint(
            0, math.trunc(math.log(b - a, 2))
        )


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


not_yet_implemented = ["variable"]

must_exist_dir = "/tmp/frama-smith-dir1-always-exists"
must_exist_input_file = must_exist_dir + "/garbage-in"

subtypes = {}
subtypes["directory"] = [must_exist_dir]
subtypes["output_file"] = [must_exist_dir + "/out1", must_exist_dir + "/out2"]
subtypes["input_file"] = [must_exist_input_file]
if not must_succeed:
    subtypes["directory"] += [must_exist_dir, "/tmp/frama-smith-dir2-may-exist"]
    subtypes["output_file"] += ["/tmp/frama-smith-dir2-may-exist/out3"]
    subtypes["input_file"] += [
        must_exist_dir + "/non-existing-file",
        "/tmp/non-existing-dir/non-existing-file",
    ]

if not (os.path.exists(must_exist_dir)):
    os.mkdir(must_exist_dir)

with open(must_exist_input_file, "w") as out_file:
    if must_succeed:
        out_file.write("[]\n")
    else:
        out_file.write("[{(\n")

all_options = {}
n_opts = 0
unsupported_n_opts = 0
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
            # some template kinds are unsupported in a few modes
            if ptests_mode and templates[option] == "functions":
                unsupported_n_opts += 1
                continue
            # some templates are 'dual': made of a list of keys and a list of values
            if "keys" in templates[option]:
                all_options[option] = "template_dual"
            elif templates[option] in not_yet_implemented:
                # not yet implemented; ignore
                continue
            else:
                # print(f"option {option} has a template: {templates[option]}")
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
                    all_options[option] = {"range": [imin, imax]}
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
                    all_options[option] = {"values": values_list}
                else:
                    print(f"missing template for option: {option} (string)")
                    missing_templates += 1
            elif option_type == "directory":
                all_options[option] = {"values": subtypes["directory"]}
            elif option_type == "input_file":
                all_options[option] = {"values": subtypes["input_file"]}
            elif option_type == "output_file":
                all_options[option] = {"values": subtypes["output_file"]}
            else:
                sys.exit(f"invalid option_type: {option_type}")

if missing_templates > 0:
    sys.exit(f"{missing_templates} missing template(s) found, quitting")

# A few command-line options are special and do not appear in autocomplete;
# we explicitly add them here
all_options["-then"] = ""

nb_source_opts = 0
if sources_glob != "":
    nb_source_opts += 1
    glob_expression = sources_glob
    source_mode = "single"
if multi_sources_glob != "":
    nb_source_opts += 1
    glob_expression = multi_sources_glob
    source_mode = "multi"
if load_save != "":
    nb_source_opts += 1
    glob_expression = load_save
    source_mode = "load"

if nb_source_opts == 0:
    sys.exit("error: no sources (use SOURCES_GLOB, MULTI_SOURCES_GLOB or LOAD_SAVE)")
elif nb_source_opts > 1:
    sys.exit("error: only one of SOURCES_GLOB, MULTI_SOURCES_GLOB and LOAD_SAVE must be set")

sources_set = set(glob.glob(glob_expression))
if not sources_set:
    sys.exit(f"error: no files matching expression: {glob_expression}")

for exc in sources_blacklist.keys():
    sources_set -= set(glob.glob(exc))

if not sources_set:
    sys.exit(
        f"error: no remaining files after applying sources blacklist: {list(sources_blacklist.keys())}"
    )

for exc in sources_exclude.split(","):
    sources_set -= set(glob.glob(exc))

if not sources_set:
    sys.exit(f"error: no remaining files after applying source exclusions: {sources_exclude}")

sources = sorted(sources_set)

if list_options:
    print("Listing all options that could be generated:")
    print("\n".join(sorted(all_options)))
    sys.exit(0)

### END OF COMMAND-LINE CHECKS; EXECUTION WILL TAKE PLACE

all_options_keys_list = list(all_options.keys())

print(
    f"Autocomplete filter: '{autocomplete_filter}'. Fuzzing {len(all_options_keys_list)}/{n_opts} Frama-C command-line options ({unsupported_n_opts} option(s) not supported in current mode)."
)

re_list_functions = re.compile("^([A-Za-z0-9_]+): (defined|declared) at.*")


def list_functions(chosen_sources, cpp_extra, add_load):
    # Note: frama-c-script loads no modules, so we do not include most options.
    # We must keep however those related to preprocessing, such as
    # '-cpp-extra-args', to ensure parsing succeeds and we get the list of
    # functions.
    fc_script_cmdline = f"{fc_script} list-functions {add_load}{chosen_sources} {cpp_extra}"
    try:
        fc_script_proc = subprocess.run(
            fc_script_cmdline,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            shell=True,
            timeout=5,
            check=False,
        )
        if fc_script_proc.returncode != 0:
            # could not get functions, return empty list
            return []
        functions = []
        for line in fc_script_proc.stdout.splitlines():
            m = re_list_functions.match(line)
            if m:
                functions.append(m.group(1))
        return functions
    except subprocess.TimeoutExpired:
        # timeout getting functions
        return []


def generate_random_args(min_args, max_args, functions=[]):
    n_args = random.randint(min_args, max_args)
    chosen_opts = random.sample(all_options_keys_list, n_args)
    args = ""
    # print(f"chosen_opts = {chosen_opts}")
    for opt in chosen_opts:
        entry = all_options[opt]
        # print(f"opt = {opt}, all_options[opt] = '{all_options[opt]}', type(entry) = {type(entry)}")
        if entry == "":
            # print(f"OPTION {opt}: no argument");
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
                # print(f"OPTION {opt}: TEMPLATE! choices: {templates[opt]}");
        elif entry == "template":
            # print(f"OPTION {opt}: TEMPLATE! choices: {templates[opt]}");
            template = templates[opt]
            if isinstance(template, list):
                args += f" {opt} {random.choice(template)}"
            else:
                # check for special template types
                if "range" in template:
                    rmin = int(template["range"][0])
                    rmax = int(template["range"][1])
                    rand = random_biased_towards_lower(rmin, rmax)
                    args += f" {opt} {rand}"
                elif template == "functions":
                    if functions != []:
                        function_subset = ",".join(
                            random.sample(functions, random.randint(1, len(functions)))
                        )
                        args += f" {opt} {function_subset}"
                    else:
                        # did not get a list of functions; ignore option
                        pass
                elif template == "function":
                    if functions != []:
                        args += f" {opt} {random.choice(functions)}"
                    else:
                        # did not get a list of functions; ignore option
                        pass
                else:
                    sys.exit(f"error: unknown special template '{template}' for option '{opt}'")
        elif entry == "template_dual":
            # print(f"OPTION {opt}: DUAL TEMPLATE!");
            key = random.choice(templates[opt]["keys"])
            value = random.choice(templates[opt]["values"])
            args += f" {opt}={key}:{value}"
        elif entry == "string" or entry == "int":
            sys.exit(f"error: option '{opt}' of type '{entry}' is unbounded and has no template")
        else:
            sys.exit(f"error: invalid argument? {opt} has type {entry}")
    # print(f"final command line ({n_args} arguments):")
    # print(f"{args}")
    return args


re_possible_values = re.compile("Possible values are: (.*)")
re_invalid_input = re.compile("invalid input .* for option (-.*)\.")

ok_tries = 0
timeouts = 0


# Timer for test execution timeout
class Timer:
    def __init__(self, timeout, callback, process):
        self._timeout = timeout
        self._callback = callback
        self._task = asyncio.ensure_future(self._job())
        self._process = process

    async def _job(self):
        await asyncio.sleep(self._timeout)
        await self._callback(self._timeout, self._process)

    def cancel(self):
        self._task.cancel()


# This function ensures that, especially in the case of timeouts, the children
# processes of the shell running Frama-C (or ptests) will also be terminated.
# If we use a simple 'process.kill()' applied to the created subprocess, this
# will not be enough, and the child process will keep running.
def kill_shell_and_children(pid):
    try:
        process = psutil.Process(pid)
        for child in process.children(recursive=True):
            try:
                print(f"killing child: {child.pid}")
                child.kill()
            except psutil.NoSuchProcess:
                print(f"process {child.pid} already killed, ignoring")
        print(f"killing process: {pid}")
        process.kill()
    except psutil.NoSuchProcess:
        print(f"process {pid} already killed, ignoring")


async def timeout_callback(timeout, process):
    print(f"### TIMEOUT ({timeout} seconds) running process {process.pid}, ignoring...")
    kill_shell_and_children(process.pid)
    global timeouts
    timeouts += 1


async def run_and_log_command(args, timeout):
    process = await asyncio.create_subprocess_shell(
        args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, limit=1024 * 256
    )
    # read line asynchronously
    logfd, logname = tempfile.mkstemp(prefix="frama_smith_")
    with open(logname, "bw") as logfile:
        try:
            if quiet:
                print(f"*** logging output to: {logname}")
            timer = Timer(timeout, timeout_callback, process)
            while True:
                try:
                    line = await asyncio.wait_for(process.stdout.readline(), timeout)
                except (asyncio.TimeoutError, asyncio.exceptions.TimeoutError):
                    print(
                        f"### TIMEOUT ({timeout} seconds) reading process {process.pid}, ignoring..."
                    )
                    kill_shell_and_children(process.pid)  # timeout
                    retcode = 124
                    return (retcode, "")
                except ValueError as e:
                    print(f"### VALUE ERROR: {repr(e)}")
                    kill_shell_and_children(process.pid)  # timeout
                    return (1, "")
                else:
                    if not line:  # EOF
                        break
                    else:
                        logfile.write(line)
                        if not quiet:
                            sys.stdout.buffer.write(line)
                            sys.stdout.flush()
                        continue
            retcode = await process.wait()  # wait for the child process to exit
            timer.cancel()
        except Exception as e:
            print(f"killing subprocess {process.pid} before re-raising exception <{repr(e)}>...")
            kill_shell_and_children(process.pid)
            raise e
    with open(logname, "r") as logfile:
        output = logfile.read()
    os.remove(logname)
    os.close(logfd)
    return (retcode, output)


loop = asyncio.get_event_loop()

for i in range(1, n_tries + 1):
    print(f"*** Generating command {i}/{n_tries}...")
    if ptests_mode:
        chosen_sources = " ".join(sources) if source_mode == "multi" else random.choice(sources)
        add_load = "-load " if source_mode == "load" else ""
        # TODO: find out how to get cpp_extra in ptests mode, so that we can
        # generate random arguments for options with 'function' template
        pre_options = generate_random_args(0, 10)
        post_options = generate_random_args(0, 10)
        cmdline = f"bin/ptests.opt -j 12 {add_load}{chosen_sources} -add-options-pre='{pre_options}' -add-options-post='{post_options} -autoload-plugins' -del-options=' -load-module[^ ]*cmxs' {extra_args}"
    else:
        chosen_sources = " ".join(sources) if source_mode == "multi" else random.choice(sources)
        cpp_extra = f'-cpp-extra-args="{cpp_extra_args}" ' if source_mode != "load" else ""
        add_load = "-load " if source_mode == "load" else ""
        functions = list_functions(chosen_sources, cpp_extra, add_load)
        cmdline = f"{framac} {mandatory_args} {add_load}{chosen_sources} {cpp_extra}{extra_args}"
        cmdline += generate_random_args(2, 15, functions=functions)
    print(f"running: {cmdline}")
    (retcode, res_stdout) = loop.run_until_complete(run_and_log_command(cmdline, timeout))
    if retcode == 4:
        if log_and_keep:
            logging.info(f"CRASH with: {cmdline}")
        else:
            sys.exit(f"Crash detected in Frama-C, stopping. Command line:\n{cmdline}")
    else:
        if retcode == 0:
            ok_tries += 1
        elif must_succeed:
            sys.exit(
                f"Frama-C returned {retcode} in mode MUST_SUCCEED, stopping. Command line:\n{cmdline}"
            )
        if res_stdout.find("Please report") != -1:
            if log_and_keep:
                logging.info(f"Fatal crash with: {cmdline}")
            else:
                if quiet:
                    print("### Output from fatal crash:")
                    print(res_stdout)
                if ptests_mode:
                    print(f"Detected fatal crash, interrupting execution. Command line:\n{cmdline}")
                    print("Automatically retrying command-line with -show...")
                    subproc = subprocess.run(cmdline + " -show", capture_output=True, shell=True)
                    res_stdout = subproc.stdout.decode("utf-8")
                    cmd_index = res_stdout.index("for command:")
                    if cmd_index != -1:
                        cmd_index += len("for command:") + 1
                        full_command = res_stdout[cmd_index : res_stdout.find("\n", cmd_index)]
                        # Remove redirection of stdout/stderr at end of command
                        if " >tests" in full_command:
                            redirection_index = full_command.index(">tests")
                            full_command = full_command[:redirection_index]
                        print(f"Found command used to crash: {full_command}")
                        # Remove outermost parentheses
                        full_command = full_command.strip(" ()")
                        # Split 'cd <dir> && (<command>' part (note: the
                        # rightmost parenthesis has already been stripped)
                        [test_dir, full_command] = full_command.split("&&", 1)
                        test_dir = (
                            test_dir[3:].strip().rstrip("/")
                        )  # remove 'cd ', trailing spaces and slashes
                        full_command = full_command.strip(" (")
                        minimize_cmd = (
                            str(script_dir / "minimize_crash_cmdline.py ")
                            + test_dir
                            + " "
                            + full_command
                        )
                        print(f"Running crash minimization script with: {minimize_cmd}")
                        os.system(minimize_cmd)
                        sys.exit(1)
                else:
                    sys.exit(
                        f"Detected fatal crash, interrupting execution. Command line:\n{cmdline}"
                    )


loop.close()

print(f"*** Executions ended without error: {ok_tries}/{n_tries} ({timeouts} timeouts)")
