#!/usr/bin/env python3
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Runs the tests of Eva in their default configuration with the recording of
# option -eva-hit-log, and writes a summary of the run.
#
# Each test run is a command of the ptests rules of plugins/eva/tests, a test
# or a single frama-c command run before the tests (EXECNOW). A run that fits
# the configuration of the recording (cvalue domain alone, memexec on, no
# option whose limits are accepted) is executed in several directories:
#   - hitlog: the command with -eva-hit-log;
#   - reference: the command with -eva-no-memexec, stopped after two minutes;
#   - memexec: the command as it is, whose output is the oracle of the test;
#   - stages, for a command of several stages (-then): the command with the
#     observer of plugins/eva/tests/hit_log/hit_log_observer.ml, which only
#     lists the stages that start an analysis of Eva (environment variable
#     HIT_LOG_OBSERVER_STAGES);
#   - observer-N, for each stage N that starts an analysis: the stages before
#     it, as in hitlog, then the stage N without the options that start an
#     analysis or print, and with -eva-hit-log; the observer, loaded, acts at
#     stage N only (HIT_LOG_OBSERVER_STAGE). It analyses copies of the project
#     without memexec and with memexec, then the project with -eva-hit-log,
#     asks each of them for the states at every point, and writes a summary
#     of the comparison (HIT_LOG_OBSERVER_SUMMARY).
# A command that loads a project saved by an EXECNOW command without analysis
# runs that command first, in each directory. The other runs are listed as
# not run, and the stages that are not observed as such, with the reason.
#
# Each invocation of the script writes the outputs of its commands in a new
# directory, named after its date, and each command in a new directory of
# it: a command reads nothing that an earlier invocation wrote, and a
# command that fails leaves no summary of an earlier one in its place. Each
# run records this invocation, the revision of the checkout and whether its
# tree has changes, taken when the script starts.
#
# The exit status of each observer is checked against the one expected from
# the exit statuses of the three commands of the run, whatever the observer
# writes: see expected_exits. The records that an observer writes are checked
# before they are counted: see damage. A stage whose records are damaged or
# incomplete is a failure, named in the summary, and none of its records is
# counted.
#
# Usage: dev/hit-log-suite.py [-j JOBS] [-o OUTDIR] [-w WORKDIR] [-k PATTERN]
#                             [--report]
#   -j JOBS     number of runs in parallel (default 8)
#   -o OUTDIR   directory of the results and of the summary; it must not be
#               in the checkout (default: a new temporary directory)
#   -w WORKDIR  directory in which the invocation creates the directory of
#               the outputs of its commands (default: OUTDIR/work); it must
#               not be in the checkout
#   -k PATTERN  only the runs whose name (suite/test.number) contains PATTERN;
#               the option can be repeated
#   --report    only write the summary again, from the results in OUTDIR
#
# It stops before the build when the checkout, OUTDIR or WORKDIR has less
# than FC_MIN_FREE_GB GiB free (default 5).
#
# Run it from the root of the checkout, with the opam switch active. It builds
# Frama-C, regenerates the ptests rules of Eva and builds the observer first.
# The summary is OUTDIR/summary.md; the results of each run are in
# OUTDIR/runs, and its outputs in the directory of the invocation.

import argparse
import collections
import concurrent.futures
import difflib
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

TESTS = "plugins/eva/tests"
# The directory that the tests name ../../../share from their result
# directory.
SHARE = "plugins/eva/share"
OBSERVER = "_build/default/plugins/eva/tests/hit_log/result/hit_log_observer.cmxs"
REFERENCE_TIMEOUT = 120
TIMEOUT = 900

# The suite of the observer's own tests, run by its ptests rules.
OBSERVER_SUITE = "hit_log"

# Separators of the stages of a command line.
THEN = {"-then", "-then-last", "-then-replace"}
THEN_ON = "-then-on"

# Options that start an analysis of Eva, directly or through another
# plug-in, and options that print after the analysis. They are removed from
# the command of the observer, which starts the analyses itself. The second
# set takes an argument.
ANALYSIS_FLAGS = {
    "-eva",
    "-out",
    "-input",
    "-deps",
    "-calldeps",
    "-inout",
    "-input-with-formals",
    "-inout-with-formals",
    "-out-external",
    "-deref",
    "-from-verify-assigns",
    "-scf",
    "-sparecode",
    "-users",
}
ANALYSIS_WITH_ARGUMENT = {
    "-eva-annot",
    "-slice-return",
    "-slice-threat",
    "-slice-calls",
    "-slice-pragma",
    "-slice-value",
    "-slice-rd",
    "-slice-wr",
}
PRINTING_FLAGS = {"-report", "-print"}

# The options above that have a negation -no-..., which the observer of a
# later stage sets when an earlier stage set the option.
NEGATED = {
    "-eva",
    "-out",
    "-input",
    "-deps",
    "-calldeps",
    "-inout",
    "-input-with-formals",
    "-out-external",
    "-deref",
    "-scf",
    "-sparecode",
    "-print",
    "-report",
}

# The reasons why the tests that load their own OCaml module are not run.
MODULE_REASONS = {
    "fval_test.cmxs": "unit program: its module tests the floating-point "
    "intervals of Eva (Fval) in OCaml, with no analysis of a program",
    "unit_tests.cmxs": "unit program: its module runs Eva.Unit_tests, the OCaml "
    "tests of the abstract values, with no analysis of a program",
    "legacy_reads.cmxs": "protocol test: its module makes requests and reads "
    "the reports of Eva.Legacy_read_trap, which the observer drives as well",
    "legacy_reads_projects.cmxs": "protocol test: its module copies and clears "
    "projects, makes requests in them and reads the reports of "
    "Eva.Legacy_read_trap, which the observer drives as well",
    "big_local_array_script.cmxs": "creates a project: its module creates the "
    "project prj and parses the file in it, then the stage -then-on prj prints "
    "it, with no option that starts an analysis",
}

# Options whose limits under -eva-hit-log are accepted in #87, or that are
# treated as such: the test is not run.
ACCEPTED_LIMITS = {
    "-eva-no-results-function": "accepted limit of #87: -eva-no-results-function",
    "-eva-no-results-domain": "accepted limit of #87: -eva-no-results-domain",
    "-eva-no-results": "accepted limit of #87: -eva-no-results disables the "
    "results of every domain, as -eva-no-results-domain",
    "-eva-report-red-statuses": "accepted limit of #87: the red-status export",
}

REFUSAL = "requires the cvalue domain alone"

# ----- Test runs ----------------------------------------------------------


def default_suites():
    with open(os.path.join(TESTS, "ptests_config")) as f:
        for line in f:
            if line.startswith("DEFAULT_SUITES="):
                return line.split("=", 1)[1].split()
    sys.exit("no DEFAULT_SUITES in ptests_config")


def strip_redirections(tokens):
    """The tokens of a command without its redirections."""
    return redirections(tokens)[0]


def redirections(tokens):
    """The tokens of a command without its redirections, and the files of
    its standard output and error, if they are redirected."""
    result = []
    files = {}
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in (">", "1>", "2>") and i + 1 < len(tokens):
            files["err" if t == "2>" else "out"] = tokens[i + 1]
            i += 2
        else:
            result.append(t)
            i += 1
    return result, files.get("out"), files.get("err")


def commands_file_tokens(suite, name):
    with open(os.path.join(TESTS, suite, name)) as f:
        return shlex.split(f.read(), comments=True)


def expand(suite, tokens):
    """The tokens with the contents of the commands files."""
    result = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "-commands-file" and i + 1 < len(tokens):
            result.extend(expand(suite, commands_file_tokens(suite, tokens[i + 1])))
            i += 2
        elif t.startswith("-commands-file="):
            name = t.split("=", 1)[1]
            result.extend(expand(suite, commands_file_tokens(suite, name)))
            i += 1
        else:
            result.append(t)
            i += 1
    return result


def option_name(token):
    return token.split("=", 1)[0] if token.startswith("-") else None


def split_stages(args):
    """The stages of a command line and the separators between them."""
    stages = [[]]
    separators = []
    i = 0
    while i < len(args):
        t = args[i]
        if t in THEN:
            separators.append([t])
            stages.append([])
            i += 1
        elif t == THEN_ON and i + 1 < len(args):
            separators.append([t, args[i + 1]])
            stages.append([])
            i += 2
        else:
            stages[-1].append(t)
            i += 1
    return stages, separators


def join_stages(stages, separators):
    args = list(stages[0])
    for separator, stage in zip(separators, stages[1:]):
        args += separator + stage
    return args


def add_to_each_stage(args, extra):
    stages, separators = split_stages(args)
    return join_stages([stage + extra for stage in stages], separators)


def starts_analysis(token):
    name = option_name(token)
    return name in ANALYSIS_FLAGS or name in ANALYSIS_WITH_ARGUMENT


def with_module(tokens, observer):
    """[tokens] with the observer loaded after the plug-ins."""
    result = []
    loaded = False
    i = 0
    while i < len(tokens):
        t = tokens[i]
        result.append(t)
        if t == "-load-plugin" and i + 1 < len(tokens):
            result.append(tokens[i + 1])
            i += 1
        if t.startswith("-load-plugin") and not loaded:
            result.append("-load-module=" + observer)
            loaded = True
        i += 1
    if not loaded:
        result.append("-load-module=" + observer)
    return result


