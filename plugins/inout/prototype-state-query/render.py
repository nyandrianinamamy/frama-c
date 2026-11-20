##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

"""Build a portable walkthrough from the captured Eva logs."""

import html
import json
from pathlib import Path
import sys

SCENARIOS = {
    "original": (
        "Two call sites",
        "The second call has a new g and hit-reuses the first function body.",
    ),
    "loop": (
        "One call site, two visits",
        "Both visits contribute to one callstack. Each visit has its own frame.",
    ),
    "read-before-write": (
        "Read before overwrite",
        "The two g values feed local t, so Eva runs the body twice.",
    ),
    "guard": (
        "Guard refinement",
        "The call frame has x in [0,10]. The guard restricts x to [0,4] at P.",
    ),
    "unreachable": (
        "Unreachable P",
        "Both invocation frames exist. Neither reaches P.",
    ),
    "partial-base": (
        "Part of a struct",
        "Before P, the body supplies s.a and the current frame supplies s.b.",
    ),
    "maybe-write": (
        "Conditional write",
        "A retained write slice and a pass-through reference eliminate the "
        "producer's stale g=4 from the hit-stack answer.",
    ),
    "maybe-write-goto": (
        "Explicit predecessor edges",
        "The same conditional update uses explicit transfers to the label.",
    ),
    "maybe-write-upstream": (
        "Earlier merge",
        "The immediate predecessor has already merged at h=2. Looking back "
        "across that independent assignment recovers the two alternatives.",
    ),
    "precondition": (
        "Precondition stages",
        "The input of each call is recorded before its precondition reduces "
        "z. The hit reuses a call whose precondition read another g: it gets "
        "z from its own input only.",
    ),
    "missing": (
        "Storage disabled",
        "Eva analyzes the body with statement storage disabled for f.",
    ),
}


def validate(name, lines):
    events = {}
    queries = {}
    inputs = {}
    phase = None
    query = None
    for raw in lines:
        if not raw.startswith("[query] "):
            continue
        line = raw.removeprefix("[query] ")
        words = line.split()
        match words:
            case ["phase", new_phase, option, *_]:
                phase = new_phase
                assert option == f"memexec={str(phase == 'hit').lower()}"
                events[phase] = []
            case ["event", _, stack, outcome]:
                events[phase].append((stack.removeprefix("stack="), outcome))
            case ["query", phase, scope, point]:
                query = queries[phase, scope, point] = {}
            case ["input", stack, "start-of-call", result]:
                inputs[phase, stack] = result
            case [point, "legacy", available, status, stacks]:
                query["public"] = (available, status, stacks)
            case [strategy, result] if result in {
                "EXACT",
                "OMITS_FRESH",
                "CONTAINS_FRESH",
            }:
                query[strategy] = result
            case _:
                pass

    def expect(phase, scope, point, method, result):
        key = phase, scope, point
        observed = queries[key].get(method)
        assert observed == result, (name, key, method, observed, result)

    # The inputs recorded on each stack are the state that a public request
    # answers at the start of the function on that stack.
    stacks = {(phase, stack) for phase in events for stack, _ in events[phase]}
    assert set(inputs) == stacks, (name, inputs, stacks)
    assert all(result == "EXACT" for result in inputs.values()), (name, inputs)

    if name == "precondition":
        validate_precondition(name, events, queries, expect)
        return

    if name == "missing":
        assert set(events) == {"missing"}
        assert len(events["missing"]) == 2
        assert all(outcome.startswith("Body/") for _, outcome in events["missing"])
        assert len(queries) == 6
        for (_, scope, _), results in queries.items():
            expected = "value(top-model)" if scope == "joined" else "top"
            assert results["public"] == (
                "available=false",
                f"status={expected}",
                "callstacks=0",
            )
        return

    assert set(events) == {"fresh", "hit"}
    a, b = (stack for stack, _ in events["fresh"])
    assert len({a, b}) == (1 if name == "loop" else 2)
    assert [stack for stack, _ in events["hit"]] == [a, b]
    for _, outcome in events["fresh"]:
        assert outcome.startswith("Body/")
    first, second = (outcome for _, outcome in events["hit"])
    assert first.startswith("Body/")
    if name == "read-before-write":
        assert second.startswith("Body/") and first != second
    else:
        assert second == first.replace("Body/", "Reuse/")

    assert len(queries) == 4 * len({a, b, "joined"})
    for phase in ("fresh", "hit"):
        for scope in {a, b, "joined"}:
            for point in ("before", "after"):
                b_before = phase == "hit" and scope == b and point == "before"
                conditional = name in {
                    "maybe-write",
                    "maybe-write-goto",
                    "maybe-write-upstream",
                }
                expected = "CONTAINS_FRESH" if b_before and conditional else "EXACT"
                expect(phase, scope, point, "bitwise", expected)
                expected = (
                    "CONTAINS_FRESH" if b_before and name == "maybe-write-upstream" else "EXACT"
                )
                expect(phase, scope, point, "split", expected)
                expect(phase, scope, point, "lookback", "EXACT")
                if name == "guard":
                    expect(phase, scope, point, "write-only", "CONTAINS_FRESH")
                if name == "unreachable":
                    public = queries[phase, scope, point]["public"]
                    assert public[0] == "available=true" and public[1] == "status=bottom"
    if name in {"original", "loop"}:
        for scope in (b, "joined"):
            for point in ("before", "after"):
                expect("hit", scope, point, "legacy", "OMITS_FRESH")
                expect("hit", scope, point, "producer", "OMITS_FRESH")
    if name == "partial-base":
        for scope in (b, "joined"):
            expect("hit", scope, "before", "whole-base", "CONTAINS_FRESH")

    if name in {"maybe-write", "maybe-write-goto", "maybe-write-upstream"}:
        joined = "\n".join(lines)
        assert "extra-alternatives=2 extra-offsetmaps=1 extra-pass-through=1" in joined
        expected = 1 if name == "maybe-write-upstream" else 0
        assert f"storage lookback-edges={expected}" in joined


