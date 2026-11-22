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
# Each test run is a command of the ptests rules of plugins/eva/tests. A run
# that fits the configuration of the recording (cvalue domain alone, memexec
# on, no option whose limits are accepted) is executed four times, each in
# its own directory:
#   - hitlog: the command with -eva-hit-log;
#   - reference: the command with -eva-no-memexec, stopped after two minutes;
#   - memexec: the command as it is, whose output is the oracle of the test;
#   - observer: the first analysis of the command, without its option -eva
#     and the options of other plug-ins that start an analysis or print, with
#     the observer of plugins/eva/tests/hit_log/hit_log_observer.ml and
#     -eva-hit-log. The observer analyses copies of the project without
#     memexec and with memexec, then the project with -eva-hit-log, asks each
#     of them for the states at every point, and writes a summary of the
#     comparison (environment variable HIT_LOG_OBSERVER_SUMMARY).
# The other runs are listed as not run, with the reason.
#
# Usage: dev/hit-log-suite.py [-j JOBS] [-o OUTDIR] [-k PATTERN] [--report]
#   -j JOBS     number of runs in parallel (default 8)
#   -o OUTDIR   directory of the work files and of the summary; it must not be
#               in the checkout (default: a new temporary directory)
#   -k PATTERN  only the runs whose name (suite/test.number) contains PATTERN;
#               the option can be repeated
#   --report    only write the summary again, from the results in OUTDIR
#
# Run it from the root of the checkout, with the opam switch active. It builds
# Frama-C, regenerates the ptests rules of Eva and builds the observer first.
# The summary is OUTDIR/summary.md; the results of each run are in
# OUTDIR/runs, and its outputs in OUTDIR/work.

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
    result = []
    skip = False
    for t in tokens:
        if skip:
            skip = False
        elif t in (">", "2>", "1>"):
            skip = True
        else:
            result.append(t)
    return result


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


def observer_args(args, observer):
    """The arguments of the observer, or the reason why it cannot run: the
    stages up to the first one that starts an analysis, without the options
    that start an analysis or print, with the observer loaded."""
    stages, separators = split_stages(args)
    first = next(
        (i for i, s in enumerate(stages) if any(starts_analysis(t) for t in s)),
        None,
    )
    if first is None:
        return None, "no stage starts an analysis"
    if any(sep[0] != "-then" for sep in separators[:first]):
        return None, "the first analysis is after " + separators[first - 1][0]
    merged = [t for s in stages[: first + 1] for t in s]
    result = []
    i = 0
    while i < len(merged):
        t = merged[i]
        name = option_name(t)
        if name in ANALYSIS_WITH_ARGUMENT and "=" not in t:
            i += 2
            continue
        if name in ANALYSIS_FLAGS or name in ANALYSIS_WITH_ARGUMENT:
            i += 1
            continue
        if name in PRINTING_FLAGS:
            i += 1
            continue
        result.append(t)
        if t.startswith("-load-plugin"):
            result.append("-load-module=" + observer)
        i += 1
    return result + ["-eva-hit-log"], None


