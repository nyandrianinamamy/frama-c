#!/usr/bin/env python3
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

# Tables of the campaign of dev/hit-log-cost/run.sh, ticket #100.
#
#   report.py perf-summary --phases FILE --freq HZ < perf-script-output
#     Reads the output of `perf script -F time,ip,sym --no-inline` and writes,
#     for the iteration and for the passes after it (windows bounded by the
#     marks of the probe phases.ml), the samples of each function, own and
#     inclusive, the samples spent in the garbage collector, and how many
#     call chains reach the start of the program.
#
#   report.py tables --results DIR --specs LIST --ablations LIST
#     Reads the runs of DIR/runs and writes the tables in Markdown. LIST of
#     --specs is that of option -p of run.sh, from which the programs and the
#     number of runs expected in each group come. Each table states the cache
#     size of its runs, and the script stops with an error if the runs of one
#     table have different cache sizes. The last table gives the revision and
#     the cache size of each run.

import argparse
import collections
import math
import os
import re
import statistics
import sys

# ----- Probe and timers --------------------------------------------------

MARKS = ["loaded", "parsed", "iteration start", "iteration end", "eva end", "exit"]
PHASES = [
    ("parsing", "loaded", "parsed"),
    ("preparation", "parsed", "iteration start"),
    ("iteration", "iteration start", "iteration end"),
    ("after iteration", "iteration end", "eva end"),
    ("exit", "eva end", "exit"),
]
GC_FIELDS = [
    "minor_words",
    "promoted_words",
    "major_words",
    "minor_collections",
    "major_collections",
]


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        lines = [line.rstrip("\n").split("\t") for line in f if line.strip()]
    header, rows = lines[0], lines[1:]
    return [dict(zip(header, row)) for row in rows]


def read_marks(path):
    marks = {}
    for row in read_tsv(path):
        marks[row["mark"]] = row
    return marks


def phase_values(marks):
    """Wall and processor time and GC counters of each phase."""
    result = {}
    for name, start, end in PHASES:
        if start not in marks or end not in marks:
            continue
        a, b = marks[start], marks[end]
        values = {
            "wall": float(b["wall"]) - float(a["wall"]),
            "cpu": float(b["cpu"]) - float(a["cpu"]),
        }
        for field in GC_FIELDS:
            values[field] = float(b[field]) - float(a[field])
        result[name] = values
    if "exit" in marks:
        result["top heap"] = {"words": float(marks["exit"]["top_heap_words"])}
    return result


