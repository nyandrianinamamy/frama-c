##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

"""Compare the records of the acceptance driver and write the report.

Usage: compare.py EVIDENCE-DIR FIXTURE... [--require-zero-reads] [--no-write]

For each fixture, EVIDENCE-DIR holds NAME.reference.jsonl and
NAME.candidate.jsonl, written by separate processes. Answers are compared
as text: equal text means equal printed answers. NAME.native.jsonl, when
present, holds the native comparison of the models of a reference and a
candidate run in one process. Each call gets one disposition:

  MATCH       equal answers, no legacy read during the call
  LEGACY      equal answers, served with legacy reads
  MISMATCH    different answers
  MISSING     the call is absent from one of the runs
  UNOBSERVED  equal answers, but the candidate's guard was off

Each call also states the path expected to serve it (resolver or none);
the resolver and sensitivity controls check it against the reads and
resolutions of the candidate and of the legacy path. The candidates run
under the continuous trap, armed once before the analysis: any legacy read
aborts them. The zero-read gate passes when no call is LEGACY or
UNOBSERVED, the candidates logged no read during the execution either, and
the gate record of every candidate passes. The exit status is 1 on any
MISMATCH, MISSING or failed control, and also on a failed gate with
--require-zero-reads. --no-write skips writing report.md and report.json."""

import hashlib
import json
from pathlib import Path
import re
import sys

# Expected exit status, phase and reader of each trap control. The hit log
# serves every read: these controls run on the legacy path. No read happens
# during the initialization, on either path.
CONTROLS = {
    "request": (1, "request", "Eva.Results.get_cvalue_model"),
    "analysis": (1, "analysis", "Eva.Engine.register_state"),
    "collection": (1, "collection", "Eva.Summary.compute_fun_stats"),
    "post-analysis": (1, "post-analysis", "Eva.Eval_annots.mark_unreachable"),
    "initialization": (0, None, None),
}
CONTROL_FIXTURE = "legacy-reads"
PLUGIN_FIXTURE = "plugins"
TRAP_PREFIX = "legacy result-store read trapped: "


