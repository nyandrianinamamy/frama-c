# Tests of `-eva-hit-log` and their observer

`hit_log_observer.ml` is loaded by every test of this directory, and by
`dev/hit-log-suite.py` over the tests of Eva. It analyses the program three
times: the current project with `-eva-hit-log`, a copy without memexec (the
reference), and a copy with memexec and without recording. It then asks
`Eva.Results` the same requests in the three projects and gives each answer
of the recording run a verdict against the reference: equal, covers, more
precise, OMITS, unavailable or unresolved. The comment at the top of the
file lists everything it prints.

It observes the programs of the tests of Eva only: it refuses input files
outside a `plugins/eva/tests` directory or a share directory of Frama-C,
because the reference run without memexec takes hours on a case study.
`HIT_LOG_OBSERVER_ANY_PROGRAM=1` lifts this.

## Comparing states across projects

A verdict compares states of different projects. Every change to the
observer keeps these invariants; a review of a change checks each of them.
Each was broken once, and the test named beside it is its regression.

1. **Allocated blocks are matched by their creation, never by name.** Eva
   numbers allocated bases in the order of creation, which differs between
   runs. A block's key is the callstack of the allocating call and its rank
   on that callstack (`key`, `matching`). A key held by several blocks, a
   callstack that creates a different number of blocks in the two runs, or
   an unmatched block alike to an unmatched block of the other run makes the
   blocks unresolved. Tests: `alloc_sites`, `alloc_pairwise`,
   `alloc_unresolved`.
2. **Strength is kept.** A weak base summarises several blocks; renaming
   erases the difference (`rename`). Strong in the source and weak in the
   target: only the inclusion of the reference in the answer is tested
   (covers or OMITS). Weak in the source and strong in the target:
   unresolved. Test: `alloc_strength`.
3. **Extents are equal before contents are compared.** Substitution erases
   validity (`min_alloc`, `max_alloc`, `max_allocable`); a pair whose
   extents differ is unresolved (`rename`). Test: `alloc_bounds`
   (`check_bounds`).
4. **A block's descriptor is captured while its own project is current.**
   Validity and weakness are mutable and belong to each project: `capture`
   runs under `Project.on` of the run that owns the base, before matching.
   Test: `alloc_bounds` (`check_prefix`).
5. **A structure keyed by bases holds the bases of one project.** The copies
   of a base in two projects have the same identifier, so `Base.equal` holds
   and a `Base.Hptset` or `Base.Hashtbl` mixing them returns either copy.
   Allocation origins are kept per run (`allocations_of`); matching works
   on the captured `block` records. Test: `alloc_bounds` (`check_prefix`).
6. **Renaming, normalisation and inclusion run with the target project
   current.** `replace_base` merges pointer fragments by the strength of the
   target block, and `is_included` builds default offsetmaps: both finish in
   the target project (`compare_pair`). Test: `alloc_bounds`
   (`check_pointer_fragments`).
7. **An undecided match gives "unresolved", never "equal".** The observer
   fails safe: `verdict` checks unresolved bases before any inclusion.
   Tests: `alloc_unresolved`, `alloc_strength`.

`alloc_bounds` runs the unit checks of `HIT_LOG_OBSERVER_CHECK_BOUNDS`
instead of an observation. The other controls, `HIT_LOG_OBSERVER_ALLOC_*`
and `HIT_LOG_OBSERVER_UNAVAILABLE`, make a run differ from Eva in a known way,
as negative controls of the verdicts; see "Controls" in the observer.