def read_time(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    values = dict(re.findall(r"(\w+)=([0-9.]+)", text))
    return {k: float(v) for k, v in values.items()}


def read_stats(path):
    """Sums of the statistics of Eva over the functions."""
    sums = collections.Counter()
    if not os.path.exists(path):
        return sums
    with open(path, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 4:
                try:
                    sums[fields[0]] += float(fields[3])
                except ValueError:
                    pass
    return sums


def read_timers(path):
    parts, passes = {}, collections.OrderedDict()
    for row in read_tsv(path):
        if row["kind"] == "part":
            parts[row["name"]] = (float(row["wall"]), int(row["calls"]))
        elif row["kind"] == "pass":
            passes[row["name"]] = (float(row["wall"]), float(row["cpu"]))
    return parts, passes


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def read_cache(directory):
    """Cache size of the analyses of a run: the one noted by run.sh in the
    file cache-size, which must be that of option -cache-size in the file
    command; 'default' for a run with neither."""
    noted = read_text(os.path.join(directory, "cache-size"))
    command = read_text(os.path.join(directory, "command"))
    in_command = None
    if command is not None:
        match = re.search(r"(?:^|\s)-cache-size(?:\s+|=)(\S+)", command)
        in_command = match.group(1) if match else "default"
    if noted is not None and in_command is not None and noted != in_command:
        sys.exit(
            f"report.py: {directory}: cache size {noted} in the file "
            f"cache-size, {in_command} in the command"
        )
    return noted or in_command or "default"


class Run:
    def __init__(self, directory):
        self.dir = directory
        self.name = os.path.basename(directory)
        self.ok = read_status(directory) == "0"
        self.cache = read_cache(directory)
        self.time = read_time(os.path.join(directory, "time"))
        self.phases = phase_values(read_marks(os.path.join(directory, "phases.tsv")))
        self.stats = read_stats(os.path.join(directory, "stats.csv"))
        timers = os.path.join(directory, "timers.tsv")
        self.parts, self.passes = read_timers(timers) if os.path.exists(timers) else ({}, {})

    @property
    def wall(self):
        return self.time["elapsed"]

    @property
    def cpu(self):
        return self.time["user"] + self.time["sys"]

    def phase(self, name, key="wall"):
        return self.phases.get(name, {}).get(key, math.nan)


def read_status(directory):
    try:
        with open(os.path.join(directory, "status"), encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def load_runs(results):
    """Successful runs by name without the repetition, {name: [Run]}, and
    the other runs with a status, [[name, status]]."""
    runs, failed = collections.defaultdict(list), []
    root = os.path.join(results, "runs")
    for name in sorted(os.listdir(root)):
        match = re.fullmatch(r"(.*)-(\d+)", name)
        directory = os.path.join(root, name)
        status = read_status(directory)
        if not match or status is None:
            continue
        if status == "0" and os.path.exists(os.path.join(directory, "time")):
            runs[match.group(1)].append(Run(directory))
        else:
            failed.append([name, status])
    return runs, failed


# ----- Formatting --------------------------------------------------------


def median(values):
    values = [v for v in values if not math.isnan(v)]
    return statistics.median(values) if values else math.nan


def spread(values):
    values = [v for v in values if not math.isnan(v)]
    return (min(values), max(values)) if values else (math.nan, math.nan)


def fmt(value, digits=1):
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return "–"
    return f"{value:.{digits}f}"


def fmt_spread(values, digits=1):
    low, high = spread(values)
    return f"{fmt(median(values), digits)} [{fmt(low, digits)}–{fmt(high, digits)}]"


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(lines) + "\n"


# ----- Tables ------------------------------------------------------------

CONFIGS = [
    ("dev", "dev"),
    ("off", "branch, recording off"),
    ("on", "branch, recording on"),
]


def parse_specs(specs, ablations):
    """Programs, and the number of runs expected in each group, from the
    specifications NAME:OFF:ON:PLAIN:ABLATION-RUNS:ABLATIONS:PERF-FREQUENCY
    of run.sh."""
    programs, expected = [], collections.OrderedDict()
    for spec in specs.split():
        name, off, on, plain, abl_reps, abl, _ = spec.split(":")
        off, on, plain, abl_reps = int(off), int(on), int(plain), int(abl_reps)
        programs.append(name)
        abl = ablations if abl == "all" else [a for a in abl.split(",") if a]
        groups = [
            ("dev", off),
            ("off", off),
            ("meter-off", off),
            ("on", on),
            ("meter-on", on),
            ("plain-off", plain),
            ("plain-on", plain),
        ]
        groups += [(f"ablate-{ab}", abl_reps) for ab in abl]
        for group, n in groups:
            if n:
                expected[f"{group}-{name}"] = n
    return programs, expected


class Report:
    """The tables, and the cache sizes of the runs read for the table being
    written."""

    def __init__(self, results, runs, expected):
        self.results = results
        self.runs = runs
        self.expected = expected
        self.out = []
        self.caches = collections.defaultdict(set)

    def w(self, text):
        self.out.append(text)

    def get(self, name):
        rs = self.runs.get(name, [])
        for r in rs:
            self.caches[r.cache].add(r.name)
        return rs

    def note(self, directory):
        """Notes the cache size of run [directory], read outside [get]."""
        if os.path.isdir(directory):
            self.caches[read_cache(directory)].add(os.path.basename(directory))

    def n(self, name, rs):
        """Number of runs of group [name], with the number expected if it is
        larger."""
        want = self.expected.get(name)
        return f"{len(rs)} of {want}" if want and len(rs) < want else str(len(rs))

    def table(self, header, rows):
        if len(self.caches) > 1:
            sizes = "; ".join(
                f"{cache}: {', '.join(sorted(names))}"
                for cache, names in sorted(self.caches.items())
            )
            sys.exit(f"report.py: runs of different cache sizes in one table ({sizes})")
        caption = ""
        if self.caches:
            (cache,) = self.caches
            caption = f"\nCache size of these runs: {cache}.\n"
        self.caches = collections.defaultdict(set)
        self.w(table(header, rows) + caption)


def tables(args):
    runs, failed = load_runs(args.results)
    ablations = args.ablations.split()
    programs, expected = parse_specs(args.specs, ablations)
    R = Report(args.results, runs, expected)
    w, get = R.w, R.get

    w("# Tables of the campaign\n")
    revisions = os.path.join(args.results, "revisions.tsv")
    if os.path.exists(revisions):
        with open(revisions, encoding="utf-8") as f:
            rows = [line.rstrip("\n").split("\t", 1) for line in f]
        w(table(["what", "value"], rows))
    else:
        w("No revisions.tsv: the build stage did not run for these results.\n")
    w(
        "Times in seconds, median of the runs, [min–max] across the runs; n is "
        "the number of successful runs, followed by the number expected when "
        "it is smaller. CPU is user + system time. Processor time of the "
        "phases from `Sys.time`. The revision and the cache size of each run "
        "are in the last table.\n"
    )
    short = [
        [name, R.n(name, runs.get(name, [])), want]
        for name, want in expected.items()
        if len(runs.get(name, [])) < want
    ]
    for prog in programs:
        single = [f"hits-{key}-{prog}" for key, _ in CONFIGS]
        single += [f"perf-{mode}-{prog}" for mode in ["off", "on"]]
        for name in single:
            if read_status(os.path.join(args.results, "runs", name)) != "0":
                short.append([name, "0 of 1", 1])
    if short or failed:
        w("## Missing or failed runs\n")
        if short:
            w(table(["group", "successful", "expected"], short))
        if failed:
            w(table(["failed run", "status"], failed))

    # 1. Wall and processor time.
    w("## 1. Wall-clock and processor time\n")
    rows = []
    for prog in programs:
        for key, label in CONFIGS:
            rs = get(f"{key}-{prog}")
            rows.append(
                [
                    prog,
                    label,
                    R.n(f"{key}-{prog}", rs),
                    fmt_spread([r.wall for r in rs]),
                    fmt_spread([r.cpu for r in rs]),
                    fmt(median([r.time.get("maxrss", math.nan) / 1024 for r in rs]), 0),
                    fmt(max([r.time.get("majfl", 0) for r in rs], default=math.nan), 0),
                ]
            )
    R.table(
        [
            "program",
            "configuration",
            "n",
            "wall",
            "CPU",
            "peak RSS (MiB)",
            "major faults (max)",
        ],
        rows,
    )
    rows = []
    for prog in programs:
        off, on, dev = get(f"off-{prog}"), get(f"on-{prog}"), get(f"dev-{prog}")

        def med(rs, phase=None, key="wall"):
            if phase is None:
                return median([r.wall if key == "wall" else r.cpu for r in rs])
            return median([r.phase(phase, key) for r in rs])

        rows.append(
            [
                prog,
                fmt(med(on) - med(off)),
                fmt(med(on, key="cpu") - med(off, key="cpu")),
                fmt(med(on, "iteration") - med(off, "iteration")),
                fmt(med(on, "after iteration") - med(off, "after iteration")),
                fmt(med(off) - med(dev)),
                fmt(med(off, key="cpu") - med(dev, key="cpu")),
                fmt(med(off, "iteration") - med(dev, "iteration")),
            ]
        )
    R.table(
        [
            "program",
            "on − off, wall",
            "on − off, CPU",
            "on − off, iteration",
            "on − off, after iteration",
            "off − dev, wall",
            "off − dev, CPU",
            "off − dev, iteration",
        ],
        rows,
    )

    # 2. Phases from the probe.
    w("## 2. Phases, from the probe\n")
    w(
        "parsing: from the load of the probe to the AST; preparation: to the "
        "start of the iteration (state Computing); iteration: to its end (state "
        "Computed), the initial state of the globals included; after "
        "iteration: the passes, up to the end of the main function of Eva; "
        "exit: to the exit of the process.\n"
    )
    names = [p[0] for p in PHASES]
    rows = []
    for prog in programs:
        for key, label in CONFIGS:
            rs = get(f"{key}-{prog}")
            row = [prog, label]
            for name in names:
                row.append(fmt_spread([r.phase(name) for r in rs], 2))
            row.append(fmt_spread([r.phase("iteration", "cpu") for r in rs], 2))
            rows.append(row)
    R.table(
        ["program", "configuration"] + [f"{n} (wall)" for n in names] + ["iteration (CPU)"],
        rows,
    )

    # 3. Named passes.
    w("## 3. Steps after the iteration, measurement build with timers\n")
    w(
        "Wall-clock time of each step of `post_analysis` and of the hooks of "
        "state Computed. 'initial state' is the computation of the initial "
        "state of the globals, inside the iteration of table 2. "
        "'consolidation' runs with recording off only.\n"
    )
    for prog in programs:
        off, on = get(f"meter-off-{prog}"), get(f"meter-on-{prog}")
        names = []
        for r in off + on:
            for name in r.passes:
                if name not in names:
                    names.append(name)
        rows = []
        for name in names:
            a = [r.passes[name][0] for r in off if name in r.passes]
            b = [r.passes[name][0] for r in on if name in r.passes]
            rows.append(
                [
                    name,
                    fmt_spread(a, 3) if a else "–",
                    fmt_spread(b, 3) if b else "–",
                    fmt((median(b) if b else 0) - (median(a) if a else 0), 3),
                ]
            )
        w(
            f"### {prog} (n = {R.n(f'meter-off-{prog}', off)} off, "
            f"{R.n(f'meter-on-{prog}', on)} on)\n"
        )
        R.table(["step", "off", "on", "on − off"], rows)

    # 4. Parts of the iteration.
    w("## 4. Parts of the iteration, measurement build with timers\n")
    w(
        "Exclusive wall-clock time of each part (a part nested in another is "
        "counted in the inner one only), median of the runs. The parts are "
        "those of the timers file. 'rest' is the iteration of the probe minus "
        "the parts. The remainder is the difference of the iteration minus the "
        "differences of the parts, that is the difference of the rest. The "
        "parts account for the difference within the tolerance if the "
        "remainder is at most 10 % of the difference of the iteration, or at "
        "most the largest range of the iteration across the runs of either "
        "mode if that is larger.\n"
    )
    for prog in programs:
        off, on = get(f"meter-off-{prog}"), get(f"meter-on-{prog}")
        if not off or not on:
            continue
        part_names = []
        for r in off + on:
            for name in r.parts:
                if name not in part_names:
                    part_names.append(name)
        rows = []
        total_off = total_on = 0.0
        for name in part_names:
            a = median([r.parts.get(name, (math.nan, 0))[0] for r in off])
            b = median([r.parts.get(name, (math.nan, 0))[0] for r in on])
            calls_b = median([r.parts.get(name, (math.nan, 0))[1] for r in on])
            total_off += a
            total_on += b
            rows.append([name, fmt(a, 2), fmt(b, 2), fmt(b - a, 2), fmt(calls_b, 0)])
        it_off = median([r.phase("iteration") for r in off])
        it_on = median([r.phase("iteration") for r in on])
        rest_off = median([r.phase("iteration") - sum(v[0] for v in r.parts.values()) for r in off])
        rest_on = median([r.phase("iteration") - sum(v[0] for v in r.parts.values()) for r in on])
        rows.append(
            [
                "sum of the parts",
                fmt(total_off, 2),
                fmt(total_on, 2),
                fmt(total_on - total_off, 2),
                "",
            ]
        )
        rows.append(
            [
                "rest of the iteration",
                fmt(rest_off, 2),
                fmt(rest_on, 2),
                fmt(rest_on - rest_off, 2),
                "",
            ]
        )
        rows.append(["iteration", fmt(it_off, 2), fmt(it_on, 2), fmt(it_on - it_off, 2), ""])
        ranges = [spread([r.phase("iteration") for r in rs]) for rs in [off, on]]
        tolerance = max([0.1 * abs(it_on - it_off)] + [high - low for low, high in ranges])
        remainder = (it_on - it_off) - (total_on - total_off)
        within = abs(remainder) <= tolerance
        w(
            f"### {prog} (n = {R.n(f'meter-off-{prog}', off)} off, "
            f"{R.n(f'meter-on-{prog}', on)} on)\n"
        )
        R.table(["part", "off", "on", "on − off", "calls (on)"], rows)
        w(
            f"Difference of the iteration: {fmt(it_on - it_off, 2)} s; of the "
            f"parts: {fmt(total_on - total_off, 2)} s; remainder: "
            f"{fmt(remainder, 2)} s "
            f"({fmt(100 * remainder / (it_on - it_off) if it_on != it_off else math.nan, 1)}"
            " % of the difference); "
            f"tolerance: {fmt(tolerance, 2)} s; within the tolerance: "
            f"{'yes' if within else 'NO'}.\n"
        )

    # 5. GC counters.
    w("## 5. Garbage collector, from the probe\n")
    w(
        "Counters of `Gc.quick_stat` over the phase, median of the runs; words "
        "in millions; the top heap is the largest size of the major heap. The "
        "time spent in the collector is in table 6.\n"
    )
    rows = []
    for prog in programs:
        for key, label in CONFIGS:
            rs = get(f"{key}-{prog}")
            for phase in ["iteration", "after iteration"]:
                row = [prog, label, phase]
                for field in GC_FIELDS:
                    scale = 1e6 if field.endswith("words") else 1
                    row.append(
                        fmt(
                            median(
                                [r.phases.get(phase, {}).get(field, math.nan) / scale for r in rs]
                            ),
                            0,
                        )
                    )
                rows.append(row)
            row = (
                [prog, label, "top heap (MiB)"]
                + [
                    fmt(
                        median(
                            [
                                r.phases.get("top heap", {}).get("words", math.nan) * 8 / 2**20
                                for r in rs
                            ]
                        ),
                        0,
                    )
                ]
                + [""] * (len(GC_FIELDS) - 1)
            )
            rows.append(row)
    R.table(["program", "configuration", "phase"] + GC_FIELDS, rows)

    # 6. Profiles.
    w("## 6. Profiles, perf\n")
    for prog in programs:
        d_off = os.path.join(args.results, "runs", f"perf-off-{prog}")
        d_on = os.path.join(args.results, "runs", f"perf-on-{prog}")
        off, on = os.path.join(d_off, "perf.tsv"), os.path.join(d_on, "perf.tsv")
        if not (os.path.exists(off) and os.path.exists(on)):
            w(f"### {prog}\n\nNo profile.\n")
            continue
        R.note(d_off)
        R.note(d_on)
        p_off, p_on = read_perf(off), read_perf(on)
        freq = p_on["meta"]["freq"]
        w(f"### {prog}\n")
        rows = []
        for window in ["iteration", "after iteration"]:
            for label, p in [("off", p_off), ("on", p_on)]:
                m = p["meta"]
                total = m.get(f"{window} samples", 0)
                gc = p["gc"].get(window, {})
                rows.append(
                    [
                        window,
                        label,
                        fmt(total / freq, 1),
                        fmt(gc.get("minor", 0) / freq, 1),
                        fmt(gc.get("major", 0) / freq, 1),
                        fmt(gc.get("major allocation", 0) / freq, 1),
                        fmt(gc.get("other runtime", 0) / freq, 1),
                        fmt(100 * m.get(f"{window} complete", 0) / max(total, 1), 0),
                        fmt(100 * m.get(f"{window} switched", 0) / max(total, 1), 0),
                    ]
                )
        w(
            "Seconds = samples / frequency. GC: chains through the minor "
            "collection, through the major slices, and allocation in the major "
            "heap outside a collection. Chains: % reaching `caml_start_program`, "
            "and % stopping at a switch to the C stack (`caml_call_gc`, "
            "`caml_c_call`): the OCaml callers of those samples are unknown, so "
            "the inclusive time of an OCaml function excludes the GC and the C "
            "primitives it calls.\n"
        )
        R.table(
            [
                "window",
                "mode",
                "CPU (s)",
                "minor GC",
                "major GC",
                "major alloc.",
                "other runtime",
                "complete %",
                "C stack %",
            ],
            rows,
        )
        for window in ["iteration", "after iteration"]:
            for kind in ["own", "inclusive"]:
                a = p_off["functions"][window][kind]
                b = p_on["functions"][window][kind]
                names = set(a) | set(b)
                diffs = sorted(names, key=lambda n: (-abs(b.get(n, 0) - a.get(n, 0)), n))[:20]
                rows = [
                    [
                        i + 1,
                        f"`{n}`",
                        fmt(a.get(n, 0) / freq, 2),
                        fmt(b.get(n, 0) / freq, 2),
                        fmt((b.get(n, 0) - a.get(n, 0)) / freq, 2),
                    ]
                    for i, n in enumerate(diffs)
                ]
                w(f"Top 20 differences of {kind} time, {window} (s), on − off:\n")
                R.note(d_off)
                R.note(d_on)
                R.table(["#", "function", "off", "on", "on − off"], rows)

    # 7. Ablations.
    w("## 7. Ablations, measurement build with timers, recording on\n")
    w(
        "Each ablation skips one part of the recording; its answers are wrong, "
        "so only the iteration counts. Upper bound of the saving = median "
        "iteration of the run it is taken against minus median iteration of "
        "the ablation: the control (recording on, no ablation), or, for an "
        "ablation A+B, the runs of ablation A, so that the bound of B is its "
        "saving once A is removed. The range of the bound goes from the "
        "smallest to the largest difference between a run it is taken against "
        "and a run of the ablation; a bound whose range includes 0 is not told "
        "apart from the noise. The hits, the calls analysed by their body "
        "(memexec misses) and the alarms come from `-eva-statistics-file`; "
        "'same' compares them with the control.\n"
    )
    for prog in programs:
        control = get(f"meter-on-{prog}")
        if not control:
            continue
        c_its = [r.phase("iteration") for r in control]
        c_walls = [r.wall for r in control]
        rows = [
            [
                "control",
                "",
                R.n(f"meter-on-{prog}", control),
                fmt_spread(c_its),
                "",
                "",
                fmt(median(c_walls)),
                "",
                "",
            ]
        ]
        c_stats = control[0].stats
        prefix, suffix = "ablate-", f"-{prog}"
        found = [
            key[len(prefix) : -len(suffix)]
            for key in runs
            if key.startswith(prefix) and key.endswith(suffix)
        ]
        names = [ab for ab in ablations if ab in found]
        names += sorted(ab for ab in found if ab not in names)
        for ab in names:
            rs = get(f"ablate-{ab}-{prog}")
            against, b_its, b_walls = "control", c_its, c_walls
            if "+" in ab:
                against = ab.rsplit("+", 1)[0]
                base = get(f"ablate-{against}-{prog}")
                b_its = [r.phase("iteration") for r in base]
                b_walls = [r.wall for r in base]
            its = [r.phase("iteration") for r in rs]
            walls = [r.wall for r in rs]
            bound = median(b_its) - median(its)
            low, high = min(b_its) - max(its), max(b_its) - min(its)
            same = all(
                r.stats.get(k) == c_stats.get(k)
                for r in rs
                for k in ["memexec-hits", "memexec-misses", "alarm-count"]
            )
            rows.append(
                [
                    ab,
                    against,
                    R.n(f"ablate-{ab}-{prog}", rs),
                    fmt_spread(its),
                    f"{fmt(bound)} [{fmt(low)}–{fmt(high)}]",
                    "yes" if low > 0 else "no",
                    fmt(median(walls)),
                    fmt(median(b_walls) - median(walls)),
                    "yes" if same else "NO",
                ]
            )
        w(f"### {prog}\n")
        R.table(
            [
                "ablation",
                "against",
                "n",
                "iteration",
                "upper bound (iteration)",
                "above the noise",
                "wall",
                "saving (wall)",
                "same hits, analysed, alarms",
            ],
            rows,
        )

    # 8. Hits.
    w("## 8. Hits\n")
    w(
        "From one run with -eva-msg-key=progress per configuration, counted on "
        "the fly: hits, the messages 'Reusing old results for call to'; "
        "recorded, 'Recording results for' (calls analysed by their body, the "
        "main function included); computing, 'computing for function' (calls "
        "analysed by their body or their specification that are not hits). "
        "memexec hits and misses: sums of `-eva-statistics-file` over the "
        "functions, in the timed runs of the configuration (distinct values "
        "separated by /).\n"
    )
    rows = []
    for prog in programs:
        for key, label in CONFIGS:
            counts = {}
            directory = os.path.join(args.results, "runs", f"hits-{key}-{prog}")
            path = os.path.join(directory, "counts.tsv")
            if os.path.exists(path) and read_status(directory) == "0":
                R.note(directory)
                with open(path, encoding="utf-8") as f:
                    counts = dict(line.rstrip("\n").split("\t") for line in f if line.strip())
            rs = get(f"{key}-{prog}")
            hits = sorted({r.stats.get("memexec-hits", 0) for r in rs})
            misses = sorted({r.stats.get("memexec-misses", 0) for r in rs})
            rows.append(
                [
                    prog,
                    label,
                    counts.get("hits", "–"),
                    counts.get("recorded", "–"),
                    counts.get("computing", "–"),
                    "/".join(fmt(h, 0) for h in hits),
                    "/".join(fmt(m, 0) for m in misses),
                    fmt(median([r.phase("iteration") for r in rs])),
                    fmt(median([r.wall for r in rs])),
                ]
            )
    R.table(
        [
            "program",
            "configuration",
            "hits",
            "recorded",
            "computing",
            "memexec hits",
            "memexec misses",
            "iteration (s)",
            "wall (s)",
        ],
        rows,
    )

    # 9. Cost of the measurement build.
    w("## 9. Measurement build against the branch\n")
    w(
        "branch: this checkout; plain: the measurement build with no variable "
        "set (timers off, no ablation); meter: the measurement build with the "
        "timers. Wall-clock time and iteration.\n"
    )
    rows = []
    for prog in programs:
        for mode in ["off", "on"]:
            for key, label in [
                (f"{mode}-{prog}", "branch"),
                (f"plain-{mode}-{prog}", "plain"),
                (f"meter-{mode}-{prog}", "meter"),
            ]:
                rs = get(key)
                rows.append(
                    [
                        prog,
                        mode,
                        label,
                        R.n(key, rs),
                        fmt_spread([r.wall for r in rs]),
                        fmt_spread([r.phase("iteration") for r in rs]),
                    ]
                )
    R.table(["program", "recording", "build", "n", "wall", "iteration"], rows)

    # 10. Revision and cache size of each run.
    w("## 10. Runs\n")
    w(
        "Each run directory, with the revision of its build as noted when it "
        "was built, the cache size of its analyses, and its status.\n"
    )
    rows = []
    root = os.path.join(args.results, "runs")
    for name in sorted(os.listdir(root)):
        directory = os.path.join(root, name)
        if not os.path.isdir(directory):
            continue
        time = os.path.join(directory, "time")
        wall = read_time(time).get("elapsed", math.nan) if os.path.exists(time) else math.nan
        rows.append(
            [
                name,
                read_text(os.path.join(directory, "revision")) or "unknown",
                read_cache(directory),
                read_status(directory) or "none",
                fmt(wall),
            ]
        )
    w(table(["run", "revision", "cache size", "status", "wall"], rows))
    sys.stdout.write("\n".join(R.out))


# ----- perf --------------------------------------------------------------

MINOR = re.compile(
    r"^(caml_empty_minor_heap|caml_stw_empty_minor_heap|caml_minor_collection|"
    r"oldify|caml_oldify|caml_empty_minor_heaps)"
)
MAJOR = re.compile(
    r"^(caml_major_collection_slice|major_collection_slice|mark_slice|caml_mark|"
    r"mark_|sweep|caml_sweep|"
    r"caml_finish_major_cycle|cycle_all_domains|caml_compact_heap|compact_|ephe_|caml_ephe|"
    r"caml_opportunistic_major|do_some_marking|clean_slice|caml_darken|darken)"
)
ALLOC = re.compile(
    r"^(caml_alloc_shr|caml_shared_try_alloc|pool_|large_alloc|caml_alloc_custom|caml_alloc_string)"
)
RUNTIME = re.compile(
    r"^(caml_call_gc|caml_alloc_small_dispatch|caml_poll_gc_work|caml_do_pending_actions)"
)
ROOTS = {
    "caml_start_program",
    "caml_program",
    "_start",
    "__libc_start_main",
    "__libc_start_call_main",
}
SWITCH = re.compile(
    r"^(caml_call_gc|caml_c_call|caml_c_call_stack_args|caml_call_realloc_stack|"
    r"caml_alloc[0-9]|caml_allocN)$"
)


def gc_class(frames):
    for sym in frames:
        if MINOR.match(sym):
            return "minor"
        if MAJOR.match(sym):
            return "major"
    for sym in frames:
        if ALLOC.match(sym):
            return "major allocation"
    for sym in frames:
        if RUNTIME.match(sym):
            return "other runtime"
    return None


def perf_summary(args):
    marks = read_marks(args.phases)
    windows = [
        (
            "iteration",
            float(marks["iteration start"]["wall"]),
            float(marks["iteration end"]["wall"]),
        ),
        ("after iteration", float(marks["iteration end"]["wall"]), float(marks["eva end"]["wall"])),
    ]
    meta = collections.Counter()
    own = {w[0]: collections.Counter() for w in windows}
    incl = {w[0]: collections.Counter() for w in windows}
    gc = {w[0]: collections.Counter() for w in windows}

    def flush(time, frames):
        if time is None:
            return
        meta["samples"] += 1
        for name, start, end in windows:
            if start <= time < end:
                break
        else:
            return
        meta[f"{name} samples"] += 1
        if not frames:
            frames = ["[none]"]
        own[name][frames[0]] += 1
        for sym in set(frames):
            incl[name][sym] += 1
        cls = gc_class(frames)
        if cls:
            gc[name][cls] += 1
        if frames[-1] in ROOTS:
            meta[f"{name} complete"] += 1
        elif any(SWITCH.match(s) for s in frames):
            meta[f"{name} switched"] += 1

    time, frames = None, []
    for line in sys.stdin:
        if not line.strip():
            continue
        if line[0] not in " \t":
            flush(time, frames)
            match = re.search(r"(\d+\.\d+):", line)
            time = float(match.group(1)) if match else None
            frames = []
        else:
            fields = line.split(None, 1)
            sym = fields[1].strip() if len(fields) > 1 else "[unknown]"
            sym = re.sub(r"\s+\(.*\)$", "", sym)
            sym = re.sub(r"\+0x[0-9a-f]+$", "", sym)
            frames.append(sym)
    flush(time, frames)

    out = sys.stdout
    out.write("kind\twindow\tname\town\tinclusive\n")
    out.write(f"meta\t\tfreq\t{args.freq}\t\n")
    for key, value in sorted(meta.items()):
        out.write(f"meta\t\t{key}\t{value}\t\n")
    for name, _, _ in windows:
        for cls, value in sorted(gc[name].items()):
            out.write(f"gc\t{name}\t{cls}\t{value}\t\n")
        for sym in sorted(incl[name]):
            out.write(f"function\t{name}\t{sym}\t{own[name].get(sym, 0)}\t{incl[name][sym]}\n")


def read_perf(path):
    result = {
        "meta": {},
        "gc": collections.defaultdict(dict),
        "functions": collections.defaultdict(lambda: {"own": {}, "inclusive": {}}),
    }
    for row in read_tsv(path):
        if row["kind"] == "meta":
            result["meta"][row["name"]] = float(row["own"])
        elif row["kind"] == "gc":
            result["gc"][row["window"]][row["name"]] = float(row["own"])
        elif row["kind"] == "function":
            f = result["functions"][row["window"]]
            f["own"][row["name"]] = float(row["own"])
            f["inclusive"][row["name"]] = float(row["inclusive"])
    return result


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("perf-summary")
    p.add_argument("--phases", required=True)
    p.add_argument("--freq", type=float, required=True)
    p = sub.add_parser("tables")
    p.add_argument("--results", required=True)
    p.add_argument("--specs", required=True)
    p.add_argument("--ablations", default="")
    args = parser.parse_args()
    if args.command == "perf-summary":
        perf_summary(args)
    else:
        tables(args)


if __name__ == "__main__":
    main()
