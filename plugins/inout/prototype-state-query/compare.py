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

Each call also states the path expected to serve it (legacy, resolver or
none); the resolver and sensitivity controls check it against the reads and
resolutions the candidate recorded. The zero-read gate passes when no call
is LEGACY or UNOBSERVED and the candidates logged no read during the
execution either. The exit status is 1
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
        "differing": [r["id"] for r in rs if r["kind"] == "native" and not r["equal"]],
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
    """The guard sees reads on every request still served by the legacy
    store, and none on a request that reads neither store, such as a
    supplied state. Requests the candidate did not make are left out."""
    rows = [r for r in fixture["calls"] if r["disposition"] != "MISSING"]
    legacy = [r for r in rows if r["expect"] == "legacy"]
    silent = [r["id"] for r in legacy if r["legacy_reads"] == 0]
    unread = [r for r in rows if r["expect"] == "none"]
    noisy = [r["id"] for r in unread if r["legacy_reads"] or r["resolved"]]
    ok = legacy and unread and not silent and not noisy
    return {
        "control": "guard-sensitivity",
        "expected": {"legacy_without_reads": [], "unread_with_reads": []},
        "observed": {
            "legacy_calls": len(legacy),
            "legacy_without_reads": silent,
            "unread_calls": len(unread),
            "unread_with_reads": noisy,
        },
        "result": "PASS" if ok else "FAIL",
    }


def resolver_control(fixtures):
    """Every request on a supplied stack is served by the resolver, with no
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


def inout_reads(rows):
    return sum(
        r["count"]
        for r in rows
        if r["reader"].startswith("Eva.Results.") and r["caller"].startswith("Inout")
    )


def collection_control(evidence, fixtures):
    """InOut collects from the input that Eva passes to its hook: the
    candidates make no collection read on InOut's behalf through
    Eva.Results. On the legacy path, the same driver sees that read."""
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
    equal models and values; the reference resolves nothing, and every
    supplied-stack request of the candidate is resolved."""
    observed, ok = {}, True
    for f in fixtures:
        native = f["native"]
        if native is None:
            observed[f["fixture"]] = "NOT RUN"
            ok = False
            continue
        resolver_ids = {r["id"] for r in f["calls"] if r["expect"] == "resolver"}
        unresolved = [i for i in resolver_ids if native["resolved"].get(i, 0) == 0]
        summary = native["summary"] or {}
        observed[f["fixture"]] = {
            "compared": summary.get("compared"),
            "differing": native["differing"],
            "reference_resolved": native["reference_resolved"],
            "unresolved": sorted(unresolved),
        }
        ok &= bool(summary.get("compared")) and summary.get("differing") == 0
        ok &= not native["differing"] and native["reference_resolved"] == 0
        ok &= not unresolved
    return {
        "control": "native-equality",
        "expected": {"differing": 0, "reference_resolved": 0, "unresolved": []},
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


PRE_LABEL = "control-pre-label"


def pre_label_control(evidence):
    """Expected difference. The legacy path reads the input of a call from
    the store during the analysis, gets Top, and InOut's logic inputs of
    \\at(*p, Pre) are ANYTHING. With the input of the invocation, they are
    a and p. Only InOut's answers may differ."""
    ref, cand = (
        evidence / f"{PRE_LABEL}.reference.jsonl",
        evidence / f"{PRE_LABEL}.candidate.jsonl",
    )
    if not (ref.exists() and cand.exists()):
        return {"control": "pre-label-difference", "result": "NOT RUN"}
    rows = compare_calls(load(ref)[1], load(cand)[1])
    differing = [r for r in rows if r["disposition"] in ("MISMATCH", "MISSING")]

    def zone(answer):
        return answer.split("Logic inputs:")[-1].replace(";", " ").split()

    logic = {
        r["id"]: {"reference": zone(r["expected"]), "candidate": zone(r["observed"])}
        for r in differing
        if r["family"] == "inout"
    }
    ok = len(logic) == len(differing) == 1 and all(
        v["reference"][:1] == ["ANYTHING(origin:Unknown)"] and v["candidate"] == ["a", "p"]
        for v in logic.values()
    )
    return {
        "control": "pre-label-difference",
        "expected": {
            "differing": "one InOut call",
            "reference": "ANYTHING",
            "candidate": "a; p",
        },
        "observed": {"differing": [r["id"] for r in differing], "logic_inputs": logic},
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
    return execution == 0 and calls == 0, {
        "execution_reads": execution,
        "legacy_calls": calls,
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
    control_fixture = next(f for f in report["fixtures"] if f["fixture"] == CONTROL_FIXTURE)
    controls.append(sensitivity_control(control_fixture))
    controls.append(accounting_control(report["fixtures"]))
    controls.append(independence_control(report["fixtures"]))
    controls.append(resolver_control(report["fixtures"]))
    controls.append(native_control(report["fixtures"]))
    controls.append(perturbation_control(evidence))
    controls.append(collection_control(evidence, report["fixtures"]))
    controls.append(pre_label_control(evidence))
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