def static_reason(tokens):
    """The reason why a run is not executed, from its options."""
    names = [option_name(t) for t in tokens]
    if "-load" in names:
        return "other: the test loads a saved project"
    if "-load-module" in names:
        return "other: the test loads its own OCaml module"
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
        runs.append(
            {
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
        )
    return runs


def classify(run):
    """Fills the arguments of the commands of a run, or the reason why it is
    not run."""
    if run["suite"] == OBSERVER_SUITE:
        run["not_run"] = (
            "other: fixture of the observer, run with the observer by its "
            "own ptests rules (@plugins/eva/tests/hit_log/ptests_config)"
        )
        return
    if run["kind"] != "TEST":
        run["not_run"] = "other: EXECNOW command"
        return
    cmd = run["cmd"]
    if not cmd.startswith("frama-c ") or re.search(r"[|;&{}]", cmd):
        run["not_run"] = "other: not a single frama-c command"
        return
    tokens = strip_redirections(shlex.split(cmd))[1:]
    expanded = expand(run["suite"], tokens)
    reason = static_reason(expanded)
    if reason:
        run["not_run"] = reason
        return
    run["args"] = tokens
    run["expanded"] = expanded


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
    """Links into [directory] the files of the suite that the run uses."""
    suite_dir = os.path.abspath(os.path.join(TESTS, run["suite"]))
    os.makedirs(directory, exist_ok=True)
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


def run_one(run, outdir, env, observer):
    work = os.path.join(outdir, "work", run["name"])
    result = {"name": run["name"]}
    variants = {
        "hitlog": add_to_each_stage(run["args"], ["-eva-hit-log"]),
        "reference": add_to_each_stage(run["args"], ["-eva-no-memexec"]),
        "memexec": run["args"],
    }
    obs_args, obs_reason = observer_args(run["expanded"], observer)
    commands = {}
    for variant in ["hitlog", "reference", "memexec", "observer"]:
        if variant == "observer":
            if obs_args is None:
                result["observer_not_run"] = obs_reason
                break
            args = obs_args
        else:
            args = variants[variant]
        directory = os.path.join(work, variant)
        prepare_directory(run, directory)
        argv = [env["FRAMA_C"]] + args
        commands[variant] = shlex.join(argv)
        variant_env = env
        if variant == "observer":
            variant_env = dict(env)
            variant_env["HIT_LOG_OBSERVER_SUMMARY"] = os.path.join(directory, "summary")
        timeout = REFERENCE_TIMEOUT if variant == "reference" else TIMEOUT
        result[variant] = execute(run, argv, directory, variant_env, timeout)
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
    result["commands"] = commands
    if "not_run" in result:
        return result
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
    if "observer" in result:
        result["summary"] = parse_summary(os.path.join(work, "observer", "summary"))
        statuses = {result[v]["status"] for v in ["hitlog", "reference", "memexec"]}
        observer = result["observer"]["status"]
        if phase_of(result) == "start" and statuses == {observer} and observer != 0:
            result["not_run"] = (
                "other: every command stops before the analysis (exit %s)" % observer
            )
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


# ----- Summary ------------------------------------------------------------

VERDICTS = ["equal", "covers", "more precise", "OMITS", "unavailable"]


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


def observer_state(result):
    """The outcome of the observer: done, or what stopped it."""
    if "observer" not in result:
        return "not run: " + result.get("observer_not_run", "?")
    status = result["observer"]["status"]
    phase = phase_of(result)
    if records(result, "error"):
        return "error: " + records(result, "error")[0][0]
    if phase == "done" and status == 0:
        return "done"
    if phase == "done":
        return "done, exit %s" % status
    return "stopped (exit %s) in phase %s" % (status, phase)


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for row in rows:
        lines.append("| " + " | ".join(str(c) for c in row) + " |")
    return "\n".join(lines)


def write_summary(outdir, runs, results, elapsed):
    by_name = {r["name"]: r for r in results}
    lines = []
    emit = lines.append
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    dirty = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    emit("# Eva tests under -eva-hit-log\n")
    emit("Revision: `%s`%s.\n" % (head, " with uncommitted changes" if dirty else ""))
    if elapsed is not None:
        emit("Wall-clock time of the run: %.0f s.\n" % elapsed)
    # Inventory.
    inventory = []
    for run in runs:
        result = by_name.get(run["name"], {})
        reason = run.get("not_run") or result.get("not_run")
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
    # Observer.
    emit("## Observer\n")
    states = collections.Counter(observer_state(r) for r in done)
    emit(table(["Outcome of the observer", "Runs"], sorted(states.items())))
    emit("")
    observed = [r for r in done if observer_state(r).startswith("done")]
    emit("### Calls\n")
    calls = [0] * 5
    hit_runs = 0
    for r in observed:
        c = first(r, "calls")
        if c:
            calls = [a + int(b) for a, b in zip(calls, c)]
            hit_runs += int(c[1]) > 0
    emit(
        table(
            ["Analysed", "Hits", "Specification", "Builtin", "Below a hit"],
            [calls],
        )
    )
    emit("\nRuns with at least one hit: %d of %d.\n" % (hit_runs, len(observed)))
    emit("### Requests made with -eva-hit-log, per kind\n")
    requests = collections.Counter()
    for r in observed:
        for point, what, n in records(r, "requests"):
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
        totals = [0] * 5
        for r in observed:
            for rec in records(r, "verdicts"):
                if rec[0] == run_kind:
                    totals = [a + int(b) for a, b in zip(totals, rec[1:])]
        rows.append([run_kind] + totals)
    emit(table(["Run"] + VERDICTS, rows))
    emit("")
    answers = [(r["name"], answer(a)) for r in observed for a in records(r, "answer")]
    cases = collections.Counter(
        (a["case"] or "?")
        + (" (as in the reference)" if a["origin"] == "as in the reference" else "")
        for _, a in answers
        if a["recording"] == "unavailable"
    )
    emit("Unavailable answers with -eva-hit-log, per case of the closed list:\n")
    emit(table(["Case", "Answers"], sorted(cases.items())))
    emit("")
    emit("Answers that are not equal, per run, function and verdict ")
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
            ["Run", "Function", "Recording", "Memexec", "Origin", "Case", "Answers"],
            [list(k) + [v] for k, v in sorted(groups.items())],
        )
    )
    emit("")
    emit("### Callstacks listed\n")
    rows = []
    for r in observed:
        cs = first(r, "callstacks")
        cf = first(r, "callstacks filtered")
        if cs and (cs[0] != "0" or (cf and cf[0] != "0")):
            rows.append([r["name"], cs[0], cf[0] if cf else "?", cs[1]])
    emit(
        "Runs whose callstacks, listed with -eva-hit-log, are not those of the "
        "reference at some points:\n"
    )
    emit(table(["Run", "Points", "Points, filtered", "Of"], rows))
    emit("")
    emit("### Legacy-read trap\n")
    made = reported = reads = 0
    unmatched = []
    for r in observed:
        t = first(r, "trap")
        if t:
            made += int(t[0])
            reported += int(t[1])
            reads += int(t[3])
            if t[2] != "matched" or t[0] != t[1]:
                unmatched.append(r["name"])
    emit(
        "Requests made by the observer: %d; reported by the trap: %d; reads of "
        "the legacy store: %d. Runs where a request is not reported once with "
        "its description: %s.\n" % (made, reported, reads, ", ".join(unmatched) or "none")
    )
    emit("### Passes after the iteration\n")
    rows = []
    for run_kind in ["memexec", "recording"]:
        totals = [0, 0, 0]
        for r in observed:
            for rec in records(r, "passes"):
                if rec[0] == run_kind:
                    totals = [a + int(b) for a, b in zip(totals, rec[1:])]
        rows.append([run_kind] + totals)
    emit(table(["Run", "Requests", "Reads in them", "Reads outside"], rows))
    emit("")
    passes = collections.Counter()
    for r in observed:
        for name, n in records(r, "pass"):
            passes[name] += int(n)
    emit(table(["Pass, with -eva-hit-log", "Requests"], sorted(passes.items())))
    below = sum(int(x[0]) for r in observed for x in records(r, "below requests"))
    emit("\nRequests of the passes on a callstack below a hit: %d.\n" % below)
    bad = [
        r["name"]
        for r in observed
        for rec in records(r, "passes")
        if rec[0] == "recording" and (rec[2] != "0" or rec[3] != "0")
    ]
    emit(
        "Runs with a read of the legacy store after the iteration: %s.\n"
        % (", ".join(bad) or "none")
    )
    emit("### Outputs of the passes\n")
    rows = []
    for r in observed:
        for rec in records(r, "status"):
            rows.append([r["name"]] + rec)
    emit("Statuses that differ from the reference:\n")
    emit(
        table(
            ["Run", "With", "Property", "Status", "Reference", "Verdict", "Origin"],
            rows,
        )
    )
    emit("")
    rows = []
    for r in observed:
        for rec in records(r, "alarm"):
            rows.append([r["name"]] + rec)
    emit("Alarms that differ from the reference:\n")
    emit(table(["Run", "With", "Difference", "Alarm"], rows))
    emit("")
    rows = []
    for r in observed:
        stats = {rec[0]: rec[1:] for rec in records(r, "statistics")}
        if len({tuple(v) for v in stats.values()}) > 1:
            rows.append(
                [r["name"]]
                + [" ".join(stats.get(k, ["?"])) for k in ["reference", "memexec", "recording"]]
            )
    emit("Summaries (statement coverage, function coverage, alarms) that differ:\n")
    emit(table(["Run", "Reference", "Memexec", "Recording"], rows))
    emit("")
    rows = []
    for r in observed:
        for rec in records(r, "messages"):
            if rec[1] != "equal":
                rows.append([r["name"]] + rec)
    emit("Messages of the passes that differ from the reference:\n")
    emit(table(["Run", "With", "Comparison"], rows))
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