def validate_precondition(name, events, queries, expect):
    """Three calls to f: a and b analyze the body, and no entry of c
    survives the precondition. With memexec, b reuses a."""
    a, b, c = (stack for stack, _ in events["fresh"])
    assert len({a, b, c}) == 3
    assert [stack for stack, _ in events["hit"]] == [a, b, c]
    assert all(outcome.startswith("Body/") for _, outcome in events["fresh"])
    first, second, third = (outcome for _, outcome in events["hit"])
    assert first.startswith("Body/") and third.startswith("Body/") and first != third
    assert second == first.replace("Body/", "Reuse/")
    assert len(queries) == 2 * 4 * 2
    for phase in ("fresh", "hit"):
        for scope in (a, b, c, "joined"):
            for point in ("before", "after"):
                # The frame of an analyzed body is the entry that survives its
                # precondition: its reconstruction is exact. The hit at b gets
                # z from its own input, which contains the fresh z >= 4; the
                # producer's z >= 9 would omit part of it.
                reused = phase == "hit" and scope in (b, "joined")
                for method in ("whole-base", "write-only", "bitwise", "split", "lookback"):
                    expect(phase, scope, point, method, "CONTAINS_FRESH" if reused else "EXACT")
                expect(phase, scope, point, "producer", "OMITS_FRESH" if reused else "EXACT")
                if phase == "hit":
                    expect(phase, scope, point, "legacy", "OMITS_FRESH" if reused else "EXACT")
        for point in ("before", "after"):
            public = queries[phase, c, point]["public"]
            assert public[1] == "status=bottom", (name, phase, point, public)


def walkthrough(prototype, evidence):
    cases = []
    for name, (title, description) in SCENARIOS.items():
        source = "original" if name == "missing" else name
        sections = {}
        phase = "analysis"
        section = None
        lines = (evidence / f"{name}.log").read_text().splitlines()
        try:
            validate(name, lines)
        except (AssertionError, KeyError, TypeError, ValueError) as error:
            raise SystemExit(f"{name}: unexpected replay result {error!r}") from error
        for line in lines:
            if line.startswith("[query] phase "):
                phase = line.split()[2]
                sections[phase] = []
                section = None
            elif line.startswith("[query] event "):
                section = [line.removeprefix("[query] ")]
                sections[phase].append(section)
            elif line.startswith("[query] query "):
                if not sections[phase] or sections[phase][-1][0] != "Queries":
                    sections[phase].append(["Queries"])
                section = sections[phase][-1]
                section.append(line.removeprefix("[query] "))
            elif section is not None:
                section.append(line.removeprefix("[query] "))
        cases.append(
            {
                "title": title,
                "description": description,
                "source": (prototype / f"{source}.c").read_text(),
                "steps": [
                    {"label": f"{phase.title()} · {step[0]}", "text": "\n".join(step)}
                    for phase, steps in sections.items()
                    for step in steps
                ],
            }
        )
    return cases


def main():
    prototype, evidence = map(Path, sys.argv[1:])
    cases = json.dumps(walkthrough(prototype, evidence), ensure_ascii=False)
    cases = cases.replace("<", "\\u003c")
    baseline = (evidence / "environment.txt").read_text().splitlines()[0]
    template = (prototype / "walkthrough-template.html").read_text()
    output = template.replace("__CASES__", cases).replace("__REVISION__", html.escape(baseline))
    (evidence / "walkthrough.html").write_text(output)


if __name__ == "__main__":
    main()