def without_analysis(stage):
    """The tokens of [stage] without the options that start an analysis or
    print, and these options."""
    kept, removed = [], []
    i = 0
    while i < len(stage):
        t = stage[i]
        name = option_name(t)
        if name in ANALYSIS_WITH_ARGUMENT and "=" not in t and i + 1 < len(stage):
            removed.append(t + " " + stage[i + 1])
            i += 2
        elif starts_analysis(t) or name in PRINTING_FLAGS:
            removed.append(t)
            i += 1
        else:
            kept.append(t)
            i += 1
    return kept, removed


def set_before(stages):
    """The options that start an analysis or print, set by [stages] and in
    effect after them, and those of them that take an argument, with their
    stage."""
    on = set()
    with_argument = []
    for number, stage in enumerate(stages, 1):
        for t in stage:
            name = option_name(t)
            if name in ANALYSIS_FLAGS or name in PRINTING_FLAGS:
                on.add(name)
            elif name in ANALYSIS_WITH_ARGUMENT:
                with_argument.append((number, t))
            elif name and name.startswith("-no-"):
                on.discard("-" + name[len("-no-") :])
    return on, with_argument


def observer_args(stages, separators, number, observer):
    """The arguments of the observer of stage [number] (the first is 1), the
    options of that stage whose effects after the analysis are not observed,
    and the reason why the stage is not observed, if it is not. The stages
    before it run as in hitlog, with the observer loaded; the stage itself
    without the options that start an analysis or print, those that the
    stages before set being reset, and with -eva-hit-log."""
    before = stages[: number - 1]
    switches = [" ".join(s) for s in separators[: number - 1] if s[0] != "-then"]
    if switches:
        return (
            None,
            [],
            "the stages before it change the project (%s): the observer does not follow a "
            "change of project" % ", ".join(switches),
        )
    on, with_argument = set_before(before)
    if with_argument:
        stage, option = with_argument[0]
        return (
            None,
            [],
            (
                "the option %s of stage %d, which starts an analysis, cannot be "
                "reset" % (option, stage)
            ),
        )
    kept, removed = without_analysis(stages[number - 1])
    fixed = sorted(on - NEGATED)
    if fixed:
        return (
            None,
            [],
            ("the option %s of an earlier stage cannot be reset" % fixed[0]),
        )
    not_observed = sorted(on - {"-eva"})
    for t in removed:
        name = option_name(t.split(" ")[0])
        shown = t if name in ANALYSIS_WITH_ARGUMENT else name
        if shown != "-eva" and shown not in not_observed:
            not_observed.append(shown)
    reset = ["-no-" + name[1:] for name in sorted(on)]
    staged = [s + ["-eva-hit-log"] for s in before]
    staged.append(kept + reset + ["-eva-hit-log"])
    staged[0] = with_module(staged[0], observer)
    return join_stages(staged, separators[: number - 1]), not_observed, None


def saving_runs(runs):
    """The runs that save a project, by suite and file."""
    saves = {}
    for run in runs:
        tokens = redirections(shlex.split(run["cmd"]))[0]
        if tokens[:1] != ["frama-c"]:
            continue
        for i, t in enumerate(tokens):
            if t == "-save" and i + 1 < len(tokens):
                saves[(run["suite"], os.path.normpath(tokens[i + 1]))] = run
    return saves


def loaded_save(run, tokens, saves):
    """The prerequisite of a run that loads a saved project: the command
    that saves it, without analysis; or the reason why the run is not run."""
    for i, t in enumerate(tokens):
        if t != "-load" or i + 1 >= len(tokens):
            continue
        name = os.path.normpath(tokens[i + 1])
        saving = saves.get((run["suite"], name)) or saves.get(
            (run["suite"], re.sub(r"\.error$", "", name))
        )
        if saving is None:
            return None, "loads a saved project that no command of the suite saves"
        saving_tokens = redirections(shlex.split(saving["cmd"]))[0][1:]
        flags = [t for t in saving_tokens if starts_analysis(t)]
        if flags:
            return None, (
                "saved project with computed results: loads the project that "
                "%s saves after its analysis (%s), and queries its results"
                % (saving["name"], " ".join(flags))
            )
        return {"name": saving["name"], "args": saving_tokens}, None
    return None, None


def static_reason(tokens):
    """The reason why a run is not executed, from its options."""
    names = [option_name(t) for t in tokens]
    for i, t in enumerate(tokens):
        name = option_name(t)
        if name == "-load-module":
            module = t.split("=", 1)[1] if "=" in t else tokens[i + 1]
            return MODULE_REASONS.get(
                os.path.basename(module),
                "other: the test loads its own OCaml module %s" % module,
            )
    if "-eva-no-memexec" in names:
        return "memexec disabled by the test"
    for option, reason in ACCEPTED_LIMITS.items():
        if option in names:
            return reason
    return None


def runs_of_suite(suite):
    runs = []
    for path in sorted(glob.glob(os.path.join(TESTS, suite, "result", "*.wtests"))):
        with open(path) as f:
            test = json.load(f)
        m = re.match(r"(TEST|EXECNOW) #(\d+) OF TEST FILE (\S+)", test["info"])
        kind, number, source = m.group(1), int(m.group(2)), m.group(3)
        base = os.path.basename(source)
        name = "%s/%s.%d%s" % (
            suite,
            os.path.splitext(base)[0],
            number,
            "" if kind == "TEST" else ".execnow",
        )
        run = {
            "name": name,
            "suite": suite,
            "source": base,
            "kind": kind,
            "cmd": test["cmd"],
            "out": test.get("out"),
            "err": test.get("err"),
            "tmpout": test.get("tmpout"),
            "tmperr": test.get("tmperr"),
            "sedout": test.get("sedout"),
            "sederr": test.get("sederr"),
            "oracle_out": test.get("oracle_out"),
            "oracle_err": test.get("oracle_err"),
        }
        if kind == "EXECNOW":
            # The logs of an EXECNOW command are its redirections, compared
            # with the files of the same name in its oracle directory.
            _, out, err = redirections(shlex.split(test["cmd"]))
            oracles = test.get("oracle_dir", "../oracle")
            run["out"] = os.path.basename(out) if out else name + ".res.log"
            run["err"] = os.path.basename(err) if err else name + ".err.log"
            for log in ["out", "err"]:
                if run[log] in [os.path.basename(f) for f in test.get("log", [])]:
                    run["oracle_" + log] = os.path.join(oracles, run[log])
        runs.append(run)
    return runs


def observer_suite_reason(run):
    """The reason why a run of the observer's own suite is not run here."""
    rules = "run by the ptests rules of the suite (@%s/%s/ptests_config)" % (
        TESTS,
        OBSERVER_SUITE,
    )
    if run["kind"] != "TEST":
        return "hit_log: EXECNOW that saves the project a fixture loads, " + rules
    modules = sorted(
        {
            os.path.splitext(os.path.basename(m))[0]
            for found in re.findall(r"-load-module[= ](\S+)", run["cmd"])
            for m in found.split(",")
        }
    )
    others = [m for m in modules if m != "hit_log_observer"]
    if "hit_log_observer" in modules and not others:
        return "hit_log: fixture of the observer, " + rules
    if "hit_log_observer" in modules:
        return "hit_log: fixture of the observer with its own module %s, %s" % (
            ", ".join(others),
            rules,
        )
    return "hit_log: fixture with its own module %s and not the observer, %s" % (
        ", ".join(others),
        rules,
    )


def classify(run, saves):
    """Fills the arguments of the commands of a run, or the reason why it is
    not run. [saves] are the runs that save a project."""
    if run["suite"] == OBSERVER_SUITE:
        run["not_run"] = observer_suite_reason(run)
        return
    cmd = run["cmd"]
    if not cmd.startswith("frama-c ") or re.search(r"[|;&{}]", cmd):
        programs = re.findall(r"(?:^|[|;&{]\s*)([\w.-]+)", cmd)
        if programs[:1] == ["diff"]:
            run["not_run"] = "other: compares the outputs of two tests (diff), with no " "analysis"
        else:
            # The frama-c commands of the group that start an analysis: they
            # are not observed, and the reason says so.
            analyses = [
                " ".join(t for t in shlex.split(segment)[1:] if starts_analysis(t))
                for segment in re.split(r"[|;&{}]+", cmd)
                if segment.split()[:1] in (["frama-c"], ["%{bin:frama-c}"])
                and any(starts_analysis(t) for t in shlex.split(segment)[1:])
            ]
            run["not_run"] = (
                "other: not a single frama-c command, but a shell group of "
                "%s" % ", ".join(dict.fromkeys(programs))
            ) + (
                "; its frama-c commands start analyses (%s) that are not observed"
                % ", ".join(analyses)
                if analyses
                else ""
            )
        return
    tokens = strip_redirections(shlex.split(cmd))[1:]
    expanded = expand(run["suite"], tokens)
    reason = static_reason(expanded)
    if reason:
        run["not_run"] = reason
        return
    prerequisite, reason = loaded_save(run, expanded, saves)
    if reason:
        run["not_run"] = reason
        return
    if run["kind"] == "EXECNOW" and not any(starts_analysis(t) for t in expanded):
        saved = [expanded[i + 1] for i, t in enumerate(expanded[:-1]) if t == "-save"]
        run["not_run"] = "other: EXECNOW without an option that starts an " "analysis" + (
            ": it saves the parsed program (-save %s), and a run that loads "
            "it runs it first" % saved[0]
            if saved
            else ""
        )
        return
    run["args"] = tokens
    run["expanded"] = expanded
    if prerequisite:
        run["prerequisite"] = prerequisite


