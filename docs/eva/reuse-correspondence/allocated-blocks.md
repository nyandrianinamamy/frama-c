# Allocated blocks

The entries below cover the refusals of the collector on allocated blocks:
blocks created by `malloc`, `calloc`, `realloc`, `alloca` and variable-length
arrays (`Base.Allocated`). The validity record of such a block
(`Base.Variable`) and the type and name of its variable change during an
analysis. A body whose analysis depends on them, or changes them, is refused.

The fixture
[`allocation-refusals.t`](../../../plugins/eva/tests/utils/allocation-refusals.t/run.t)
holds the regressions cited below. Its OCaml module asserts the fields of each
observation; the cram file records the first reason of each body.

## Allocated blocks among the observed blocks

**Claim.** The collector refuses a body with `allocated-block` when an
allocated block is among the blocks read or written, the locations computed
before invalid offsets are trimmed, or the blocks designated by a value the
body reads without dereferencing it. The designated values include those read
by the evaluation of ACSL terms and predicates, including the `requires`
clauses of the body checked at the call site, and the finite sets of a
garbled value. A set of targets that is Top refuses with `footprint-top`.

**Kind.** OCaml obligation.

**Depends on.** [Whole-block observations and exits](body-access.md#whole-block-observations-and-exits).

**Symbols.** `Body_access.check_bases`, `Body_access.check_location`,
`Body_access.designate`, `Eval_terms.find_indeterminate`,
`Eval_terms.find_logic_var`, `Eval_terms.forall_in_over_location`,
`Eval_terms.forall_in_under_location`, `Body_access.at_call_site`,
`Transfer_logic.Make.check_fct_preconditions`.

**Argument.** The slice of issue #41 checks every set the observation reports:
`check_bases` refuses an allocated base and a Top set. `Cvalue.V.get_bases`
returns the bases of a garbled value whose origin set is finite, and Top
otherwise. This ticket adds the values that the logic evaluation reads from
the state: the value of an lvalue of a term (`find_indeterminate`), the
value of a C-typed logic variable, and the values of the location tested by
`\initialized` or `\dangling`. The slice builds no key of an entry; a key
drawn from the observation would hold only blocks of these sets.

The `requires` clauses of a body are checked with its recording suspended
([Refusal and reporting](body-access.md#refusal-and-reporting)), but a hit
skips them with the body. `check_fct_preconditions` therefore runs them
under `at_call_site`, which keeps the allocation family: a designated
allocated block or Top set refuses, a read of allocation metadata refuses
and adds its owner, and the reasons of the allocation effects are kept. The
blocks these clauses read, write or designate are not added to the sets.

**Evidence.** Execution. `copy` (`q = p`, where `p` points to an allocated
block) reads `copy allocated-block`; the module asserts R = {p}, W = {q}, an
allocated block among the designated blocks and no allocation effect.
`logic_only` reads an allocated block only through `/*@ assert p != \null; */`
and reads `logic_only: allocated-block among [annotation allocated-block
allocation-metadata]`. On the validity replay of the inventory ticket
(`equality.c`, a comparison of two pointers to allocated blocks), `equal_live`
reads `equal_live allocated-block` twice. A probe module that prints all
the reasons, run on the same programs at the base revision `5151231fd4`, gave
`allocated-block` for `copy` and `equal_live` already, and only
`annotation` for `logic_only`; the module now also asserts that
`equal_live` reads allocation metadata and has an owner. In `requires.c`,
three bodies that do not access the block that their clause `\valid(p)`,
`\initialized(p)` or `\block_length(p) >= sizeof(int)` reads are refused
with `allocated-block` and the owner `__malloc_main_l18`; the module asserts
that R is empty and W = {x}. Before `at_call_site`, at revision
`99a0c401f2`, the probe module gave no reason for these bodies.

**Open.** None for this claim.

## Allocation effects

**Claim.** The collector refuses a body that performs an allocation, a
reallocation or a deallocation, or that updates a validity record, with the
reasons `allocation`, `reallocation`, `deallocation` and `validity-mutation`.
The detection follows what the builtins do, not their reported assigns. It
covers variable-length arrays, `alloca`, the automatic deallocation of the
blocks of a call at its return, and the updates made by the widening of a
memory map.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Builtins_malloc.alloc_fresh`, `Builtins_malloc.alloc_by_stack`,
`Builtins_malloc.alloc_weakest_base`, `Builtins_malloc.free_aux`,
`Builtins_malloc.realloc_builtin_aux`,
`Builtins_malloc.deallocates_at_return`,
`Compute_functions.Make.compute_and_cache_call`,
`Base.update_variable_validity`, `Base.on_validity_update`.

**Argument.** Each builtin refuses at the operation, when it runs: the three
functions that return a base for an allocation (a new base, a base reused
from the same call stack, and the single weak base of the imprecise mode),
the release `free_aux` (also used by `realloc`, `__fc_vla_free` and the
automatic deallocation) and `realloc` on a pointer it accepts. A reused
base is an allocation even when no base is created: the state gains its block.
`__fc_vla_alloc` and `alloca` go through the same functions. The automatic
blocks of a call are released by the caller at the return; inside the
recorder of the callee, after its body, `compute_and_cache_call` refuses the
callee with `deallocation` when the allocation registry holds an automatic
block for its call stack. The registry is read when the body ends, so a call
that only returns, on a call stack that allocated before, is also refused.
The release itself, in the caller, refuses the caller.

`Base.update_variable_validity` is the only function that changes a
validity record. The kernel runs the observers of `on_validity_update` before
each update, and the collector refuses the active body. The callers are the
reuse of a base by an allocation, which also changes the type and the name of
its variable, and the widening of a memory map, which increases the maximal
validity of a weak block whose binding changed.

**Evidence.** Execution, in `effects.c` and `widening.c`: `allocate`,
`release`, `resize` (`realloc`), `vla`, `scratch` (`alloca`) and
`scratch_once` read `allocation`, `deallocation`, `reallocation`,
`allocation`, `allocation` and `allocation`. The second call of
`scratch_once`, which returns without allocating on a call stack whose block
is still registered, reads `deallocation` and is the only reason. `fill`
writes a value to a weak allocated block in a loop, allocates nothing, and
reads `fill validity-mutation`. A probe module that prints all the reasons,
run on the same programs at the base revision, gave `builtin` as the first
reason of each of these bodies, no reason for the second call of
`scratch_once`, and `allocated-block` and `side-table` for `fill`.

**Open.** Memexec still stores a body that the collector refuses: in
`release.c`, the first call to `release` reads `storage: stored (entry 1);
collector: refused (deallocation)` and the second call is a memexec hit. The
mechanism that stores entries from the collector must not reproduce this.

## Owners of allocation metadata

**Claim.** The collector refuses a body with `allocation-metadata` when its
analysis reads the validity, the type, the size or the alignment of an
allocated block, including in an operation that the analyzer selects and the
program does not: a binding visited by a widening, a default binding, or the
bound of a target read by the widening of a pointer offset. The blocks read
are the owners of the observation. A memoised result that can depend on this
metadata either reports its owners on a hit as on a miss, or depends only on
data that does not change, except the tags of the nodes of offsetmaps (see
[Read paths of the validity record](#read-paths-of-the-validity-record)).

**Kind.** OCaml obligation.

**Depends on.** [Allocation effects](#allocation-effects).

**Symbols.** `Base.validity`, `Base.is_weak`, `Base.typeof`,
`Base.bits_sizeof`, `Base.alignof`, `Base.metadata_read`,
`Base.on_metadata_read`, `Cvalue.Default_offsetmap.default_offsetmap`,
`Body_access.Result.owners`.

**Argument.** The kernel accessors of an allocated base run the observers of
`on_metadata_read`. The collector adds the refusal and the base to the owners
of the active body. The functions that match the `Allocated` constructor
without an accessor call `Base.metadata_read`. The other reads of a validity
record go through a validity extracted by one of these accessors. The paths
are listed in [the next section](#read-paths-of-the-validity-record).

The observation is conservative. A write to an allocated block reads its
metadata in the collector's own location queries, and the body is already
refused for `allocated-block`. The exit sets are computed with recording
suspended. The cache lookup and storage run with recording suspended: they
are not part of the body.

**Evidence.** Execution, in `widening.c`: the loop of `shift` changes
integers only. Its first call, before any allocation, reads `shift before
the allocation: no owner`; its second call, after `keep = malloc(...)`,
reads `shift after the allocation: owners __malloc_main_l43`, because the
widening visits the bindings common to both states, including the allocated
one. `quiet` converges before the widening and reads `quiet would-store`
after the allocation. At the base revision, the probe module gave only
`side-table` for both calls of `shift`.

**Open.** The trace that lists the exercised paths below was produced by a
module that is not part of the test suite.

## Refusals inherited by an enclosing body

**Claim.** A body inherits the reasons `reallocation`, `allocation`,
`deallocation`, `validity-mutation`, `allocated-block` and
`allocation-metadata`, and the owners, of every body analysed during its own
analysis.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Body_access.capture`, `Body_access.inherited`.

**Argument.** When a body's observation completes, `capture` adds these
reasons and the owners to the recorder of the enclosing body, before the
observers run. An enclosing body is already refused for `nested-call`; the
inherited reasons make the cause visible and keep the owners with the body
that will be stored when child observations are composed. A call answered by
a memexec hit runs no body, and passes nothing on: the enclosing body is
refused for the nested call only.

**Evidence.** Execution: `main` of `effects.c` calls the bodies above and
reads `main reallocation`; the module asserts the three effect reasons and a
non-empty set of owners. In `release.c`, `main` reads `main allocation`.

**Open.** None for this claim.

## Read paths of the validity record

**Claim.** The table lists every transitive read of the validity record or of
the type of an allocated block reachable from the analysis of a body by the
cvalue domain and the kernel memory maps, with its treatment. Where the audit
is not conclusive, the treatment is a refusal, except for the tags of the
nodes of offsetmaps that the body does not build (see Open).

**Kind.** OCaml obligation.

**Depends on.** [Owners of allocation metadata](#owners-of-allocation-metadata).

**Argument.** A read of the metadata of an allocated base goes through an
accessor of `Base`, which reports it at the read, or matches the `Allocated`
or `Variable` constructor, or uses a validity extracted earlier by an
accessor. A memo is the only way to use the result of a read without
repeating it. The rows list the constructor matches and the extracted
validities, found by searching `src/kernel/services/abstract_interp` and
`plugins/eva/src` for the constructors, the fields of the record and the
accessors; the callers of the accessors that were exercised; and the
persistent memos of these directories.

Each row gives the path, what it reads, its treatment and its
evidence. "Exercised" means that a tracing module, registered with
`Base.on_metadata_read` and `Base.on_validity_update`, printed the call chain
of the path while recording a body, at revision `4cbfeffd6b`, on the
programs of the fixture and on a loop that advances a pointer through an
allocated block. "Inspected" means source inspection only.

Accessors of `Base`:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Base.validity`, `Base.is_weak`, `Base.typeof`, `Base.bits_sizeof`, `Base.alignof` | validity, weakness, type | reported | exercised (`validity`, `is_weak`, `alignof`) |
| `Base.valid_offset`, `Base.is_valid_offset` | validity, through `Base.validity` | reported | exercised |
| `Base.is_weak_validity`, `Base.valid_range`, `Base.pretty_validity` | a validity given as argument | extracted by a reported accessor | inspected |
| `Base.update_variable_validity` | updates the record | `validity-mutation` | exercised |
| `Base.pretty`, `Base.to_varinfo` | name of the variable | text and identity, not metadata | inspected |

Kernel memory maps and values:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Lmap.add_binding`, `Lmap.find`, `Lmap.paste_offsetmap`, `Lmap.copy_offsetmap` | `Base.validity` of the target | reported | exercised |
| `Lmap.widen`, visit of the common bindings | `Base.is_weak`, `Base.validity` | reported | exercised (`shift`) |
| `Lmap.widen`, maximal validity of a weak block | updates the record | `validity-mutation` | exercised (`fill`) |
| `Cvalue.Default_offsetmap.default_offsetmap` | constructor of an allocated base | `Base.metadata_read` | exercised (in the allocation builtins) |
| `Addresses.cardinal_zero_or_one` | `Base.is_weak` | reported | exercised (through `Locations.cardinal_zero_or_one`, `Cvalue.forward_eq_int`, `Eval_op.add_if_singleton`, `Offsetmap` node tags) |
| `Map_lattice.With_Cardinality.find_lonely_key`, `find_lonely_binding` | `Base.is_weak` | reported | exercised (through `Cvalue.V.project_ival`, `Precise_locs`, the pointer comparisons of `Cvalue_forward`, `Eval_typ.offsetmap_matches_type`) |
| `Addresses.widen`, thresholds from the target | `Base.validity` | reported | exercised (pointer loop) |
| `Addresses.is_relationable`, `Addresses.cardinal` | `Base.validity`, `Base.is_weak` | reported | inspected |
| `Locations.valid_part`, `Locations.enumerate_valid_bits_under_over`, `Locations.interval_from_ival_under` | `Base.valid_offset`, `Base.validity` | reported | exercised |
| `Locations.is_valid`, `Locations.valid_cardinal_zero_or_one` | `Base.is_valid_offset`, `Base.is_weak` | reported | inspected |
| `Offsetmap` and `Tr_offset` functions with a `~validity` argument, `Offsetmap.size_from_validity` | a validity given as argument | extracted by a reported accessor in `Lmap` | inspected |
| `Lmap_bitwise` default bindings | `Base.validity` | reported | inspected |

Eva:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Cvalue_forward`: pointer comparison, alignment, `nearly_valid_bits` | `Base.is_valid_offset`, `find_lonely_key`, `Base.alignof`, an extracted validity | reported | exercised (comparison, alignment) |
| `Main_locations`: validity of a location and its reduction | `Base.is_valid_offset`, `find_lonely_key` | reported | exercised |
| `Eval_op.add_if_singleton` | `Base.is_weak` | reported | exercised |
| `Eval_op.reduce_by_initialized_defined` | `Base.is_weak` | reported | inspected |
| `Eval_terms`, `\block_length` | `Base.validity` | reported | inspected |
| `Builtins_malloc`: sizes, initial contents, release, reallocation, weak check | `Base.validity`, `Base.is_weak`, constructor | reported, in a body refused for the effect | exercised |
| `Builtins_malloc.is_automatically_deallocated`, `Main_values` | constructor and kind of deallocation | immutable | inspected |
| `Builtins_malloc.update_variable_validity` | changes the type and the name of the variable | followed by `Base.update_variable_validity` in the same function | exercised |
| `Builtins_memory` (`memset`), `Cvalue.pretty_base_offsets_typ` | type of the variable through `Base.to_varinfo` | builtin refused; message text | inspected |
| `Auto_loop_unroll`, `Logic_inout` | the variable of a base | identity only | inspected |
| `Mem_exec` | `Base.validity` in `diff_base_full_zone` | outside recording | inspected |
| `Cvalue_init` | validity of globals | before any body | inspected |
| Other domains, `Concurrency`, Mthread | various | the body is refused at admission | inspected |

Windows where recording is suspended:

| Site | Runs | Treatment | Evidence |
| --- | --- | --- | --- |
| `Transfer_logic.Make.check_fct_preconditions` | `requires` clauses of the body | `at_call_site`: allocation family recorded | exercised (`requires.c`) |
| `Compute_functions.Make.compute_and_cache_call` | memexec lookup and storage, including `Mem_exec` reads of `Base.validity` | outside the body | inspected |
| `Body_access.capture` | computation of W_exit and W_sure; observers of the result | the collector's own work; observers must not change the analysis | inspected |
| `Cvalue_callbacks.run_hook` | call hooks | an unclassified hook refuses with `side-table`; the classified protocols do not change the analysis of the body | inspected |
| `Iterator` | `Async.yield` | no analysis | inspected |

Persistent memos:

| Memo | Depends on | Treatment | Evidence |
| --- | --- | --- | --- |
| `Offsetmap` node tag of a node the body builds (hash-consing) | `V.cardinal_zero_or_one`, hence `Base.is_weak`, of the node's value | read before the merge with the table: reported on a hit as on a miss | exercised |
| tags of nodes the body does not build, `Lmap` compositional bool | weakness of the bases when the content was first built | not refused; see below | inspected |
| `Lmap` inclusion and narrowing caches, over default bindings | default offsetmap of the base | size `max_allocable + 1`, which is immutable; the join of cvalue does not read default bindings | inspected |
| `lmap.widen` cache, without hints | thresholds of `Addresses.widen` | not used by the cvalue domain, which always passes hints; Mthread is refused | inspected |
| `Lmap_bitwise` join, inclusion and `fold_on_zone` caches | default bindings | size from `max_allocable` | inspected |
| `Addresses.contains_addresses_of_any_locals` cache | constructor of the base | immutable | inspected |
| `Offsetmap` join, inclusion, narrowing and `map2` caches | values; a hit returns nodes with their tags | values carry no metadata; tags as above | inspected |
| `Map_lattice`, `Int_Intervals` and `Addresses` binary caches | values and intervals only | no metadata | inspected |
| `Widen` hints per function, valuation of a transfer | no metadata; scope of one transfer | none needed | inspected |

The node tag of an offsetmap is computed in `nNode` from the weakness of the
bases of the node's value, before the node is merged with the hash-consing
table. The table ignores the tag when it compares nodes: a node built again
with the same content keeps the tag of its first construction. The read is
reported whenever the body builds a node, on a hit of the table as on a miss.
It is not reported for a node that the body takes from its input state or
from a hit of a binary cache of `Offsetmap` or `Lmap`. The tags feed
`Offsetmap.cardinal_zero_or_one`, the compositional bool of `Lmap`,
`Lmap.comp_prefixes` and `Lmap.find_prefix`, which `Partitioning_index.add`
uses to select the stored states that it compares by inclusion with a new
state. A new state whose subpart is indexed is compared only with the states
of the same subpart, so whether the state is kept can depend on the tags. A
base becomes weak only through `Base.update_variable_validity`, which
refuses a body that runs it: a tag that disagrees with the current weakness
of a base comes from a change made before the body. The audit is not
conclusive for these nodes, and the collector does not refuse them: a
refusal would cover every body whose states hold a pointer to an allocated
block.

For the default bindings: the two functions that create an allocated base
give it a `Variable` validity, and `Offsetmap.size_from_validity` sizes it
by `max_allocable`, which is immutable. Moreover, the inclusion of two
states reads the default binding only for a base bound in one state and not
the other. Within a body, every state comes from one entry state, and only an
allocation, a release or a nested call adds or removes an allocated binding;
each refuses.

**Evidence.** As in each row. The tracing module was run on `effects.c`,
`widening.c`, `equality.c` and the pointer loop. It printed 44 distinct call
chains of six frames; the table names the function of each, and the two
chains that start in `Body_access` are the collector's own location queries
on a written allocated block.

**Open.** The tags of the nodes that a body does not build are not
reported and do not refuse: this differs from the ticket, which asks for a
refusal where the audit is not conclusive. Their dependency is on changes of
weakness made before the body. `Partitioning_index.add` drops a new state
only after `Domain.is_included` holds for a stored state, so a stale tag can
only keep a state included in another one: the result stays sound, but can
differ from that of a fresh analysis. Between a producer and a lookup, the cache
must account for these changes, or the argument must show that the choices
of `Partitioning_index.add` do not change the result. `Partitioning_index`
also consults the tags of all the bindings, including blocks outside R;
whether a match on a projection of the input preserves its choices belongs to
the frame claim and is not argued here. The tracing module is not committed,
and the rows marked "inspected" have no regression.
