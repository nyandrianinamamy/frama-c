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
#   report.py tables --results DIR --programs LIST --ablations LIST
#     Reads the runs of DIR/runs and writes the tables in Markdown.

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


class Run:
    def __init__(self, directory):
        self.dir = directory
        self.ok = read_status(directory) == "0"
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
    """Runs by name without the repetition: {name: [Run]}."""
    runs = collections.defaultdict(list)
    root = os.path.join(results, "runs")
    for name in sorted(os.listdir(root)):
        match = re.fullmatch(r"(.*)-(\d+)", name)
        directory = os.path.join(root, name)
        if not match or not os.path.exists(os.path.join(directory, "time")):
            continue
        run = Run(directory)
        if run.ok:
            runs[match.group(1)].append(run)
    return runs


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


def tables(args):
    runs = load_runs(args.results)
    programs = args.programs.split()
    ablations = args.ablations.split()
    out = []
    w = out.append

    def get(name):
        return runs.get(name, [])

    w("# Tables of the campaign\n")
    revisions = os.path.join(args.results, "revisions.tsv")
    if os.path.exists(revisions):
        with open(revisions, encoding="utf-8") as f:
            rows = [line.rstrip("\n").split("\t", 1) for line in f]
        w(table(["what", "value"], rows))
    w(
        "Times in seconds, median of the runs, [min–max] across the runs; n is "
        "the number of runs. CPU is user + system time. Processor time of the "
        "phases from `Sys.time`.\n"
    )

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
                    len(rs),
                    fmt_spread([r.wall for r in rs]),
                    fmt_spread([r.cpu for r in rs]),
                    fmt(median([r.time.get("maxrss", math.nan) / 1024 for r in rs]), 0),
                    fmt(max([r.time.get("majfl", 0) for r in rs], default=math.nan), 0),
                ]
            )
    w(
        table(
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
    )
    rows = []
    for prog in programs:
        off = median([r.wall for r in get(f"off-{prog}")])
        on = median([r.wall for r in get(f"on-{prog}")])
        dev = median([r.wall for r in get(f"dev-{prog}")])
        off_it = median([r.phase("iteration") for r in get(f"off-{prog}")])
        on_it = median([r.phase("iteration") for r in get(f"on-{prog}")])
        dev_it = median([r.phase("iteration") for r in get(f"dev-{prog}")])
        off_post = median([r.phase("after iteration") for r in get(f"off-{prog}")])
        on_post = median([r.phase("after iteration") for r in get(f"on-{prog}")])
        rows.append(
            [
                prog,
                fmt(on - off),
                fmt(on_it - off_it),
                fmt(on_post - off_post),
                fmt(off - dev),
                fmt(off_it - dev_it),
            ]
        )
    w(
        table(
            [
                "program",
                "on − off, wall",
                "on − off, iteration",
                "on − off, after iteration",
                "off − dev, wall",
                "off − dev, iteration",
            ],
            rows,
        )
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
    w(
        table(
            ["program", "configuration"] + [f"{n} (wall)" for n in names] + ["iteration (CPU)"],
            rows,
        )
    )

    # 3. Named passes.
    w("## 3. Steps after the iteration, measurement build with timers\n")
    w(
        "Wall-clock time of each step of `post_analysis` and of the hooks of "
        "state Computed. 'initial state' is the computation of the initial "
        "state of the globals, inside the iteration of table 2.\n"
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
                    fmt(median(b) - median(a), 3) if a and b else "–",
                ]
            )
        w(f"### {prog} (n = {len(off)} off, {len(on)} on)\n")
        w(table(["step", "off", "on", "on − off"], rows))

    # 4. Parts of the iteration.
    w("## 4. Parts of the iteration, measurement build with timers\n")
    w(
        "Exclusive wall-clock time of each part (a part nested in another is "
        "counted in the inner one only), median of the runs. 'rest' is the "
        "iteration of the probe minus the parts. The remainder is the "
        "difference of the iteration minus the differences of the parts, "
        "that is the difference of the rest; the tolerance is the largest "
        "range of the iteration across the runs of either mode.\n"
    )
    part_names = [
        "memexec",
        "merge",
        "legacy store",
        "hooks",
        "footprint",
        "point projection",
        "call starts",
        "hits and starts",
        "state bases",
        "zone bases",
    ]
    for prog in programs:
        off, on = get(f"meter-off-{prog}"), get(f"meter-on-{prog}")
        if not off or not on:
            continue
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
        tolerance = max(
            spread([r.phase("iteration") for r in off])[1]
            - spread([r.phase("iteration") for r in off])[0],
            spread([r.phase("iteration") for r in on])[1]
            - spread([r.phase("iteration") for r in on])[0],
        )
        w(f"### {prog} (n = {len(off)} off, {len(on)} on)\n")
        w(table(["part", "off", "on", "on − off", "calls (on)"], rows))
        w(
            f"Difference of the iteration: {fmt(it_on - it_off, 2)} s; of the "
            f"parts: {fmt(total_on - total_off, 2)} s; remainder: "
            f"{fmt((it_on - it_off) - (total_on - total_off), 2)} s; tolerance: "
            f"{fmt(tolerance, 2)} s.\n"
        )

    # 5. GC counters.
    w("## 5. Garbage collector, from the probe\n")
    w(
        "Counters of `Gc.quick_stat` over the phase, median of the runs; words "
        "in millions; the top heap is the largest size of the major heap.\n"
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
    w(table(["program", "configuration", "phase"] + GC_FIELDS, rows))

    # 6. Profiles.
    w("## 6. Profiles of the iteration, perf\n")
    for prog in programs:
        off = os.path.join(args.results, "runs", f"perf-off-{prog}", "perf.tsv")
        on = os.path.join(args.results, "runs", f"perf-on-{prog}", "perf.tsv")
        if not (os.path.exists(off) and os.path.exists(on)):
            continue
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
        w(
            table(
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
        )
        for kind in ["own", "inclusive"]:
            a = p_off["functions"]["iteration"][kind]
            b = p_on["functions"]["iteration"][kind]
            names = set(a) | set(b)
            diffs = sorted(names, key=lambda n: -abs(b.get(n, 0) - a.get(n, 0)))[:20]
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
            w(f"Top 20 differences of {kind} time in the iteration (s), on − off:\n")
            w(table(["#", "function", "off", "on", "on − off"], rows))

    # 7. Ablations.
    w("## 7. Ablations, measurement build with timers, recording on\n")
    w(
        "Each ablation skips one part of the recording; its answers are wrong, "
        "so only the iteration counts. Upper bound of the saving = iteration "
        "of the control (recording on, no ablation) minus iteration of the "
        "ablation. The hits, the calls analysed by their body (memexec misses) "
        "and the alarms come from `-eva-statistics-file`; 'same' compares them "
        "with the control.\n"
    )
    for prog in programs:
        control = get(f"meter-on-{prog}")
        if not control:
            continue
        c_it = median([r.phase("iteration") for r in control])
        c_wall = median([r.wall for r in control])
        rows = [
            [
                "control",
                len(control),
                fmt_spread([r.phase("iteration") for r in control]),
                "",
                fmt(c_wall),
                "",
                "",
            ]
        ]
        c_stats = control[0].stats
        for ab in ablations:
            rs = get(f"ablate-{ab}-{prog}")
            if not rs:
                continue
            it = median([r.phase("iteration") for r in rs])
            wall = median([r.wall for r in rs])
            same = all(
                r.stats.get(k) == c_stats.get(k)
                for r in rs
                for k in ["memexec-hits", "memexec-misses", "alarm-count"]
            )
            rows.append(
                [
                    ab,
                    len(rs),
                    fmt_spread([r.phase("iteration") for r in rs]),
                    fmt(c_it - it),
                    fmt(wall),
                    fmt(c_wall - wall),
                    "yes" if same else "NO",
                ]
            )
        w(f"### {prog}\n")
        w(
            table(
                [
                    "ablation",
                    "n",
                    "iteration",
                    "upper bound (iteration)",
                    "wall",
                    "saving (wall)",
                    "same hits, analysed, alarms",
                ],
                rows,
            )
        )

    # 8. Hits.
    w("## 8. Hits\n")
    w(
        "hits: progress messages 'Reusing old results for call to'; recorded: "
        "'Recording results for' (calls analysed by their body); computing: "
        "'Computing for function'. From one run with -eva-msg-key=progress per "
        "configuration, counted on the fly. memexec hits and misses: sums of "
        "the statistics of the timed runs.\n"
    )
    rows = []
    for prog in programs:
        for key, label in CONFIGS:
            counts = {}
            path = os.path.join(args.results, "runs", f"hits-{key}-{prog}", "counts.tsv")
            if os.path.exists(path):
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
                ]
            )
    w(
        table(
            [
                "program",
                "configuration",
                "hits",
                "recorded",
                "computing",
                "memexec hits",
                "memexec misses",
                "iteration (s)",
            ],
            rows,
        )
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
                        len(rs),
                        fmt_spread([r.wall for r in rs]),
                        fmt_spread([r.phase("iteration") for r in rs]),
                    ]
                )
    w(table(["program", "recording", "build", "n", "wall", "iteration"], rows))
    sys.stdout.write("\n".join(out))


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
    p.add_argument("--programs", default="gzip monocypher")
    p.add_argument("--ablations", default="")
    args = parser.parse_args()
    if args.command == "perf-summary":
        perf_summary(args)
    else:
        tables(args)


if __name__ == "__main__":
    main()