# ----- Execution ----------------------------------------------------------


def included_files(directory, name, seen):
    """[name] and the files of [directory] that it includes, recursively."""
    if name in seen or not os.path.isfile(os.path.join(directory, name)):
        return
    seen.add(name)
    try:
        with open(os.path.join(directory, name), errors="replace") as f:
            text = f.read()
    except OSError:
        return
    for included in re.findall(r'#\s*include\s*"([^"]+)"', text):
        included_files(directory, os.path.normpath(included), seen)


def prepare_directory(run, directory):
    """Creates [directory], which must not exist, and links into it the files
    of the suite that the run uses."""
    suite_dir = os.path.abspath(os.path.join(TESTS, run["suite"]))
    os.makedirs(directory)
    names = set()
    for entry in os.listdir(suite_dir):
        path = os.path.join(suite_dir, entry)
        if os.path.isfile(path) and not re.search(r"\.[ci]$", entry):
            names.add(entry)
    sources = set()
    for t in [run["source"]] + run["expanded"]:
        for candidate in [t] + t.split("=")[1:]:
            included_files(suite_dir, os.path.normpath(candidate), sources)
    for name in names | sources:
        target = os.path.join(directory, name)
        if not os.path.lexists(target) and os.sep not in name:
            os.symlink(os.path.join(suite_dir, name), target)


def execute(run, argv, directory, env, timeout):
    """Runs [argv] in [directory], with the output files of the test, then
    its filters."""
    start = time.monotonic()
    out = os.path.join(directory, run["tmpout"] or run["out"])
    err = os.path.join(directory, run["tmperr"] or run["err"])
    with open(out, "w") as o, open(err, "w") as e:
        try:
            proc = subprocess.run(argv, cwd=directory, stdout=o, stderr=e, env=env, timeout=timeout)
            status = proc.returncode
        except subprocess.TimeoutExpired:
            status = "timeout"
    for name in ["sedout", "sederr"]:
        if run[name]:
            subprocess.run(run[name], shell=True, cwd=directory, env=env)
    return {"status": status, "time": round(time.monotonic() - start, 2)}


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_summary(path):
    records = []
    text = read(path)
    if text:
        for line in text.splitlines():
            records.append(line.split("\t"))
    return records


def diff(a, b, name_a, name_b):
    """The lines of a unified diff of two texts, without its header."""
    if a == b:
        return []
    lines = difflib.unified_diff(
        (a or "").splitlines(), (b or "").splitlines(), name_a, name_b, lineterm="", n=1
    )
    return list(lines)[2:]


def parse_stages(path):
    """The stages that the observer lists in the file [path]: by number,
    the project of the stage, the projects of the analyses that start in it,
    and whether the command finishes it."""
    stages = {}
    for fields in parse_summary(path):
        if fields[:1] == ["stage"] and len(fields) >= 4:
            stages[int(fields[1])] = {
                "project": fields[2],
                "analyses": [p for p in fields[3].split(",") if p],
                "unfinished": fields[4:] == ["unfinished"],
            }
    return stages


def stage_plan(run, counted, status, observer):
    """For each stage of the command of [run], whether it is observed, with
    the arguments of its observer and the options not observed, or the
    reason why it is not. [counted] are the stages listed by the observer
    for a command of several stages, run with the exit status [status]."""
    stages, separators = split_stages(run["expanded"])
    plan = []
    for number in range(1, len(stages) + 1):
        entry = {"stage": number, "reason": None}
        if len(stages) == 1:
            if not any(starts_analysis(t) for t in stages[0]):
                entry["reason"] = "no option starts an analysis"
        elif counted is None or number not in counted:
            entry["reason"] = "the command stops before this stage (exit %s)" % status
        else:
            c = counted[number]
            if not c["analyses"]:
                _, removed = without_analysis(stages[number - 1])
                entry["reason"] = "no analysis starts in this stage" + (
                    "; its options %s act after the analysis of an earlier stage, and are not "
                    "observed" % " ".join(removed)
                    if removed
                    else ""
                )
            elif len(c["analyses"]) > 1:
                entry["reason"] = "%d analyses start in this stage" % len(c["analyses"])
            elif c["analyses"][0] != c["project"]:
                entry["reason"] = (
                    "the analysis starts in project %s, not in project %s of "
                    "the stage" % (c["analyses"][0], c["project"])
                )
            entry["unfinished"] = c["unfinished"]
        if entry["reason"] is None:
            args, not_observed, reason = observer_args(stages, separators, number, observer)
            entry["reason"] = reason
            entry["args"] = args
            entry["not_observed"] = not_observed
        entry["observed"] = entry["reason"] is None
        plan.append(entry)
    return plan


def run_prerequisite(run, directory, env):
    """Runs in [directory] the command that saves the project that [run]
    loads."""
    prerequisite = run.get("prerequisite")
    if prerequisite:
        with open(os.path.join(directory, "prerequisite.res"), "w") as o, open(
            os.path.join(directory, "prerequisite.err"), "w"
        ) as e:
            subprocess.run(
                [env["FRAMA_C"]] + prerequisite["args"],
                cwd=directory,
                stdout=o,
                stderr=e,
                env=env,
                timeout=TIMEOUT,
            )


def run_one(run, work_root, env, observer, provenance):
    work = os.path.join(work_root, run["name"])
    result = {"name": run["name"], "provenance": provenance}
    variants = {
        "hitlog": add_to_each_stage(run["args"], ["-eva-hit-log"]),
        "reference": add_to_each_stage(run["args"], ["-eva-no-memexec"]),
        "memexec": run["args"],
    }
    commands = {}
    for variant in ["hitlog", "reference", "memexec"]:
        args = variants[variant]
        directory = os.path.join(work, variant)
        prepare_directory(run, directory)
        run_prerequisite(run, directory, env)
        argv = [env["FRAMA_C"]] + args
        commands[variant] = shlex.join(argv)
        timeout = REFERENCE_TIMEOUT if variant == "reference" else TIMEOUT
        result[variant] = execute(run, argv, directory, env, timeout)
        if variant == "hitlog":
            text = (read(os.path.join(directory, run["out"])) or "") + (
                read(os.path.join(directory, run["err"])) or ""
            )
            if REFUSAL in text:
                result["not_run"] = "another domain enabled: recording refused"
                break
        if variant == "reference" and result[variant]["status"] == "timeout":
            result["not_run"] = "reference too costly (over %d s)" % REFERENCE_TIMEOUT
            break
    if "not_run" in result:
        result["commands"] = commands
        return result
    result["commands"] = commands
    out = {
        v: (
            read(os.path.join(work, v, run["out"])),
            read(os.path.join(work, v, run["err"])) or "",
        )
        for v in ["hitlog", "reference", "memexec"]
    }
    oracle_dir = os.path.join(TESTS, run["suite"], "result")
    oracle = (
        read(os.path.join(oracle_dir, run["oracle_out"] or "")),
        read(os.path.join(oracle_dir, run["oracle_err"] or "")) or "",
    )
    result["memexec_matches_oracle"] = out["memexec"] == oracle
    result["log_diffs"] = {}
    for a, b in [
        ("memexec", "hitlog"),
        ("reference", "memexec"),
        ("reference", "hitlog"),
    ]:
        result["log_diffs"][a + " -> " + b] = {
            "res": diff(out[a][0], out[b][0], a, b),
            "err": diff(out[a][1], out[b][1], a, b),
        }
    # The stages that start an analysis, for a command of several stages.
    counted = None
    status = None
    if len(split_stages(run["expanded"])[0]) > 1:
        directory = os.path.join(work, "stages")
        prepare_directory(run, directory)
        run_prerequisite(run, directory, env)
        argv = [env["FRAMA_C"]] + with_module(run["expanded"], observer)
        commands["stages"] = shlex.join(argv)
        stages_env = dict(env)
        stages_env["HIT_LOG_OBSERVER_STAGES"] = os.path.join(directory, "stages")
        result["stages run"] = execute(run, argv, directory, stages_env, TIMEOUT)
        status = result["stages run"]["status"]
        # The observer creates the file when it is loaded. It only lists
        # the stages: the command exits as without it.
        result["stages run"]["loaded"] = os.path.isfile(os.path.join(directory, "stages"))
        if not result["stages run"]["loaded"]:
            result["stages failure"] = (
                "the observer that lists the stages is not loaded (exit %s)" % status
            )
        elif status != result["memexec"]["status"]:
            result["stages failure"] = (
                "the observer that lists the stages exits with %s, where the "
                "command exits with %s" % (status, result["memexec"]["status"])
            )
        counted = parse_stages(os.path.join(directory, "stages"))
    plan = stage_plan(run, counted, status, observer)
    result["stages"] = [{k: v for k, v in entry.items() if k != "args"} for entry in plan]
    result["observers"] = []
    for entry in plan:
        if not entry["observed"]:
            continue
        variant = "observer-%d" % entry["stage"]
        directory = os.path.join(work, variant)
        prepare_directory(run, directory)
        run_prerequisite(run, directory, env)
        argv = [env["FRAMA_C"]] + entry["args"]
        commands[variant] = shlex.join(argv)
        observer_env = dict(env)
        observer_env["HIT_LOG_OBSERVER_SUMMARY"] = os.path.join(directory, "summary")
        observer_env["HIT_LOG_OBSERVER_STAGE"] = str(entry["stage"])
        observed = execute(run, argv, directory, observer_env, TIMEOUT)
        observed["stage"] = entry["stage"]
        # The observer creates the summary when it is loaded: the directory
        # is new, so a summary is that of this command.
        observed["loaded"] = os.path.isfile(os.path.join(directory, "summary"))
        observed["summary"] = parse_summary(os.path.join(directory, "summary"))
        result["observers"].append(observed)
    statuses = {result[v]["status"] for v in ["hitlog", "reference", "memexec"]}
    status = statuses.pop() if len(statuses) == 1 else 0
    if (
        status != 0
        and "stages failure" not in result
        and all(
            o["loaded"] and phase_of(o) == "start" and o["status"] == status
            for o in result["observers"]
        )
    ):
        # A command that stops before an analysis starts, as one whose file
        # does not parse, in every mode: the observer is loaded, and stops
        # as the command does, before its stage. For a command of several
        # stages, the observer has not found an analysis that starts.
        if len(plan) == 1 or not result["observers"]:
            result["not_run"] = "other: every command stops before the analysis (exit %s)" % status
    return result