def main():
    parser = argparse.ArgumentParser(description="Eva tests under -eva-hit-log")
    parser.add_argument("-j", type=int, default=8, dest="jobs")
    parser.add_argument("-o", dest="outdir")
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
    os.makedirs(os.path.join(outdir, "work"), exist_ok=True)
    share = os.path.join(outdir, "work", "share")
    if not os.path.lexists(share):
        os.symlink(os.path.abspath(SHARE), share)
    start = time.monotonic()
    if not options.report:
        env = build(options.jobs)
    runs = [run for suite in default_suites() for run in runs_of_suite(suite)]
    for run in runs:
        classify(run)
    selected = [run for run in runs if "args" in run and selects(options.patterns, run)]
    results = []
    if not options.report:
        observer = os.path.abspath(OBSERVER)
        print("%d runs, %d to execute" % (len(runs), len(selected)), flush=True)
        with concurrent.futures.ThreadPoolExecutor(options.jobs) as pool:
            futures = {pool.submit(run_one, run, outdir, env, observer): run for run in selected}
            for n, future in enumerate(concurrent.futures.as_completed(futures), 1):
                result = future.result()
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
                        result.get("not_run") or observer_state(result),
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
            with open(path) as f:
                results.append(json.load(f))
    runs = [r for r in runs if selects(options.patterns, r)]
    write_summary(outdir, runs, results, elapsed)
    print("Summary: " + os.path.join(outdir, "summary.md"))


if __name__ == "__main__":
    main()