def records(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def load(path):
    rs = records(path)
    header = next(r for r in rs if r["kind"] == "header")
    calls = [r for r in rs if r["kind"] == "call"]
    execution = [r for r in rs if r["kind"] == "execution"]
    return header, calls, execution


def collection(path):
    return next((r["reads"] for r in records(path) if r["kind"] == "collection"), [])


def accounting(path):
    return next((r for r in records(path) if r["kind"] == "accounting"), None)


def gate_record(path):
    return next((r for r in records(path) if r["kind"] == "gate"), None)


def scopes(path):
    return [
        {k: r[k] for k in ("phase", "entries", "reads", "resolutions", "registrations")}
        for r in records(path)
        if r["kind"] == "scope"
    ]


def disposition(expected, observed):
    if expected is None or observed is None:
        return "MISSING"
    if expected["answer"] != observed["answer"]:
        return "MISMATCH"
    if observed["reads"] is None:
        return "UNOBSERVED"
    return "LEGACY" if observed["reads"] else "MATCH"


def compare_calls(reference, candidate):
    observed = {c["id"]: c for c in candidate}
    ids = [c["id"] for c in reference]
    ids += [c["id"] for c in candidate if c["id"] not in ids]
    expected = {c["id"]: c for c in reference}
    rows = []
    for call_id in ids:
        exp, obs = expected.get(call_id), observed.get(call_id)
        reads = (obs or {}).get("reads") or []
        resolved = (obs or {}).get("resolved") or []
        rows.append(
            {
                "id": call_id,
                "family": (exp or obs)["family"],
                "request": (exp or obs)["request"],
                "expect": (exp or obs).get("expect"),
                "expected": exp and exp["answer"],
                "observed": obs and obs["answer"],
                "legacy_reads": len(reads),
                "readers": sorted(
                    {f"{r['phase']}/{r['reader']}/{r['access']}/{r['store']}" for r in reads}
                ),
                "resolved": len(resolved),
                "visits": sorted({r["visits"] for r in resolved}),
                "disposition": disposition(exp, obs),
            }
        )
    return rows


def digest(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


def native_report(evidence, name):
    path = evidence / f"{name}.native.jsonl"
    if not path.exists():
        return None
    rs = records(path)
    summary = next((r for r in rs if r["kind"] == "native-summary"), None)
    return {
        "summary": summary,
        "differing": [r["id"] for r in rs if r["kind"] == "native" and r["equal"] is False],
        "text_differing": [
            r["id"] for r in rs if r["kind"] == "native" and not r.get("text_equal", True)
        ],
        "resolved": {r["id"]: len(r["resolved"]) for r in rs if r["kind"] == "native"},
        "reference_resolved": sum(
            len(r["reference_resolved"]) for r in rs if r["kind"] == "native"
        ),
    }


def fixture_report(evidence, name):
    ref_header, ref_calls, _ = load(evidence / f"{name}.reference.jsonl")
    cand_header, cand_calls, execution = load(evidence / f"{name}.candidate.jsonl")
    rows = compare_calls(ref_calls, cand_calls)
    inputs = [{"path": p, "sha256": digest(p)} for p in cand_header["inputs"]]
    return {
        "fixture": name,
        "reference": {k: ref_header[k] for k in ("argv", "guard", "config")},
        "candidate": {k: cand_header[k] for k in ("argv", "guard", "config")},
        "plugins": cand_header["plugins"],
        "same_plugins": ref_header["plugins"] == cand_header["plugins"],
        "same_inputs": ref_header["inputs"] == cand_header["inputs"],
        "inputs": inputs,
        "execution": [{**e["first"], "count": e["count"]} for e in execution],
        "execution_reads": sum(e["count"] for e in execution),
        "collection": collection(evidence / f"{name}.candidate.jsonl"),
        "native": native_report(evidence, name),
        "accounting": {
            "reference": accounting(evidence / f"{name}.reference.jsonl"),
            "candidate": accounting(evidence / f"{name}.candidate.jsonl"),
        },
        "gate": gate_record(evidence / f"{name}.candidate.jsonl"),
        "scopes": scopes(evidence / f"{name}.candidate.jsonl"),
        "calls": rows,
    }


TRAP_FIELDS = re.compile(
    r"phase=(?P<phase>\S+) reader=(?P<reader>\S+) access=(?P<access>\S+) "
    r"store=(?P<store>\S+) point=(?P<point>.*?)(?: via=(?P<via>\S+))?$"
)


def parse_trap(log):
    for line in log.splitlines():
        if TRAP_PREFIX in line:
            match = TRAP_FIELDS.match(line.split(TRAP_PREFIX, 1)[1])
            return match and match.groupdict()
    return None


def control_report(evidence, phase):
    status_path = evidence / f"control-{phase}.status"
    log_path = evidence / f"control-{phase}.log"
    expected_status, expected_phase, expected_reader = CONTROLS[phase]
    if not status_path.exists():
        return {"control": f"trap:{phase}", "result": "NOT RUN"}
    status = int(status_path.read_text())
    trap = parse_trap(log_path.read_text())
    observed = {
        "status": status,
        "phase": trap and trap.get("phase"),
        "reader": trap and trap.get("reader"),
        "access": trap and trap.get("access"),
        "point": trap and trap.get("point"),
    }
    ok = (
        status == expected_status
        and observed["phase"] == expected_phase
        and observed["reader"] == expected_reader
    )
    return {
        "control": f"trap:{phase}",
        "expected": {
            "status": expected_status,
            "phase": expected_phase,
            "reader": expected_reader,
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


def comparator_control(evidence):
    """Altering one agreeing answer must add exactly one MISMATCH to those
    the evidence already has."""
    path = evidence / f"{CONTROL_FIXTURE}.candidate.jsonl"
    _, ref_calls, _ = load(evidence / f"{CONTROL_FIXTURE}.reference.jsonl")
    _, cand_calls, _ = load(path)

    def mismatches(calls):
        rows = compare_calls(ref_calls, calls)
        return [r["id"] for r in rows if r["disposition"] == "MISMATCH"]

    differing = set(mismatches(cand_calls))
    ref_ids = {c["id"] for c in ref_calls}
    target = next(
        (i for i, c in enumerate(cand_calls) if c["id"] in ref_ids and c["id"] not in differing),
        None,
    )
    if target is None:
        return {"control": "comparator-mismatch", "result": "NOT RUN"}
    altered = [dict(c) for c in cand_calls]
    altered[target]["answer"] += " (altered)"
    added = sorted(set(mismatches(altered)) - differing)
    expected = [altered[target]["id"]]
    return {
        "control": "comparator-mismatch",
        "expected": {"added_mismatches": expected},
        "observed": {"added_mismatches": added},
        "result": "PASS" if added == expected else "FAIL",
    }


def status_of(evidence, stem):
    path = evidence / f"{stem}.status"
    return int(path.read_text()) if path.exists() else None


def trap_of(evidence, stem):
    path = evidence / f"{stem}.log"
    return parse_trap(path.read_text()) if path.exists() else None


# The fixtures whose candidate command also runs on the legacy path, as the
# positive control of the continuous trap, and with the tail probe.
CONTINUOUS_FIXTURES = ("legacy-reads", "plugins")
# Where the continuous trap aborts the legacy path: the first read of the
# analysis, when the state at the start of main is registered.
CONTINUOUS_LEGACY = ("analysis", "Eva.Engine.register_state")


def continuous_trap_control(fixtures):
    """Every candidate ran under the trap of every phase, armed once before
    the analysis and never changed: the guard was never armed with another
    mode, the battery completed, and the trap logged no read."""
    observed, ok = {}, bool(fixtures)
    for f in fixtures:
        gate = f["gate"] or {}
        observed[f["fixture"]] = {
            "guard": f["candidate"]["guard"],
            "arms": gate.get("arms"),
            "logged": gate.get("logged"),
            "trapped_count": gate.get("trapped_count"),
        }
        ok &= (
            f["candidate"]["guard"] == "trap:all"
            and gate.get("arms") == ["trap:all"]
            and gate.get("final") == "trap:all"
            and gate.get("logged") == 0
            and gate.get("trapped") is None
            and gate.get("trapped_count") == 0
            and gate.get("passes") is True
        )
    return {
        "control": "continuous-trap",
        "expected": {
            "guard": "trap:all",
            "arms": ["trap:all"],
            "logged": 0,
            "trapped_count": 0,
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


def continuous_legacy_control(evidence):
    """The candidate's command on the legacy path, under the same trap, must
    abort at the first read of the legacy store."""
    observed, ok = {}, True
    for name in CONTINUOUS_FIXTURES:
        stem = f"control-continuous-legacy-{name}"
        status, trap = status_of(evidence, stem), trap_of(evidence, stem) or {}
        observed[name] = {
            "status": status,
            "phase": trap.get("phase"),
            "reader": trap.get("reader"),
            "point": trap.get("point"),
        }
        ok &= status == 1 and (trap.get("phase"), trap.get("reader")) == CONTINUOUS_LEGACY
    return {
        "control": "continuous-trap-legacy-path",
        "expected": {
            "status": 1,
            "phase": CONTINUOUS_LEGACY[0],
            "reader": CONTINUOUS_LEGACY[1],
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


TAIL_PROBE = re.compile(r"\[acceptance\] tail-probe logged=(\d+) trapped=(\d+)")


def tail_probe_control(evidence):
    """After the candidate's battery, still under the trap and with no read
    logged, a request on cleared results must abort in the request phase:
    the trap is still armed at the end of the run."""
    observed, ok = {}, True
    for name in CONTINUOUS_FIXTURES:
        stem = f"control-tail-probe-{name}"
        log_path, jsonl = evidence / f"{stem}.log", evidence / f"{stem}.jsonl"
        status, trap = status_of(evidence, stem), trap_of(evidence, stem) or {}
        before = TAIL_PROBE.search(log_path.read_text()) if log_path.exists() else None
        gate = (gate_record(jsonl) if jsonl.exists() else None) or {}
        observed[name] = {
            "status": status,
            "before_probe": before and {"logged": int(before[1]), "trapped": int(before[2])},
            "gate_passes": gate.get("passes"),
            "phase": trap.get("phase"),
            "reader": trap.get("reader"),
        }
        ok &= (
            status == 1
            and before is not None
            and before[1] == "0"
            and before[2] == "0"
            and gate.get("passes") is True
            and trap.get("phase") == "request"
        )
    return {
        "control": "tail-probe",
        "expected": {
            "status": 1,
            "before_probe": {"logged": 0, "trapped": 0},
            "gate_passes": True,
            "phase": "request",
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


# Phases in which the legacy path must read its store. No read happens
# during the initialization, on either path.
READING_PHASES = ("analysis", "collection", "post-analysis", "request")


def by_phase(rows):
    return {r["phase"]: r for r in rows}


def sensitivity_control(evidence, fixtures):
    """The guard sees the reads that the candidates avoid. The same battery
    on the legacy path, with every read logged, reads the store in each
    phase but the initialization, and on each request that the candidate's
    resolver serves; the candidate reads in no phase. A request that reads
    neither store, such as a supplied state, reads and resolves nothing on
    either path."""
    by_name = {f["fixture"]: f for f in fixtures}
    observed, ok = {}, True
    for name in CONTINUOUS_FIXTURES:
        path = evidence / f"control-sensitivity-{name}.jsonl"
        if name not in by_name or not path.exists():
            return {"control": "guard-sensitivity", "result": "NOT RUN"}
        f = by_name[name]
        legacy_scopes = by_phase(scopes(path))
        cand_scopes = by_phase(f["scopes"])
        _, legacy_calls, _ = load(path)
        legacy = {c["id"]: c for c in legacy_calls}
        resolver = [r["id"] for r in f["calls"] if r["expect"] == "resolver"]
        silent = [i for i in resolver if not (legacy.get(i) or {}).get("reads")]
        unread = [r for r in f["calls"] if r["expect"] == "none"]
        noisy = [
            r["id"]
            for r in unread
            if r["legacy_reads"]
            or r["resolved"]
            or (legacy.get(r["id"]) or {}).get("reads")
            or (legacy.get(r["id"]) or {}).get("resolved")
        ]
        phases = {
            p: {
                "legacy_path": (legacy_scopes.get(p) or {}).get("reads"),
                "candidate": (cand_scopes.get(p) or {}).get("reads"),
            }
            for p in ("initialization",) + READING_PHASES
        }
        observed[name] = {
            "reads_by_phase": phases,
            "resolver_calls": len(resolver),
            "resolver_calls_without_legacy_reads": silent,
            "unread_calls": len(unread),
            "unread_with_reads": noisy,
        }
        ok &= (
            all(v["candidate"] == 0 for v in phases.values())
            and all((phases[p]["legacy_path"] or 0) > 0 for p in READING_PHASES)
            and phases["initialization"]["legacy_path"] == 0
            and bool(resolver)
            and not silent
            and not noisy
        )
    return {
        "control": "guard-sensitivity",
        "expected": {
            "reads_by_phase": {
                "candidate": 0,
                "legacy_path": {"initialization": 0, "other phases": ">0"},
            },
            "resolver_calls_without_legacy_reads": [],
            "unread_with_reads": [],
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


REGISTRATION = (
    "Eva.Engine.register_state",
    "Eva.Function_calls.register_analysis_target",
    "Eva.Iterator.record_fireable",
)


def registration_control(fixtures):
    """During the analysis of each candidate, the three writers of the
    legacy store take the previously registered value from the hit log:
    each resolves in the analysis phase, and no phase reads."""
    observed, ok = {}, bool(fixtures)
    for f in fixtures:
        analysis = by_phase(f["scopes"]).get("analysis") or {}
        counts = analysis.get("registrations") or {}
        observed[f["fixture"]] = {
            "entries": {s["phase"]: s["entries"] for s in f["scopes"]},
            "registrations": counts,
        }
        ok &= (
            analysis.get("entries", 0) > 0
            and counts.get(REGISTRATION[0], 0) > 0
            and counts.get(REGISTRATION[1], 0) > 0
            and all(s["reads"] == 0 for s in f["scopes"])
        )
    return {
        "control": "hit-log-registration",
        "expected": {"registrations": {REGISTRATION[0]: ">0", REGISTRATION[1]: ">0"}},
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


def store_check_control(evidence, names):
    """The legacy store that the analysis writes from the hit log: once the
    hit log declines every request, each request reads that store, and its
    answer must still be the reference's. The analysis that a request runs,
    such as the intervening analysis of the snapshot, still registers its
    results through the hit log: these resolutions, in the analysis phase,
    serve no request."""
    observed, ok = {}, bool(names)
    for name in names:
        path = evidence / f"control-store-check-{name}.jsonl"
        if not path.exists():
            return {"control": "legacy-store-writes", "result": "NOT RUN"}
        _, ref_calls, _ = load(evidence / f"{name}.reference.jsonl")
        _, calls, _ = load(path)
        rows = compare_calls(ref_calls, calls)
        differing = [r["id"] for r in rows if r["disposition"] in ("MISMATCH", "MISSING")]
        reads = sum(r["legacy_reads"] for r in rows)
        resolved = [
            c["id"]
            for c in calls
            if any(x.get("phase") != "analysis" for x in c.get("resolved") or [])
        ]
        observed[name] = {
            "calls": len(rows),
            "differing": differing,
            "legacy_reads": reads,
            "resolved": resolved,
        }
        ok &= bool(rows) and not differing and reads > 0 and not resolved
    return {
        "control": "legacy-store-writes",
        "expected": {
            "differing": [],
            "legacy_reads": ">0",
            "resolved outside an analysis": [],
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


# The request that prints the exported statuses and callers.
EXPORT_CALLS = "export.calls"


def export_payload_control(evidence):
    """A hit log that exports every function as unreachable and without
    caller changes the exported payload only: the comparison must report
    export.calls, and nothing else. The statuses read after restoring that
    payload stay the reference's: the restored records of the hit log serve
    them, not the exported tables."""
    path = evidence / "control-perturb-calls-plugins.jsonl"
    if not path.exists():
        return {"control": "export-payload-perturbation", "result": "NOT RUN"}
    _, ref_calls, _ = load(evidence / f"{PLUGIN_FIXTURE}.reference.jsonl")
    _, calls, _ = load(path)
    rows = compare_calls(ref_calls, calls)
    mismatches = [r["id"] for r in rows if r["disposition"] in ("MISMATCH", "MISSING")]
    restored = next((r for r in rows if r["id"] == "export.statuses"), {})
    ok = mismatches == [EXPORT_CALLS] and restored.get("disposition") in ("MATCH", "LEGACY")
    return {
        "control": "export-payload-perturbation",
        "expected": {"mismatches": [EXPORT_CALLS], "export.statuses": "equal"},
        "observed": {
            "mismatches": mismatches,
            "export.statuses": restored.get("disposition"),
        },
        "result": "PASS" if ok else "FAIL",
    }


def snapshot_control(fixtures):
    """The snapshot round trip: the exported statuses and callers are the
    reference's; an intervening analysis changes the statuses; restoring
    the snapshot gives back the statuses read before the export. Each of
    these requests is served by the hit log, under the trap."""
    fixture = next((f for f in fixtures if f["fixture"] == PLUGIN_FIXTURE), None)
    if fixture is None:
        return {"control": "snapshot-round-trip", "result": "NOT RUN"}
    rows = {r["id"]: r for r in fixture["calls"]}
    ids = [EXPORT_CALLS, "snapshot.statuses", "snapshot.intervening", "export.statuses"]
    not_matching = [i for i in ids if (rows.get(i) or {}).get("disposition") != "MATCH"]
    intervening = (rows.get("snapshot.intervening") or {}).get("observed") or ""
    before = (rows.get("snapshot.statuses") or {}).get("observed")
    after = (rows.get("export.statuses") or {}).get("observed")
    differs = intervening.startswith("differs=true")
    ok = not not_matching and differs and before is not None and before == after
    return {
        "control": "snapshot-round-trip",
        "expected": {
            "not_matching": [],
            "intervening_differs": True,
            "restored_equals_saved": True,
        },
        "observed": {
            "not_matching": not_matching,
            "intervening_differs": differs,
            "restored_equals_saved": before is not None and before == after,
        },
        "result": "PASS" if ok else "FAIL",
    }


def resolver_control(fixtures):
    """Every request expected on the resolver is served by it, with no
    legacy read, and no other request is."""
    unserved, unexpected = [], []
    count = 0
    for f in fixtures:
        for r in f["calls"]:
            if r["disposition"] == "MISSING":
                continue
            if r["expect"] == "resolver":
                count += 1
                if not r["resolved"] or r["legacy_reads"]:
                    unserved.append(f"{f['fixture']}:{r['id']}")
            elif r["resolved"]:
                unexpected.append(f"{f['fixture']}:{r['id']}")
    return {
        "control": "resolver-path",
        "expected": {"unserved": [], "unexpected": []},
        "observed": {
            "resolver_calls": count,
            "unserved": unserved,
            "unexpected": unexpected,
        },
        "result": "PASS" if count and not unserved and not unexpected else "FAIL",
    }


def perturbation_control(evidence):
    """A resolver that rebuilds every visit from the first producer of its
    function answers the second stack with the state of the first call: the
    comparison must report it, on requests served by the resolver only."""
    path = evidence / "control-wrong-producer.jsonl"
    if not path.exists():
        return {"control": "resolver-perturbation", "result": "NOT RUN"}
    _, ref_calls, _ = load(evidence / f"{CONTROL_FIXTURE}.reference.jsonl")
    _, calls, _ = load(path)
    rows = compare_calls(ref_calls, calls)
    mismatches = [r for r in rows if r["disposition"] == "MISMATCH"]
    outside = [r["id"] for r in mismatches if r["expect"] != "resolver"]
    ok = bool(mismatches) and not outside
    return {
        "control": "resolver-perturbation",
        "expected": {"mismatches": ">0", "outside_resolver": []},
        "observed": {
            "mismatches": [r["id"] for r in mismatches],
            "outside_resolver": outside,
        },
        "result": "PASS" if ok else "FAIL",
    }


SELECTION_FIXTURE = "selection"
# Answers of the fresh-only reference that make the selection fixture
# discriminate, with the reason. The unfiltered request evaluates the joined
# state; a selection evaluates each stack then joins the answers, even when
# it names every stack; the visits of one stack are joined before the
# evaluation.
SELECTION_EXPECTED = {
    "eval_exp[u==w].unfiltered": "{0; 1}",
    "eval_exp[u==w].selector-all": "{1}",
    "eval_exp[u==w].filter-all": "{1}",
    "eval_exp[x==y].stack:main/g@53": "{0; 1}",
    "eval_exp[x==y].stack:main/g@49": "{1}",
    "eval_exp[100/((u-w)+1)].unfiltered": "{-100; 33; 50; 100}",
    "eval_exp[100/((u-w)+1)].selector-all": "{100}",
    "eval_callee[*(tbl[u-w])].unfiltered": "f1 f2",
    "eval_callee[*(tbl[u-w])].selector-all": "f1",
    "eval_exp[x==y].supplied": "{0}",
}


def selection_control(fixtures):
    """The selection fixture distinguishes evaluating the joined state from
    evaluating each stack then joining, on the reference's own answers; its
    enumeration order differs from the order of the names; and the
    candidate serves each of these requests like the reference."""
    fixture = next((f for f in fixtures if f["fixture"] == SELECTION_FIXTURE), None)
    if fixture is None:
        return {"control": "selection-order", "result": "NOT RUN"}
    rows = {r["id"]: r for r in fixture["calls"]}

    def reference(call_id):
        # The value of an evaluation, before its alarms.
        text = (rows.get(call_id) or {}).get("expected") or ""
        return text.split("; alarms")[0]

    wrong = {i: reference(i) for i in SELECTION_EXPECTED if reference(i) != SELECTION_EXPECTED[i]}
    stacks = reference("stacks.unfiltered").split()
    order_exercised = len(stacks) > 2 and stacks != sorted(stacks)
    checked = list(SELECTION_EXPECTED) + [
        "stacks.unfiltered",
        "by_callstack.unfiltered",
    ]
    served = [
        i
        for i in checked
        if (rows.get(i) or {}).get("disposition") != "MATCH"
        or (rows[i]["expect"] == "resolver" and not rows[i]["resolved"])
    ]
    ok = not wrong and order_exercised and not served
    return {
        "control": "selection-order",
        "expected": {
            "reference_answers": SELECTION_EXPECTED,
            "stack_order_differs_from_names": True,
            "not_served_like_reference": [],
        },
        "observed": {
            "reference_answers_differing": wrong,
            "stacks.unfiltered": " ".join(stacks),
            "not_served_like_reference": served,
        },
        "result": "PASS" if ok else "FAIL",
    }


def selection_perturbation_control(evidence):
    """With the wrong producer, the requests on several stacks or none of the
    selection fixture must report MISMATCH, on resolved requests only."""
    path = evidence / "control-wrong-producer-selection.jsonl"
    if not path.exists():
        return {"control": "selection-perturbation", "result": "NOT RUN"}
    _, ref_calls, _ = load(evidence / f"{SELECTION_FIXTURE}.reference.jsonl")
    _, calls, _ = load(path)
    rows = compare_calls(ref_calls, calls)
    mismatches = [r for r in rows if r["disposition"] == "MISMATCH"]
    outside = [r["id"] for r in mismatches if r["expect"] != "resolver"]
    several = [
        r["id"]
        for r in mismatches
        if r["id"].endswith((".unfiltered", ".selector-all", ".filter-all", ".filter-drop-first"))
    ]
    ok = bool(several) and not outside
    return {
        "control": "selection-perturbation",
        "expected": {"several_or_no_stack_mismatches": ">0", "outside_resolver": []},
        "observed": {
            "mismatches": len(mismatches),
            "several_or_no_stack_mismatches": len(several),
            "outside_resolver": outside,
        },
        "result": "PASS" if ok else "FAIL",
    }


# Reports that Eva derives from its results after the analysis: reading
# them reads neither store, but they follow the answers of the resolver.
DERIVED_FAMILIES = {"statuses", "statistics"}


def plugin_perturbation_control(evidence):
    """With the wrong producer, the plug-in battery must report mismatches on
    the guard outcomes and on InOut's effects, and only on requests served
    by the resolver or on reports that Eva derives from its results."""
    path = evidence / "control-wrong-producer-plugins.jsonl"
    if not path.exists():
        return {"control": "plugins-perturbation", "result": "NOT RUN"}
    _, ref_calls, _ = load(evidence / f"{PLUGIN_FIXTURE}.reference.jsonl")
    _, calls, _ = load(path)
    rows = compare_calls(ref_calls, calls)
    mismatches = [r for r in rows if r["disposition"] == "MISMATCH"]
    outside = [
        r["id"]
        for r in mismatches
        if r["expect"] != "resolver" and r["family"] not in DERIVED_FAMILIES
    ]
    families = sorted({r["family"] for r in mismatches})
    ok = "guards" in families and any(f.startswith("inout-") for f in families) and not outside
    return {
        "control": "plugins-perturbation",
        "expected": {
            "families": "guards and inout-*",
            "outside_resolver_or_derived": [],
        },
        "observed": {
            "mismatches": [r["id"] for r in mismatches],
            "families": families,
            "outside_resolver_or_derived": outside,
        },
        "result": "PASS" if ok else "FAIL",
    }


def inout_reads(rows):
    return sum(
        r["count"]
        for r in rows
        if r["reader"].startswith("Eva.Results.") and r["caller"].startswith("Inout")
    )


def collection_control(evidence, fixtures):
    """When the hit log records, InOut takes the state at the start of each
    call, Top during the analysis, without a request: the candidates make
    no collection read on InOut's behalf through Eva.Results. On the legacy
    path, the same driver sees that read."""
    path = evidence / "control-legacy-path.jsonl"
    if not path.exists():
        return {"control": "inout-collection", "result": "NOT RUN"}
    candidates = {f["fixture"]: inout_reads(f["collection"]) for f in fixtures}
    legacy = inout_reads(collection(path))
    ok = legacy > 0 and not any(candidates.values())
    return {
        "control": "inout-collection",
        "expected": {"candidates": 0, "legacy_path": ">0"},
        "observed": {"candidates": candidates, "legacy_path": legacy},
        "result": "PASS" if ok else "FAIL",
    }


def native_control(fixtures):
    """In one process, the legacy reference and the candidate give natively
    equal models and values and equal text answers; the reference resolves
    nothing, and every request expected on the resolver is resolved. The
    snapshot requests, whose intervening analysis adds an assigns clause to
    the AST, are compared across processes only."""
    observed, ok = {}, True
    for f in fixtures:
        native = f["native"]
        if native is None:
            observed[f["fixture"]] = "NOT RUN"
            ok = False
            continue
        # The snapshot requests run a new analysis, which changes the AST:
        # only the comparison across processes covers them.
        compared = native["resolved"]
        not_compared = sorted(
            r["id"] for r in f["calls"] if r["id"] not in compared and r["family"] != "snapshot"
        )
        resolver_ids = {
            r["id"] for r in f["calls"] if r["expect"] == "resolver" and r["id"] in compared
        }
        unresolved = [i for i in resolver_ids if compared[i] == 0]
        summary = native["summary"] or {}
        observed[f["fixture"]] = {
            "compared": summary.get("compared"),
            "differing": native["differing"],
            "text_differing": native["text_differing"],
            "reference_resolved": native["reference_resolved"],
            "unresolved": sorted(unresolved),
            "not_compared": not_compared,
        }
        ok &= bool(summary.get("compared")) and summary.get("differing") == 0
        ok &= not native["differing"] and native["reference_resolved"] == 0
        ok &= not native["text_differing"] and not unresolved and not not_compared
    return {
        "control": "native-equality",
        "expected": {
            "differing": 0,
            "text_differing": [],
            "reference_resolved": 0,
            "unresolved": [],
            "not_compared": "snapshot requests only",
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


def independence_control(fixtures):
    """The reference is fresh-only and takes the legacy path."""
    wrong = [
        f["fixture"]
        for f in fixtures
        if f["reference"]["config"].get("-eva-memexec") != "false"
        or f["reference"]["config"].get("-eva-hit-log") != "false"
        or f["reference"]["guard"] != "off"
    ]
    return {
        "control": "reference-independence",
        "expected": {"memexec": "false", "hit_log": "false", "guard": "off"},
        "observed": {"other_reference": wrong},
        "result": "PASS" if not wrong else "FAIL",
    }


PARITY = "control-parity"
PROGRESS = re.compile(
    r"computing for function (?P<body>\w+)|Reusing old results for call to (?P<reuse>\w+)"
)
# For each fixture of the parity control: the analyses of f on the legacy
# path with memexec, and InOut's logic inputs for each call to f.
PARITY_FIXTURES = {
    "pre-label": ({"body": 2, "reuse": 0}, ["ANYTHING(origin:Unknown)"]),
    "precondition": ({"body": 2, "reuse": 1}, ["\\nothing"]),
}


def analyses(log, function):
    """How Eva interpreted the calls to [function], from its own progress
    messages: bodies analyzed and calls served from the memexec cache."""
    counts = {"body": 0, "reuse": 0}
    for m in PROGRESS.finditer(log.read_text()):
        for kind in counts:
            if m.group(kind) == function:
                counts[kind] += 1
    return counts


def parity_control(evidence):
    """InOut's answers and memexec admission. In both fixtures, the input of a
    call to f differs from the entry that survives its precondition. With
    memexec, the legacy path and the hit log must give the same answers,
    InOut's included, and Eva must interpret the calls to f in the same
    way. The legacy path must exercise each case. In pre-label.c, the
    assertion of f reads *p in the Pre state: its logic inputs are ANYTHING,
    and no call to f is reused. In precondition.c, the precondition of f
    reads bases that its body does not: the second call to f is reused."""
    observed, ok = {}, True
    for fixture, (expected_analyses, expected_logic) in PARITY_FIXTURES.items():
        paths = {side: evidence / f"{PARITY}-{fixture}.{side}" for side in ("legacy", "hit-log")}
        files = [Path(f"{p}{ext}") for p in paths.values() for ext in (".jsonl", ".log")]
        if not all(f.exists() for f in files):
            return {"control": "inout-memexec-parity", "result": "NOT RUN"}
        legacy, hit_log = (load(Path(f"{p}.jsonl"))[1] for p in paths.values())
        rows = compare_calls(legacy, hit_log)
        differing = [r["id"] for r in rows if r["disposition"] in ("MISMATCH", "MISSING")]
        counts = {side: analyses(Path(f"{p}.log"), "f") for side, p in paths.items()}

        def logic(answer):
            return answer.split("Logic inputs:")[-1].replace(";", " ").split()

        inout = {
            r["id"]: {"legacy": logic(r["expected"]), "hit-log": logic(r["observed"])}
            for r in rows
            if r["family"] == "inout"
        }
        exercised = (
            len(inout) == sum(expected_analyses.values())
            and all(v["legacy"] == expected_logic for v in inout.values())
            and counts["legacy"] == expected_analyses
        )
        ok = ok and exercised and not differing and counts["hit-log"] == counts["legacy"]
        observed[fixture] = {
            "differing": differing,
            "logic_inputs": inout,
            "analyses_of_f": counts,
        }
    return {
        "control": "inout-memexec-parity",
        "expected": {
            fixture: {
                "differing": [],
                "logic_inputs": logic_inputs,
                "analyses_of_f": {"legacy": counts, "hit-log": "same"},
            }
            for fixture, (counts, logic_inputs) in PARITY_FIXTURES.items()
        },
        "observed": observed,
        "result": "PASS" if ok else "FAIL",
    }


def accounting_control(fixtures):
    """Every logged read belongs to the execution or to one call, and the
    reference logs none."""
    unbalanced = []
    for f in fixtures:
        ref, cand = f["accounting"]["reference"], f["accounting"]["candidate"]
        if not (
            ref
            and cand
            and ref["logged"] == 0
            and cand["logged"] == cand["attributed"]
            and cand["attributed"]
            == f["execution_reads"] + sum(r["legacy_reads"] for r in f["calls"])
        ):
            unbalanced.append(f["fixture"])
    return {
        "control": "read-accounting",
        "expected": {"unbalanced": []},
        "observed": {"unbalanced": unbalanced},
        "result": "PASS" if not unbalanced else "FAIL",
    }


def zero_read_gate(fixtures):
    execution = sum(f["execution_reads"] for f in fixtures)
    calls = sum(
        1 for f in fixtures for r in f["calls"] if r["disposition"] in ("LEGACY", "UNOBSERVED")
    )
    failed = [f["fixture"] for f in fixtures if not (f["gate"] or {}).get("passes")]
    return execution == 0 and calls == 0 and not failed, {
        "execution_reads": execution,
        "legacy_calls": calls,
        "failed_gates": failed,
    }


def gate_control(evidence, gate_passes):
    """compare.py --require-zero-reads must exit 1 exactly when the gate
    fails on the same evidence."""
    path = evidence / "zero-read-gate.status"
    expected = 0 if gate_passes else 1
    if not path.exists():
        return {"control": "zero-read-gate-exit", "result": "NOT RUN"}
    status = int(path.read_text())
    return {
        "control": "zero-read-gate-exit",
        "expected": {"status": expected},
        "observed": {"status": status},
        "result": "PASS" if status == expected else "FAIL",
    }


def one_line(text):
    if text is None:
        return "—"
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return "; ".join(lines).replace("|", "\\|")


def markdown(report):
    out = ["# State-query acceptance report", ""]
    env = report["environment"]
    out += [
        f"- Revision: `{env.get('revision')}` ({env.get('worktree')})",
        f"- Command: `{env.get('command')}`",
        f"- Candidate options: `{env.get('candidate-options')}`",
        f"- Replay: `bash plugins/inout/prototype-state-query/" f"acceptance.sh`",
        f"- Zero-read gate: {'PASS' if report['gate']['passes'] else 'FAIL'} "
        f"`{json.dumps(report['gate']['observed'])}`",
        "",
    ]
    out += [
        "## Controls",
        "",
        "| Control | Expected | Observed | Result |",
        "| --- | --- | --- | --- |",
    ]
    for c in report["controls"]:
        out.append(
            f"| {c['control']} | `{json.dumps(c.get('expected'))}` | "
            f"`{json.dumps(c.get('observed'))}` | {c['result']} |"
        )
    for f in report["fixtures"]:
        out += ["", f"## {f['fixture']}", ""]
        out += [
            f"- Plugins: {', '.join(f['plugins'])}" f" (same in both runs: {f['same_plugins']})"
        ]
        for i in f["inputs"]:
            out.append(f"- Input: `{i['path']}` sha256 `{i['sha256']}`")
        for side in ("reference", "candidate"):
            cfg = " ".join(f"{k}={v}" for k, v in f[side]["config"].items())
            out.append(f"- {side.capitalize()}: guard={f[side]['guard']} " f"`{cfg}`")
        out += [
            "",
            "| Scope | Entries | Reads | Resolutions | Registrations |",
            "| --- | --- | --- | --- | --- |",
        ]
        for sc in f["scopes"]:
            regs = ", ".join(f"{k}: {v}" for k, v in sc["registrations"].items())
            out.append(
                f"| {sc['phase']} | {sc['entries']} | {sc['reads']} | "
                f"{sc['resolutions']} | {regs} |"
            )
        out += [
            "",
            "| Phase | Reader | Access | Store | Reads | Caller |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for e in f["execution"]:
            out.append(
                f"| {e['phase']} | {e['reader']} | {e['access']} | "
                f"{e['store']} | {e['count']} | {e['caller'] or '—'} |"
            )
        native = f["native"]
        if native:
            summary = native["summary"] or {}
            out += [
                "",
                f"- Native equality: {summary.get('compared')} models and values "
                f"compared, differing: {native['differing'] or 'none'}",
            ]
        out += [
            "",
            "| Call | Expect | Expected | Observed | Legacy reads | Resolved | " "Disposition |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for r in f["calls"]:
            readers = "<br>".join(r["readers"])
            visits = "<br>".join(r["visits"])
            out.append(
                f"| `{r['id']}` | {r['expect']} | {one_line(r['expected'])} | "
                f"{one_line(r['observed'])} | {r['legacy_reads']} "
                f"{readers} | {r['resolved']} {visits} | {r['disposition']} |"
            )
    return "\n".join(out) + "\n"


def environment(evidence):
    env = {}
    path = evidence / "environment.txt"
    for line in path.read_text().splitlines() if path.exists() else []:
        key, _, value = line.partition(" ")
        if key == "plugins":
            env.setdefault("plugins", []).append(value)
        else:
            env[key] = value
    return env


def main(argv):
    flags = {"--require-zero-reads", "--no-write"}
    require_zero = "--require-zero-reads" in argv
    args = [a for a in argv if a not in flags]
    evidence, fixtures = Path(args[0]), args[1:]
    report = {
        "environment": environment(evidence),
        "fixtures": [fixture_report(evidence, name) for name in fixtures],
    }
    gate_passes, gate_observed = zero_read_gate(report["fixtures"])
    report["gate"] = {"passes": gate_passes, "observed": gate_observed}
    controls = [control_report(evidence, phase) for phase in CONTROLS]
    controls.append(comparator_control(evidence))
    controls.append(continuous_trap_control(report["fixtures"]))
    controls.append(continuous_legacy_control(evidence))
    controls.append(tail_probe_control(evidence))
    controls.append(sensitivity_control(evidence, report["fixtures"]))
    controls.append(registration_control(report["fixtures"]))
    controls.append(store_check_control(evidence, fixtures))
    controls.append(accounting_control(report["fixtures"]))
    controls.append(independence_control(report["fixtures"]))
    controls.append(resolver_control(report["fixtures"]))
    controls.append(native_control(report["fixtures"]))
    controls.append(perturbation_control(evidence))
    controls.append(selection_control(report["fixtures"]))
    controls.append(selection_perturbation_control(evidence))
    controls.append(plugin_perturbation_control(evidence))
    controls.append(export_payload_control(evidence))
    controls.append(snapshot_control(report["fixtures"]))
    controls.append(collection_control(evidence, report["fixtures"]))
    controls.append(parity_control(evidence))
    if not require_zero:
        controls.append(gate_control(evidence, gate_passes))
    report["controls"] = controls
    if "--no-write" not in argv:
        (evidence / "report.json").write_text(json.dumps(report, indent=1))
        (evidence / "report.md").write_text(markdown(report))
    failing = {"MISMATCH", "MISSING"}
    failed = require_zero and not gate_passes
    for f in report["fixtures"]:
        counts = {}
        for r in f["calls"]:
            counts[r["disposition"]] = counts.get(r["disposition"], 0) + 1
            failed |= r["disposition"] in failing
        failed |= not (f["same_plugins"] and f["same_inputs"])
        summary = " ".join(f"{k}={v}" for k, v in sorted(counts.items()))
        print(f"{f['fixture']}: {summary}")
    for c in controls:
        print(f"{c['control']}: {c['result']}")
        failed |= c["result"] != "PASS"
    print(f"zero-read gate: {'PASS' if gate_passes else 'FAIL'} {json.dumps(gate_observed)}")
    if "--no-write" not in argv:
        print(f"Report: {evidence / 'report.md'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