def build(jobs):
    def step(argv):
        print("+ " + shlex.join(argv), flush=True)
        subprocess.run(argv, check=True)

    step(["dune", "build", "-j", str(jobs), "@install"])
    step(["dune", "exec", "--", "frama-c-ptests", TESTS])
    step(["dune", "build", "-j", str(jobs), OBSERVER])
    env = subprocess.run(
        ["dune", "exec", "--", "env", "-0"], check=True, capture_output=True
    ).stdout
    env = dict(item.split("=", 1) for item in env.decode().split("\0") if "=" in item)
    env["FRAMA_C"] = shutil.which("frama-c", path=env["PATH"])
    return env


def without_observer_variables(env):
    """[env] without the variables that the observer reads, as its controls:
    the script sets those of each command."""
    return {k: v for k, v in env.items() if not k.startswith("HIT_LOG_OBSERVER_")}


# ----- Summary ------------------------------------------------------------

VERDICTS = ["equal", "covers", "more precise", "OMITS", "unavailable", "unresolved"]


ANSWER_FIELDS = [
    "kind",
    "function",
    "description",
    "request",
    "recording",
    "memexec",
    "origin",
    "case",
]


def answer(fields):
    """An answer record of the observer, by field."""
    return dict(zip(ANSWER_FIELDS, fields + [""] * len(ANSWER_FIELDS)))


def records(result, kind):
    return [r[1:] for r in result.get("summary", []) if r and r[0] == kind]


def first(result, kind):
    found = records(result, kind)
    return found[0] if found else None


def phase_of(result):
    phases = records(result, "phase")
    return phases[-1][0] if phases else "start"


def observations(result):
    """The observations of a run, one per observed stage, with the name of
    the run, labelled with the stage for a command of several stages, and
    whether the stage is the first observed one of the run. A result of an
    earlier version of this script has one observation, of the first
    analysis."""
    found = result.get("observers")
    if found is None:
        found = []
        if "observer" in result:
            found = [dict(result["observer"], stage=1, summary=result.get("summary", []))]
    listed = {o["stage"] for o in found}
    found = found + [
        dict(stage=s["stage"], failure="missing observer")
        for s in stages_of(result)
        if s["observed"] and s["stage"] not in listed
    ]
    several = len(stages_of(result)) > 1
    first_stage = min((o["stage"] for o in found), default=None)
    checked = []
    for o in found:
        if "failure" not in o:
            problem = record_shape_damage(o)
            if problem:
                o = dict(o, failure="damaged records: " + problem)
        checked.append(
            dict(
                o,
                name=result["name"] + (" stage %d" % o["stage"] if several else ""),
                first=o["stage"] == first_stage,
                expected=None if "failure" in o else expected_exits(result, o),
            )
        )
    return checked


def expected_exits(result, o):
    """The exit statuses expected from the observer of a stage, from the exit
    statuses of the three commands of its run and from the stages that the
    command reaches, and why.

    The command of the observer runs the stages of the test command up to
    its stage, and the three analyses in one process:
    - if the command reaches a later stage, it does not stop in this one:
      the observer exits with 0;
    - otherwise the observer exits as the commands do, with one of their
      statuses: with 0 if they do, and with 1 for an error of the analysed
      program, which each analysis reports;
    - but an analysis that stops (record "stopped") ends a command with a
      status that is not 0, while the observer, which catches the stop to
      go on with the two other analyses, then exits with 0."""
    statuses = sorted({result[v]["status"] for v in ["hitlog", "reference", "memexec"]}, key=str)
    reached = [
        s["stage"]
        for s in stages_of(result)
        if not (s.get("reason") or "").startswith("the command stops before this stage")
    ]
    if o["stage"] < max(reached, default=o["stage"]):
        return [0], "the command reaches a later stage"
    if statuses != [0] and records(o, "stopped"):
        return [0], "an analysis stops, which ends the commands with exit %s" % ", ".join(
            str(s) for s in statuses
        )
    return statuses, "the commands exit with %s" % ", ".join(str(s) for s in statuses)


def stages_of(result):
    """The stages of a run. A result of an earlier version of this script
    has the first analysis only, observed or not."""
    if "stages" in result:
        return result["stages"]
    if "observer" in result:
        return [{"stage": 1, "observed": True, "reason": None}]
    return [
        {
            "stage": 1,
            "observed": False,
            "reason": result.get("observer_not_run", "not recorded"),
        }
    ]


# The version of the records that the observer writes, in its record
# "format". A summary without this record is of an earlier version of the
# observer.
FORMAT = "4"

INT = "a number"
DECIMAL = "a decimal number"
TEXT = "a text"
THREE_RUNS = {"reference", "recording", "memexec"}
TWO_RUNS = {"recording", "memexec"}

# The fields of each kind of record, after the kind: a number, a decimal
# number, a text, or one of the values of a set.
SHAPES = {
    "format": [TEXT],
    "control": [TEXT, TEXT],
    "phase": [{"reference", "memexec", "recording", "requests", "done"}],
    "stopped": [],
    "no result": [],
    "error": [TEXT],
    "unresolved": [TEXT, TEXT, TEXT],
    "summarised": [TEXT, TEXT, TEXT],
    "below rebuilt": [{"not listed", "not rebuilt", "crossing"}, TEXT],
    "answer": [
        TEXT,
        TEXT,
        TEXT,
        {"joined", "filtered", "callstack"},
        set(VERDICTS),
        set(VERDICTS) | {"not compared"},
        TEXT,
        TEXT,
    ],
    "unreachable statements": [THREE_RUNS, INT],
    "unreachable": [TWO_RUNS, {"only in this run", "only in the reference"}, TEXT, TEXT],
    "initial": [set(VERDICTS)],
    "calls": [INT] * 5,
    "heap calls": [INT] * 4,
    "requests": [TEXT, TEXT, INT],
    "verdicts": [TWO_RUNS] + [INT] * len(VERDICTS),
    "not compared": [{"memexec"}, INT],
    "callstacks": [INT, INT],
    "callstacks filtered": [INT, INT],
    "trap": [INT, INT, {"matched", "unmatched"}, INT],
    "passes": [TWO_RUNS, INT, INT, INT],
    "pass": [TEXT, INT],
    "below requests": [INT],
    "properties": [INT],
    "status": [
        TWO_RUNS,
        TEXT,
        TEXT,
        TEXT,
        {"MORE OPTIMISTIC", "less optimistic", "different"},
        TEXT,
    ],
    "alarms": [THREE_RUNS, INT],
    "alarm": [THREE_RUNS, {"missing", "added"}, TEXT],
    "statistics": [THREE_RUNS, DECIMAL, DECIMAL, INT],
    "messages": [
        TWO_RUNS,
        {"equal", "equal up to the names of the created bases", "unresolved", "differ"},
    ],
}

# The shapes that differ in the records of an earlier version of the
# observer: it did not count the unresolved answers at first, did not give
# the reason of an unresolved base, and compared the messages up to the
# suffixes of the names at first.
EARLIER_SHAPES = {
    "verdicts": [[TWO_RUNS] + [INT] * n for n in (len(VERDICTS) - 1, len(VERDICTS))],
    "unresolved": [[TEXT, TEXT]],
    "messages": [
        [TWO_RUNS, SHAPES["messages"][1] | {"equal up to the suffixes of the names"}],
    ],
}

