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
as text: equal text means equal printed answers, and inclusion between
models is not checked. Each call gets one disposition:

  MATCH       equal answers, no legacy read during the call
  LEGACY      equal answers, served with legacy reads
  MISMATCH    different answers
  MISSING     the call is absent from one of the runs
  UNOBSERVED  equal answers, but the candidate's guard was off

The zero-read gate passes when no call is LEGACY or UNOBSERVED and the
candidates logged no read during the execution either. The exit status is 1
on any MISMATCH, MISSING or failed control, and also on a failed gate with
--require-zero-reads. --no-write skips writing report.md and report.json."""

import hashlib
import json
from pathlib import Path
import re
import sys

# Expected exit status, phase and reader of each trap control.
CONTROLS = {
    "request": (1, "request", "Eva.Results.get_cvalue_model"),
    "analysis": (1, "analysis", "Eva.Engine.register_state"),
    "collection": (1, "collection", "Eva.Summary.compute_fun_stats"),
    "post-analysis": (1, "post-analysis", "Eva.Eval_annots.mark_unreachable"),
    "initialization": (0, None, None),
}
CONTROL_FIXTURE = "legacy-reads"
TRAP_PREFIX = "legacy result-store read trapped: "


def load(path):
    records = [json.loads(line) for line in path.read_text().splitlines()]
    header = next(r for r in records if r["kind"] == "header")
    calls = [r for r in records if r["kind"] == "call"]
    execution = [r for r in records if r["kind"] == "execution"]
    return header, calls, execution


def accounting(path):
    records = [json.loads(line) for line in path.read_text().splitlines()]
    return next((r for r in records if r["kind"] == "accounting"), None)


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
        rows.append(
            {
                "id": call_id,
                "family": (exp or obs)["family"],
                "request": (exp or obs)["request"],
                "expected": exp and exp["answer"],
                "observed": obs and obs["answer"],
                "legacy_reads": len(reads),
                "readers": sorted(
                    {f"{r['phase']}/{r['reader']}/{r['access']}/{r['store']}" for r in reads}
                ),
                "disposition": disposition(exp, obs),
            }
        )
    return rows


def digest(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


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
        "accounting": {
            "reference": accounting(evidence / f"{name}.reference.jsonl"),
            "candidate": accounting(evidence / f"{name}.candidate.jsonl"),
        },
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


def sensitivity_control(fixture):
    """The guard sees reads on stored results and none on a supplied
    state. Requests the candidate did not make are left out."""
    rows = [r for r in fixture["calls"] if r["disposition"] != "MISSING"]
    supplied = [r for r in rows if r["family"] == "supplied-state"]
    stored = [r for r in rows if r["family"] != "supplied-state"]
    silent = [r["id"] for r in stored if r["legacy_reads"] == 0]
    ok = supplied and all(r["legacy_reads"] == 0 for r in supplied) and not silent
    return {
        "control": "guard-sensitivity",
        "expected": {"supplied_state_reads": 0, "stored_without_reads": []},
        "observed": {
            "supplied_state_reads": [r["legacy_reads"] for r in supplied],
            "stored_without_reads": silent,
        },
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
    return execution == 0 and calls == 0, {"execution_reads": execution, "legacy_calls": calls}


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
            "| Phase | Reader | Access | Store | Reads | Caller |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for e in f["execution"]:
            out.append(
                f"| {e['phase']} | {e['reader']} | {e['access']} | "
                f"{e['store']} | {e['count']} | {e['caller'] or '—'} |"
            )
        out += [
            "",
            "| Call | Expected | Observed | Legacy reads | " "Disposition |",
            "| --- | --- | --- | --- | --- |",
        ]
        for r in f["calls"]:
            readers = "<br>".join(r["readers"])
            out.append(
                f"| `{r['id']}` | {one_line(r['expected'])} | "
                f"{one_line(r['observed'])} | {r['legacy_reads']} "
                f"{readers} | {r['disposition']} |"
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
    control_fixture = next(f for f in report["fixtures"] if f["fixture"] == CONTROL_FIXTURE)
    controls.append(sensitivity_control(control_fixture))
    controls.append(accounting_control(report["fixtures"]))
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