# The records that a complete summary has once: the kind, and the first
# field for a record written for each run. Those of the second list are not
# in the summaries of an earlier version of the observer.
REQUIRED = (
    [
        ("calls", None),
        ("verdicts", "recording"),
        ("verdicts", "memexec"),
        ("callstacks", None),
        ("callstacks filtered", None),
        ("trap", None),
        ("passes", "memexec"),
        ("passes", "recording"),
        ("below requests", None),
        ("properties", None),
        ("initial", None),
        ("messages", "recording"),
        ("messages", "memexec"),
    ]
    + [("alarms", run) for run in sorted(THREE_RUNS)]
    + [("statistics", run) for run in sorted(THREE_RUNS)]
)
REQUIRED_SINCE_FORMAT = [
    ("format", None),
    ("not compared", "memexec"),
    ("heap calls", None),
] + [("unreachable statements", run) for run in sorted(THREE_RUNS)]

PHASES = ["reference", "memexec", "recording", "requests", "done"]


def fits(field, shape):
    if shape == INT:
        return re.fullmatch(r"\d+", field) is not None
    if shape == DECIMAL:
        # The coverage of an analysis that reaches no statement is printed
        # as -nan.
        return re.fullmatch(r"\d+\.\d+|-?nan", field) is not None
    if shape == TEXT:
        return True
    return field in shape


def describe_record(rec):
    text = " ".join(rec)
    return "`%s`" % (text if len(text) <= 60 else text[:60] + "...")


def has_format(o):
    """Whether the summary of an observation has the record of its format:
    one without it is of an earlier version of the observer."""
    return bool(records(o, "format"))


def record_shape_damage(o):
    summary = o.get("summary")
    if not isinstance(summary, list) or not all(
        isinstance(rec, list) and rec and all(isinstance(f, str) for f in rec) for rec in summary
    ):
        return "the summary is not a list of records"
    current = has_format(o)
    for rec in summary:
        kind, fields = rec[0], rec[1:]
        if kind not in SHAPES:
            return "unknown record %s" % describe_record(rec)
        shapes = [SHAPES[kind]]
        if not current:
            shapes = EARLIER_SHAPES.get(kind, shapes)
        if not any(len(fields) == len(shape) for shape in shapes):
            return "the record %s has %d fields, not %s" % (
                describe_record(rec),
                len(fields),
                " or ".join(str(len(shape)) for shape in shapes),
            )
        shape = next(shape for shape in shapes if len(fields) == len(shape))
        for position, (field, expected) in enumerate(zip(fields, shape), 1):
            if not fits(field, expected):
                return "the field %d of the record %s is not %s" % (
                    position,
                    describe_record(rec),
                    (
                        expected
                        if isinstance(expected, str)
                        else "one of " + ", ".join(sorted(expected))
                    ),
                )
    return None


def damage(o):
    """What is damaged or missing in the records of an observation that the
    observer ended (phase "done") with a result: the first defect found, or
    None. The records are checked before any of them is counted:
    - each record is of a known kind, with the number of fields of its kind,
      numbers where its kind has numbers, and known values where it has a
      closed set of values;
    - the records that a complete summary has once are there once, among
      them the record of the trap and those of the passes;
    - the phases are those of a complete run, in order;
    - the counts agree with each other: the requests per kind with the
      requests of the trap, the requests per pass with those of the passes,
      the verdicts with the requests that have a verdict, and the answers
      listed with the verdicts that are not "equal".
    A summary of an earlier version of the observer is checked with the
    shapes and the records of that version."""
    current = has_format(o)
    if current and records(o, "format") != [[FORMAT]]:
        return "the records are of the format %s, not %s" % (
            " ".join(sum(records(o, "format"), [])),
            FORMAT,
        )
    if records(o, "control"):
        return "the run is under a control of the observer: %s" % " ".join(records(o, "control")[0])
    for kind, key in REQUIRED + (REQUIRED_SINCE_FORMAT if current else []):
        found = [rec for rec in records(o, kind) if key is None or rec[0] == key]
        if len(found) != 1:
            return "%s `%s`" % (
                "no record" if not found else "%d records" % len(found),
                kind + (" " + key if key else ""),
            )
    phases = [rec[0] for rec in records(o, "phase")]
    if phases != PHASES:
        return "the phases are %s, not %s" % (", ".join(phases), ", ".join(PHASES))

    def one(kind, key=None):
        found = [rec for rec in records(o, kind) if key is None or rec[0] == key][0]
        return [int(f) for f in found if re.fullmatch(r"\d+", f)]

    requests = [(what, int(n)) for _, what, n in records(o, "requests")]
    made = sum(n for _, n in requests)
    with_verdict = sum(n for what, n in requests if what in ("joined", "filtered", "callstack"))
    trap = one("trap")
    if made != trap[0]:
        return "%d requests per kind, and %d requests made in the record of the trap" % (
            made,
            trap[0],
        )
    per_pass = sum(int(n) for _, n in records(o, "pass"))
    if per_pass != one("passes", "recording")[0]:
        return "%d requests per pass, and %d requests in the record of the passes" % (
            per_pass,
            one("passes", "recording")[0],
        )
    not_compared = one("not compared", "memexec")[0] if current else 0
    answers = [answer(a) for a in records(o, "answer")]
    for run, missing in [("recording", 0), ("memexec", not_compared)]:
        verdicts = one("verdicts", run)
        if sum(verdicts) + missing != with_verdict:
            return "%d verdicts of the run %s%s, and %d requests with a verdict" % (
                sum(verdicts),
                run,
                ", %d answers not compared" % missing if missing else "",
                with_verdict,
            )
        listed = len([a for a in answers if a[run] not in ("equal", "not compared")])
        if listed != sum(verdicts) - verdicts[0]:
            return "%d answers listed as not equal for the run %s, and %d in its verdicts" % (
                listed,
                run,
                sum(verdicts) - verdicts[0],
            )
    return None


def result_damage(result):
    """What is damaged in the result of a run, read from its file, before
    its observations are read: None if it has the fields that the summary
    uses, of the types it expects."""

    def texts(value):
        return isinstance(value, list) and all(isinstance(item, str) for item in value)

    def is_status(execution):
        return isinstance(execution, dict) and (
            type(execution.get("status")) is int or execution.get("status") == "timeout"
        )

    if not isinstance(result, dict) or not isinstance(result.get("name"), str):
        return "the result has no name"
    if "provenance" in result or "stages" in result:
        p = result.get("provenance")
        if not isinstance(p, dict) or not isinstance(p.get("revision"), str):
            return "missing or invalid provenance.revision"
        if not texts(p.get("changes")):
            return "missing or invalid provenance.changes"
        if "invocation" in p and not isinstance(p["invocation"], str):
            return "missing or invalid provenance.invocation"
    if "not_run" in result:
        return None if isinstance(result["not_run"], str) else "the reason not run is not a text"
    for variant in ["hitlog", "reference", "memexec"]:
        if not is_status(result.get(variant)):
            return "no exit status of the command %s" % variant
    found = result.get("observers")
    if found is None and "observer" in result:
        # A result of an earlier version of this script.
        found = [dict(result["observer"], stage=1)] if is_status(result["observer"]) else None
    if not isinstance(found, list):
        return "no list of observers"
    for o in found:
        if not is_status(o) or type(o.get("stage")) is not int:
            return "an observer without stage or exit status"
        # Earlier records predate invocation directories and the format row.
        if (
            isinstance(o.get("summary"), list)
            and ["format", FORMAT] in o["summary"]
            and "invocation" not in result.get("provenance", {})
        ):
            return "missing or invalid provenance.invocation"
        if type(o.get("loaded", True)) is not bool or not isinstance(o.get("failure", ""), str):
            return "invalid observer loaded flag or failure"
    for field in ["stages failure", "observer_not_run"]:
        if field in result and not isinstance(result[field], str):
            return "invalid " + field
    if type(result.get("memexec_matches_oracle")) is not bool:
        return "missing or invalid memexec_matches_oracle"
    stages = result.get("stages", [])
    if not isinstance(stages, list) or not all(
        isinstance(s, dict) and type(s.get("stage")) is int and type(s.get("observed")) is bool
        for s in stages
    ):
        return "the stages are not a list of stages"
    for s in stages:
        if s["observed"]:
            if "reason" not in s or s["reason"] is not None:
                return "invalid reason for observed stage %d" % s["stage"]
        elif not isinstance(s.get("reason"), str):
            return "missing or invalid reason for unobserved stage %d" % s["stage"]
        if (s["observed"] or "not_observed" in s) and not texts(s.get("not_observed")):
            return "missing or invalid not_observed options for stage %d" % s["stage"]
    if "stages" in result:
        expected = [s["stage"] for s in stages if s["observed"]]
        listed = [o["stage"] for o in found]
        if len(set(listed)) != len(listed) or set(listed) - set(expected):
            return "duplicate observer or observer of an unobserved stage"
    diffs = result.get("log_diffs")
    if not isinstance(diffs, dict):
        return "the differences of the outputs are not recorded by pair"
    for pair in ["memexec -> hitlog", "reference -> memexec", "reference -> hitlog"]:
        if pair not in diffs:
            return "missing log difference " + pair
    for pair, difference in diffs.items():
        for stream in ["res", "err"]:
            if not isinstance(difference, dict) or not texts(difference.get(stream)):
                return "missing or invalid %s in log difference %s" % (stream, pair)
    return None


def read_result(path):
    """The result of a run in the file [path], and what is damaged in it:
    one of the two is None."""
    try:
        with open(path) as f:
            result = json.load(f)
    except (OSError, ValueError) as error:
        return None, "the file is not read: %s" % type(error).__name__
    damaged = result_damage(result)
    return (None, damaged) if damaged else (result, None)


def observer_state(o):
    """The outcome of an observation: done, or the failure that stopped it,
    that its exit status shows, or that left its records damaged or
    incomplete."""
    if "failure" in o:
        return "failure: " + o["failure"]
    status = o["status"]
    phase = phase_of(o)
    # A record of an earlier version of this script does not tell whether
    # the observer was loaded.
    if not o.get("loaded", True):
        return "failure: the observer is not loaded (exit %s): it wrote no summary" % status
    expected, why = o["expected"]
    if status not in expected:
        return "failure: exit %s in phase %s, where %s is expected: %s" % (
            status,
            phase,
            " or ".join(str(s) for s in expected),
            why,
        )
    if records(o, "error"):
        return "failure: " + records(o, "error")[0][0]
    if phase != "done":
        return "failure: stopped (exit %s) in phase %s" % (status, phase)
    if records(o, "no result"):
        return "failure: the analysis with -eva-hit-log has no result"
    damaged = damage(o)
    if damaged:
        return "failure: damaged records: " + damaged
    t = first(o, "trap")
    if t[2] != "matched" or t[0] != t[1]:
        return "failure: incomplete record of the trap"
    return "done" if status == 0 else "done, exit %s" % status


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for row in rows:
        lines.append("| " + " | ".join(str(c) for c in row) + " |")
    return "\n".join(lines)


def provenance():
    """The revision of the checkout and its changes to tracked files."""
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    changes = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    return {"revision": head, "changes": changes}


def describe_provenance(p):
    if not p:
        return "unknown (no record)"
    return "`%s`%s" % (
        p["revision"],
        (
            " with changes to %d tracked files" % len(p["changes"])
            if p["changes"]
            else ", tree clean"
        ),
    )


def total(observed, kind, run_kind, width):
    """The sums of the [width] numbers of the records [kind] of the run
    [run_kind], over observations whose records are checked. The verdicts of
    an earlier version of the observer have no count of unresolved answers,
    which it did not tell apart: that count is not known, and adds
    nothing."""
    totals = [0] * width
    for o in observed:
        for rec in records(o, kind):
            if rec[0] == run_kind:
                fields = rec[1:]
                if len(fields) < width and kind == "verdicts" and not has_format(o):
                    fields = fields + ["0"] * (width - len(fields))
                totals = [a + int(b) for a, b in zip(totals, fields, strict=True)]
    return totals


def write_summary(outdir, runs, results, elapsed, unread=()):
    """Writes the summary of the results [results] of the runs [runs].
    [unread] are the runs whose result file is damaged, with the damage."""
    by_name = {r["name"]: r for r in results}
    unread = dict(unread)
    lines = []
    emit = lines.append
    emit("# Eva tests under -eva-hit-log\n")
    revisions = collections.Counter(describe_provenance(r.get("provenance")) for r in results)
    if len(revisions) <= 1:
        emit("Revision of the runs: %s.\n" % (next(iter(revisions)) if revisions else "no run"))
    else:
        emit("**The runs are of %d different revisions:**\n" % len(revisions))
        emit(table(["Revision", "Runs"], sorted(revisions.items())))
        emit("")
    now = describe_provenance(provenance())
    if revisions and now not in revisions:
        emit("This summary is written at revision %s.\n" % now)
    invocations = collections.Counter(
        (r.get("provenance") or {}).get("invocation", "not recorded") for r in results
    )
    emit(
        "Invocations of the script that made the runs, each with its own "
        "directory of outputs: %s.\n"
        % (", ".join("`%s` (%d runs)" % i for i in sorted(invocations.items())) or "none")
    )
    if elapsed is not None:
        emit("Wall-clock time of the run: %.0f s.\n" % elapsed)
    # Inventory.
    inventory = []
    for run in runs:
        result = by_name.get(run["name"], {})
        reason = run.get("not_run") or result.get("not_run")
        if reason is None and run["name"] in unread:
            reason = "FAILURE: the result of the run is damaged"
        if reason is None and not result:
            reason = "other: not executed by this invocation"
        inventory.append((run["name"], reason))
    executed = [n for n, r in inventory if r is None]
    emit("## Inventory\n")
    emit(
        "%d runs in the default configuration of suites %s: %d executed, "
        "%d not run.\n"
        % (
            len(inventory),
            ", ".join(sorted({r["suite"] for r in runs})),
            len(executed),
            len(inventory) - len(executed),
        )
    )
    reasons = collections.Counter(r for _, r in inventory if r is not None)
    emit(table(["Reason not run", "Runs"], sorted(reasons.items())))
    emit("")
    per_suite = collections.defaultdict(lambda: [0, 0])
    for name, reason in inventory:
        per_suite[name.split("/")[0]][0 if reason is None else 1] += 1
    emit(
        table(
            ["Suite", "Executed", "Not run"],
            [(s, e, n) for s, (e, n) in sorted(per_suite.items())],
        )
    )
    emit("")
    with open(os.path.join(outdir, "inventory.tsv"), "w") as f:
        for name, reason in inventory:
            f.write("%s\t%s\n" % (name, "executed" if reason is None else reason))
    emit("Every run, with its reason: `inventory.tsv`.\n")
    done = [by_name[n] for n in executed]
    # Stages.
    emit("## Stages\n")
    stages = [(r, s) for r in done for s in stages_of(r)]
    all_obs = [o for r in done for o in observations(r)]
    later = [o for o in all_obs if not o["first"]]
    emit(
        "%d stages in the %d executed runs: %d observed, of which %d are the "
        "first observed stage of their run and %d a later stage; %d not "
        "observed.\n"
        % (
            len(stages),
            len(done),
            len(all_obs),
            len(all_obs) - len(later),
            len(later),
            len([1 for _, s in stages if not s["observed"]]),
        )
    )
    not_observed = collections.Counter(s["reason"] for _, s in stages if not s["observed"])
    emit(table(["Reason a stage is not observed", "Stages"], sorted(not_observed.items())))
    emit("")
    emit("Observed stages that are not the first observed stage of their run:\n")
    emit(table(["Stage"], [[o["name"]] for o in later]))
    emit("")
    late_first = sorted(o["name"] for o in all_obs if o["first"] and o["stage"] > 1)
    emit(
        "Runs whose first observed stage is not the first stage of the "
        "command: %s.\n" % (", ".join(late_first) or "none")
    )
    options = collections.Counter(
        option for _, s in stages if s["observed"] for option in s.get("not_observed", [])
    )
    emit(
        "Options of the observed stages whose effects after the analysis are "
        "not observed (the observer removes them), by number of stages:\n"
    )
    emit(table(["Option", "Stages"], sorted(options.items())))
    emit("")
    with open(os.path.join(outdir, "stages.tsv"), "w") as f:
        for r, s in stages:
            f.write(
                "%s\t%d\t%s\t%s\n"
                % (
                    r["name"],
                    s["stage"],
                    "observed" if s["observed"] else s["reason"],
                    " ".join(s.get("not_observed", [])),
                )
            )
    emit("Every stage, with its reason or the options not observed: `stages.tsv`.\n")
    conditional = [o for o in all_obs if o["stage"] > 1]
    emit(
        "**The reference of a stage that is not the first stage of its command "
        "is conditional on the stages before it.** The observer of such a stage "
        "runs the stages before it with -eva-hit-log, then copies the project "
        "that they leave and analyses the copy without memexec: this reference "
        "is not the whole command run without memexec. An answer of such a "
        "stage that is equal to its reference is equal given that prefix: a "
        "difference that an earlier stage run with the recording leaves in the "
        "project, as in its annotations, its statuses or the state of another "
        "plug-in, is in the reference as well, and the comparison does not see "
        "it. This concerns %d observed stages: the %d later stages listed above, "
        "and the first observed stage of the %d runs just named, whose earlier "
        "stages start no analysis. The outputs of the whole commands, run "
        "without memexec and with -eva-hit-log, are compared apart, in "
        '"Outputs of the test commands".\n'
        % (len(conditional), len(later), len(conditional) - len(later))
    )
    # Observer.
    emit("## Observer\n")
    states = collections.Counter(observer_state(o) for o in all_obs)
    emit(table(["Outcome of the observer", "Stages"], sorted(states.items())))
    emit("")
    failures = [o for o in all_obs if observer_state(o).startswith("failure")]
    observed = [o for o in all_obs if not observer_state(o).startswith("failure")]
    emit(
        "**Failures: %d** observed stages, counted apart from the totals "
        "below, which are those of the %d other observed stages.\n" % (len(failures), len(observed))
    )
    emit(table(["Stage", "Outcome"], [[o["name"], observer_state(o)] for o in failures]))
    emit("")
    emit(
        "**Runs whose result is damaged: %d.** The file of the result of the run "
        "cannot be read: nothing of it is counted.\n" % len(unread)
    )
    emit(table(["Run", "Damage"], sorted(unread.items())))
    emit("")
    listing_failures = [(r["name"], r["stages failure"]) for r in done if "stages failure" in r]
    emit(
        "**Runs whose stage listing failed: %d.** Valid observations from these "
        "runs are kept and counted.\n" % len(listing_failures)
    )
    emit(table(["Run", "Failure"], listing_failures))
    emit("")
    earlier = [o for o in observed if not has_format(o)]
    if earlier:
        emit(
            "**%d of these %d stages have records of an earlier version of the "
            "observer**, without a record of their format: they are checked and "
            "read as that version wrote them. Its comparison is not that of this "
            "version: it does not keep the strength of the allocated blocks, it "
            "compares the run with memexec through the run with -eva-hit-log, "
            "and its first versions do not count the unresolved answers, shown "
            "as 0.\n" % (len(earlier), len(observed))
        )
    stopped = sorted(o["name"] for o in observed if records(o, "stopped"))
    emit(
        "Observed stages where an analysis stops, as by an option or an "
        "error of the program: %s.\n" % (", ".join(stopped) or "none")
    )
    emit("### Calls\n")
    calls = [0] * 5
    hit_runs = 0
    for o in observed:
        c = first(o, "calls")
        if c:
            calls = [a + int(b) for a, b in zip(calls, c)]
            hit_runs += int(c[1]) > 0
    emit(
        table(
            ["Analysed", "Hits", "Specification", "Builtin", "Below a hit"],
            [calls],
        )
    )
    emit("\nStages with at least one hit: %d of %d.\n" % (hit_runs, len(observed)))
    heap = [0] * 4
    heap_runs = 0
    lost_rows = []
    for o in observed:
        h = first(o, "heap calls")
        if h:
            heap = [a + int(b) for a, b in zip(heap, h)]
            heap_runs += int(h[0]) > 0
            if int(h[1]) or int(h[2]):
                lost_rows.append([o["name"], h[1], h[2]])
    emit(
        "Heap calls, which memexec does not store, those of them whose "
        "cache entries hold full states, which answer the requests at the "
        "points of their bodies instead of the rule, and the calls analysed "
        "by their body that memexec would have answered from the entry of a "
        "heap call, as Eva counts them in its statistics hit-log-heap-calls, "
        "hit-log-full-states, hit-log-lost-hits and hit-log-lost-hits-below. "
        "The last column counts those made during the analysis of a call "
        "that would have been a hit: without the change, they would have "
        "been below a hit.\n"
    )
    emit(
        table(
            ["Heap calls", "Full states", "Hits not made", "During one"],
            [[heap[0], heap[3], heap[1], heap[2]]],
        )
    )
    emit("\nStages with at least one heap call: %d of %d.\n" % (heap_runs, len(observed)))
    emit("Stages with hits not made:\n")
    emit(table(["Stage", "Hits not made", "During one"], lost_rows))
    emit("")
    rows = [
        [o["name"]] + rec
        for o in observed
        for rec in records(o, "below rebuilt")
        if rec[0] != "crossing"
    ]
    emit(
        "Calls below a hit that the observer rebuilds and Eva does not list, " "or the converse:\n"
    )
    emit(table(["Stage", "Which", "Callstack"], rows))
    emit("")
    crossing = collections.Counter(
        o["name"] for o in observed for rec in records(o, "below rebuilt") if rec[0] == "crossing"
    )
    emit("Calls below a hit that cross a recursion, per stage:\n")
    emit(table(["Stage", "Calls"], sorted(crossing.items())))
    emit("")
    emit("### Requests made with -eva-hit-log, per kind\n")
    requests = collections.Counter()
    for o in observed:
        for point, what, n in records(o, "requests"):
            requests[(point, what)] += int(n)
    points = sorted({p for p, _ in requests})
    whats = sorted({w for _, w in requests})
    emit(
        table(
            ["Point"] + whats,
            [[p] + [requests[(p, w)] for w in whats] for p in points],
        )
    )
    emit("\nTotal: %d requests.\n" % sum(requests.values()))
    emit("### Answers against the run without memexec\n")
    rows = []
    for run_kind in ["recording", "memexec"]:
        for group, members in [
            ("all observed stages", observed),
            ("first observed stage of each run", [o for o in observed if o["first"]]),
            ("later stages", [o for o in observed if not o["first"]]),
        ]:
            rows.append([run_kind, group] + total(members, "verdicts", run_kind, len(VERDICTS)))
    emit(table(["Run", "Stages"] + VERDICTS, rows))
    emit("")
    emit(
        "The answers of a stage that is not the first stage of its command are "
        "compared with a reference that is conditional on the stages before it: "
        'see "Stages".\n'
    )
    not_compared = sum(int(rec[1]) for o in observed for rec in records(o, "not compared"))
    emit(
        "The run with memexec, without recording, is compared with the "
        "reference between these two runs only: with the created bases of the "
        "two matched to each other, and on the callstacks that one of the two "
        "lists. Answers with -eva-hit-log on a callstack that neither of the two "
        "lists, where the run with memexec is not compared: %d.\n" % not_compared
    )
    answers = [(o["name"], answer(a)) for o in observed for a in records(o, "answer")]
    cases = collections.Counter(
        (a["case"] or "?")
        + (" (as in the reference)" if a["origin"] == "as in the reference" else "")
        for _, a in answers
        if a["recording"] == "unavailable"
    )
    emit("Unavailable answers with -eva-hit-log, per case of the closed list:\n")
    emit(table(["Case", "Answers"], sorted(cases.items())))
    emit("")
    # The comparison of a record of created bases: the run with -eva-hit-log
    # against the run named, or the run with memexec against the reference.
    comparisons = {
        "without memexec": "-eva-hit-log against the reference",
        "with memexec": "-eva-hit-log against memexec",
        "memexec against reference": "memexec against the reference",
    }

    def comparison(rec):
        return [comparisons.get(rec[0], rec[0])] + rec[1:]

    rows = [
        [o["name"]] + (comparison(rec) + ["match undecided"])[:3]
        for o in observed
        for rec in records(o, "unresolved")
    ]
    emit(
        "Created bases whose match between two runs is unresolved (the answers "
        "that hold them are counted as unresolved in that comparison): the match "
        "is not decided, or the base is one block in the run compared and a "
        "summary of several blocks in the run it is compared with.\n"
    )
    emit(table(["Stage", "Comparison", "Base", "Reason"], rows))
    emit("")
    rows = [[o["name"]] + comparison(rec) for o in observed for rec in records(o, "summarised")]
    emit(
        "Created bases that summarise several blocks, matched to one block of "
        "the run they are compared with. An answer that holds one is compared "
        "in one direction only: it covers the answer of that run, or OMITS it, "
        "and is never equal to it nor more precise.\n"
    )
    emit(table(["Stage", "Comparison", "Summary of several blocks", "One block"], rows))
    emit("")
    unresolved = total(observed, "verdicts", "recording", len(VERDICTS))[-1]
    emit(
        "**Unresolved answers with -eva-hit-log: %d.** Each one fails the criterion "
        "that no state of the run with -eva-hit-log omits a value of the reference, "
        "unless it is explained: the comparison cannot tell whether it omits one.\n" % unresolved
    )
    emit(
        "Unresolved answers with memexec, without recording: %d.\n"
        % total(observed, "verdicts", "memexec", len(VERDICTS))[-1]
    )
    emit("Answers that are not equal, per stage, function and verdict ")
    emit("(recording, then memexec without recording, against the reference):\n")
    groups = collections.Counter(
        (
            n,
            a["function"] or "-",
            a["recording"],
            a["memexec"],
            a["origin"] or "-",
            a["case"],
        )
        for n, a in answers
    )
    emit(
        table(
            ["Stage", "Function", "Recording", "Memexec", "Origin", "Case", "Answers"],
            [list(k) + [v] for k, v in sorted(groups.items())],
        )
    )
    emit("")
    emit("### Callstacks listed\n")
    rows = []
    for o in observed:
        cs = first(o, "callstacks")
        cf = first(o, "callstacks filtered")
        if cs and (cs[0] != "0" or (cf and cf[0] != "0")):
            rows.append([o["name"], cs[0], cf[0] if cf else "?", cs[1]])
    emit(
        "Stages whose callstacks, listed with -eva-hit-log, are not those of "
        "the reference at some points:\n"
    )
    emit(table(["Stage", "Points", "Points, filtered", "Of"], rows))
    emit("")
    emit("### Legacy-read trap\n")
    made = reported = reads = 0
    for o in observed:
        t = first(o, "trap")
        made += int(t[0])
        reported += int(t[1])
        reads += int(t[3])
    emit(
        "Requests made by the observer: %d; reported by the trap: %d; reads of "
        "the legacy store: %d. Each of these stages has a complete record of "
        "the trap: every request reported once, with its description; a stage "
        "without one is a failure above.\n" % (made, reported, reads)
    )
    emit("### Passes after the iteration\n")
    rows = []
    for run_kind in ["memexec", "recording"]:
        rows.append([run_kind] + total(observed, "passes", run_kind, 3))
    emit(table(["Run", "Requests", "Reads in them", "Reads outside"], rows))
    emit("")
    passes = collections.Counter()
    for o in observed:
        for name, n in records(o, "pass"):
            passes[name] += int(n)
    emit(table(["Pass, with -eva-hit-log", "Requests"], sorted(passes.items())))
    below = sum(int(x[0]) for o in observed for x in records(o, "below requests"))
    emit("\nRequests of the passes on a callstack below a hit: %d.\n" % below)
    bad = [
        o["name"]
        for o in observed
        for rec in records(o, "passes")
        if rec[0] == "recording" and (rec[2] != "0" or rec[3] != "0")
    ]
    emit(
        "Stages with a read of the legacy store after the iteration: %s.\n"
        % (", ".join(bad) or "none")
    )
    emit("### Outputs of the passes\n")
    rows = [[o["name"]] + rec for o in observed for rec in records(o, "status")]
    emit("Statuses that differ from the reference:\n")
    emit(
        table(
            ["Stage", "With", "Property", "Status", "Reference", "Verdict", "Origin"],
            rows,
        )
    )
    emit("")
    rows = [[o["name"]] + rec for o in observed for rec in records(o, "alarm")]
    emit("Alarms that differ from the reference:\n")
    emit(table(["Stage", "With", "Difference", "Alarm"], rows))
    emit("")
    rows = []
    for o in observed:
        stats = {rec[0]: rec[1:] for rec in records(o, "statistics")}
        if len({tuple(v) for v in stats.values()}) > 1:
            rows.append(
                [o["name"]]
                + [" ".join(stats.get(k, ["?"])) for k in ["reference", "memexec", "recording"]]
            )
    emit("Summaries (statement coverage, function coverage, alarms) that differ:\n")
    emit(table(["Stage", "Reference", "Memexec", "Recording"], rows))
    emit("")
    count = collections.Counter()
    for o in observed:
        for run_kind, n in records(o, "unreachable statements"):
            count[run_kind] += int(n)
    emit(
        "Statements unreachable for the passes (the state before them is "
        "bottom): %s.\n"
        % ", ".join("%d %s" % (count[k], k) for k in ["reference", "memexec", "recording"])
    )
    emit(
        "Statements unreachable in one run and reachable in the reference, or "
        "the converse, compared one by one. The two comparisons are separate, "
        "each against the reference:\n"
    )
    for run_kind, title in [
        ("recording", "with -eva-hit-log"),
        ("memexec", "with memexec, without recording"),
    ]:
        rows = [
            [o["name"]] + rec[1:]
            for o in observed
            for rec in records(o, "unreachable")
            if rec[0] == run_kind
        ]
        directions = collections.Counter(row[1] for row in rows)
        emit(
            "- %s: %d statements differ, %d unreachable only in the reference and "
            "%d only in this run.\n"
            % (
                title,
                len(rows),
                directions["only in the reference"],
                directions["only in this run"],
            )
        )
        emit(table(["Stage", "Unreachable", "Statement", "Case"], rows))
        emit("")
    rows = []
    for o in observed:
        for rec in records(o, "messages"):
            if rec[1] != "equal":
                rows.append([o["name"]] + rec)
    emit("Messages of the passes that differ from the reference:\n")
    emit(table(["Stage", "With", "Comparison"], rows))
    emit("")
    emit("## Outputs of the test commands\n")
    rows = []
    for r in done:
        st = [str(r.get(v, {}).get("status")) for v in ["reference", "memexec", "hitlog"]]
        if st != ["0", "0", "0"]:
            rows.append([r["name"]] + st)
    emit("Runs whose commands do not all exit with 0:\n")
    emit(table(["Run", "Reference", "Memexec", "Hitlog"], rows))
    emit("")
    mismatch = [r["name"] for r in done if not r.get("memexec_matches_oracle")]
    emit(
        "Runs whose output without recording differs from the tracked oracle: "
        "%s.\n" % (", ".join(mismatch) or "none")
    )
    for pair in ["memexec -> hitlog", "reference -> memexec", "reference -> hitlog"]:
        rows = []
        for r in done:
            d = r.get("log_diffs", {}).get(pair)
            if d and (d["res"] or d["err"]):
                count = sum(
                    1
                    for line in d["res"] + d["err"]
                    if line[:1] in "+-" and line[:3] not in ("+++", "---")
                )
                rows.append([r["name"], count])
        emit("Runs whose output differs, %s (changed lines):\n" % pair)
        emit(table(["Run", "Lines"], rows))
        emit("")
    with open(os.path.join(outdir, "log-diffs.txt"), "w") as f:
        for r in done:
            for pair, d in r.get("log_diffs", {}).items():
                if d["res"] or d["err"]:
                    f.write("=== %s: %s\n" % (r["name"], pair))
                    for line in d["res"]:
                        f.write("res " + line + "\n")
                    for line in d["err"]:
                        f.write("err " + line + "\n")
    emit("The differences themselves: `log-diffs.txt`.\n")
    with open(os.path.join(outdir, "summary.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


# ----- Main ---------------------------------------------------------------


def selects(patterns, run):
    return not patterns or any(p in run["name"] for p in patterns)


def check_free_space(directories):
    """Stops when one of [directories] is on a volume with less than
    FC_MIN_FREE_GB GiB free: a full disk makes runs fail in ways that read
    as failures of the observer."""
    minimum = float(os.environ.get("FC_MIN_FREE_GB", "5"))
    for directory in directories:
        free = shutil.disk_usage(directory).free / 2**30
        if free < minimum:
            sys.exit(
                "only %.1f GiB free on the volume of %s (FC_MIN_FREE_GB=%g)"
                % (free, directory, minimum)
            )


def main():
    parser = argparse.ArgumentParser(description="Eva tests under -eva-hit-log")
    parser.add_argument("-j", type=int, default=8, dest="jobs")
    parser.add_argument("-o", dest="outdir")
    parser.add_argument("-w", dest="workdir")
    parser.add_argument("-k", dest="patterns", action="append", default=[])
    parser.add_argument("--report", action="store_true")
    options = parser.parse_args()
    if not os.path.isfile(os.path.join(TESTS, "ptests_config")):
        sys.exit("run this script from the root of the checkout")
    outdir = options.outdir or tempfile.mkdtemp(prefix="hit-log-suite-")
    outdir = os.path.abspath(outdir)
    if outdir.startswith(os.path.abspath(".") + os.sep):
        sys.exit("the output directory must not be in the checkout")
    os.makedirs(os.path.join(outdir, "runs"), exist_ok=True)
    start = time.monotonic()
    if not options.report:
        # The directory of the outputs of this invocation: a new one, so
        # that no command finds a file of an earlier invocation.
        workdir = os.path.abspath(options.workdir or os.path.join(outdir, "work"))
        if (workdir + os.sep).startswith(os.path.abspath(".") + os.sep):
            sys.exit("the directory of the outputs must not be in the checkout")
        os.makedirs(workdir, exist_ok=True)
        check_free_space([".", outdir, workdir])
        work_root = tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=workdir)
        os.symlink(os.path.abspath(SHARE), os.path.join(work_root, "share"))
        source = dict(provenance(), invocation=os.path.basename(work_root))
        env = without_observer_variables(build(options.jobs))
        print("Outputs of the commands: " + work_root, flush=True)
    runs = [run for suite in default_suites() for run in runs_of_suite(suite)]
    saves = saving_runs(runs)
    for run in runs:
        classify(run, saves)
    selected = [run for run in runs if "args" in run and selects(options.patterns, run)]
    results = []
    unread = []
    if not options.report:
        observer = os.path.abspath(OBSERVER)
        print("%d runs, %d to execute" % (len(runs), len(selected)), flush=True)
        with concurrent.futures.ThreadPoolExecutor(options.jobs) as pool:
            futures = {
                pool.submit(run_one, run, work_root, env, observer, source): run for run in selected
            }
            for n, future in enumerate(concurrent.futures.as_completed(futures), 1):
                result = future.result()
                # The summary is written from the results of this
                # invocation, not from the files of an earlier one.
                results.append(result)
                path = os.path.join(outdir, "runs", result["name"] + ".json")
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w") as f:
                    json.dump(result, f)
                print(
                    "[%d/%d] %s: %s"
                    % (
                        n,
                        len(selected),
                        result["name"],
                        result.get("not_run")
                        or result.get("stages failure")
                        or ", ".join(
                            "stage %d %s" % (o["stage"], observer_state(o))
                            for o in observations(result)
                        )
                        or "no stage observed",
                    ),
                    flush=True,
                )
        elapsed = time.monotonic() - start
        with open(os.path.join(outdir, "time"), "w") as f:
            f.write("%.0f\n" % elapsed)
    else:
        elapsed = None
        t = read(os.path.join(outdir, "time"))
        if t:
            elapsed = float(t)
        for run in selected:
            path = os.path.join(outdir, "runs", run["name"] + ".json")
            if os.path.isfile(path):
                result, damaged = read_result(path)
                if damaged:
                    unread.append((run["name"], damaged))
                else:
                    results.append(result)
    runs = [r for r in runs if selects(options.patterns, r)]
    write_summary(outdir, runs, results, elapsed, unread)
    print("Summary: " + os.path.join(outdir, "summary.md"))


if __name__ == "__main__":
    main()
