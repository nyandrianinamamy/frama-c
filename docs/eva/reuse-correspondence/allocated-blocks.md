# Allocated blocks

The entries below cover the refusals of the collector on allocated blocks:
blocks created by `malloc`, `calloc`, `realloc`, `alloca` and variable-length
arrays (`Base.Allocated`). The validity record of such a block
(`Base.Variable`) and the type and name of its variable change during an
analysis. A body whose analysis depends on them, or changes them, is refused.

The fixture
[`allocation-refusals.t`](../../../plugins/eva/tests/utils/allocation-refusals.t/run.t)
holds the regressions cited below. Its OCaml module asserts the fields of each
observation; the cram file records the reasons of each body. "Before the
fixes" below means revision `1333c8063f2cda041cf7c2f6b0de5e4f84708bcc`, the
reviewed state of this ticket rebased on the integration branch; "the base
revision" means `50dc2a31ff53bf181cbd6b9fa83aea3a8f445c8b`, the integration
branch before this ticket.

## Allocated blocks among the observed blocks

**Claim.** The collector refuses a body with `allocated-block` when an
allocated block is among the blocks read or written, the locations computed
before invalid offsets are trimmed, or the blocks designated by a value the
body reads without dereferencing it. The designated values include the cells
that a load combines, in C and in logic, the values of ACSL terms, the cells
scanned by the string primitives of the logic, and the finite sets of a
garbled value. The `requires` clauses of the body, checked at the call site,
are observed in the same way for this refusal. A set of blocks that is Top
refuses with `footprint-top`.

The claim does not cover a pointer to an allocated block held in a cell that
the body does not read, in a block that it reads elsewhere. `sibling` of
`contents.c` reads `holder.n` while `holder.p` holds such a pointer: it is
not refused, and the whole block `holder`, pointer included, is in R and in
a key produced from it. The collector does not exclude such a key block: a
consumer of the key must handle a key block that holds a pointer to an
allocated block.

**Kind.** OCaml obligation.

**Depends on.** [Whole-block observations and exits](body-access.md#whole-block-observations-and-exits),
[Annotation and contract reads](body-access.md#annotation-and-contract-reads).

**Symbols.** `Body_access.check_bases`, `Body_access.check_location`,
`Body_access.designate`, `Body_access.designate_bases`,
`Body_access.designate_cells`, `Body_access.read_bases`,
`Body_access.at_call_site`, `Body_access.is_observing`,
`Logic_access.with_clause`, `Logic_access.load`, `Logic_access.read`,
`Eval_terms.apply_logic_builtin`,
`Transfer_logic.Make.check_fct_preconditions`.

**Argument.** The slice of issue #41 checks every set the observation reports:
`check_bases` refuses an allocated base and a Top set. `Cvalue.V.get_bases`
returns the bases of a garbled value whose origin set is finite, and Top
otherwise. Issue #42 reports the loads of ACSL clauses through
`Logic_access`: the location, the targets of every cell that the load
combines (`designate_cells`), the blocks of the pointer of a string primitive
and the value of each term. A cell that holds a pointer beside an
uninitialized cell is joined into an uninitialized value that designates
nothing; the cells are therefore designated before the join, in C
(`Cvalue_queries`) and in logic.

The `requires` clauses of a body are checked with its recording suspended
([Refusal and reporting](body-access.md#refusal-and-reporting)): they belong
to the call site. The body is analysed from the states that these checks
reduce. On a memexec hit, the caller checks the clauses again to update
their statuses and ignores the reduced states: the stored exit states stand
for the analysis from the states reduced when the entry was stored
([Refusals inherited by an enclosing body](#refusals-inherited-by-an-enclosing-body)).
The dependence of the reduction on allocated blocks must therefore refuse
the entry. `check_fct_preconditions` runs the clauses under `at_call_site`,
which keeps a second recorder, the recorder of the body, for the allocation
family:
`Logic_access.with_clause` arms itself when a body or its call site is
observed (`is_observing`), and `read_bases`, `designate_bases`,
`designate_cells` and `designate` check the blocks of the call site with
`check_bases` without adding them to R or to the designated set. An unknown
load location at the call site refuses as `footprint-top`, where it sets
R = Top with the clause reason in a body. The reads of allocation metadata
add their owners. The footprint refusal `contract` is omitted at the
call site. The logger and ordered-effect observers can add separate
refusals during a call-site check.
[Ordered and opaque effects](collector-effects.md#ordered-and-opaque-effects).

**Evidence.** Execution. `copy` (`q = p`, where `p` points to an allocated
block) reads `copy allocated-block`; the module asserts R = {p}, W = {q}, an
allocated block among the designated blocks and no allocation effect.
`logic_only` reads an allocated block only through `/*@ assert p != \null; */`
and reads `logic_only: allocated-block allocation-metadata`; the module
asserts R = {p} and W = {x}. On the validity replay of the inventory ticket
(`equality.c`, a comparison of two pointers to allocated blocks),
`equal_live` reads `equal_live allocated-block` twice and the module asserts
that it reads allocation metadata and has an owner. In `requires.c`, three
bodies that do not access the block that their clause `\valid(p)`,
`\initialized(p)` or `\block_length(p) >= sizeof(int)` reads are refused
with `allocated-block` and the owner `__malloc_main_l18`; the module asserts
that R is empty and W = {x}. At the base revision, the probe module
described in [Allocation effects](#allocation-effects) gave no reason for
these bodies.

In `call-site.c` (`-machdep x86_32`), a word covers a garbled address of an
allocated block and an uninitialized padding. `req_word`, whose clause
`u->word == 0` loads that word, reads `allocated-block`; before the fixes it
read `would-store`. `c_word`, the C load of the same word, reads
`allocated-block` after the rebase on issue #42, which designates the cells
of C loads. With an initialized padding, `req_initialized` reads
`allocated-block allocation-metadata`; a clause over a word without pointer
reads `would-store`. The module asserts that these clauses add nothing to R.
In `strings.c`, `valid_read_string` and logic `strlen` over a union that holds
half the address of an allocated block read `allocated-block` (before the
fixes: `would-store`); the same scan before the allocation reads
`would-store`. Over an unknown value, the string scan reads `footprint-top`
(before the fixes: `would-store`) and `\initialized` reads `footprint-top`
(before the fixes too, but `would-store` at the base revision).

**Open.** A formal that the body does not read is not observed: a body that
ignores a pointer to an allocated block passed as argument is not refused by
this claim; a probe module (not committed) gives `would-store` for such a
body. Its binding is shared with the entry state of the body and is not
rebuilt ([next section](#contents-of-the-written-blocks)). No committed test
covers it.

## Contents of the written blocks

**Claim.** The collector refuses a body with `allocated-block`, and adds the
block to the owners, when a value of a block that the body may write
designates an allocated block, in the entry state of the body or in one of
its exit states. A value with an unknown set of targets refuses with
`footprint-top`.

**Kind.** OCaml obligation.

**Depends on.** [Allocated blocks among the observed blocks](#allocated-blocks-among-the-observed-blocks).

**Symbols.** `Body_access.check_written`,
`Compute_functions.Make.compute_and_cache_call`,
`Offsetmap.are_mergeable_nodes`, `Offsetmap.make_node`, `Offsetmap.nNode`.

**Argument.** The kernel builds an offsetmap from the values of its nodes.
Gluing two adjacent parts of a value (`are_mergeable_nodes`, through
`make_node`) and the tag of a node (`nNode`) depend on
`V.cardinal_zero_or_one`, which reads the weakness of the targets: a read
reported to the collector. The binary caches of `Offsetmap` (join, narrowing,
narrowing with reinterpretation, `map2`) and of `Lmap` (join, widening
without hints, narrowing, inclusion) return a result without repeating the
query. A narrowing computed while its target was strong, repeated after the
target became weak, returns two glued halves of a pointer and reports no
read; without the cache it returns a garbled value (open item below). The
offsetmaps that such an operation combines in the analysis of a body hold
the values of the bindings of its states.

A binding that the body neither reads nor writes keeps, in every state of the
body, the offsetmap of the entry state, physically. The transfers change only
the bindings they write, and the writes include the reductions by a
condition (`Cvalue_transfer.reduce`), the reductions by a clause
(`Logic_access.record_reduction`) and the scope changes. The join, the
narrowing, the widening and the inclusion of `Lmap` are traversals of
`Hptmap` with `idempotent` set: they return a subtree shared by both maps
without visiting it (source inspection). The widening of `Lmap` then visits
the bindings common to both maps to update the weak blocks; it reads their
weakness through `Base.is_weak`, which reports it. A binding that the body
reads is checked through the designations of the previous claim. The
remaining bindings are those of the blocks of W. Their values come from the
entry state or from a write of the body, whose value the body evaluates and
designates; `check_written` checks them at entry and at each exit, outside
the observation, and adds the refusal and the owners explicitly. The may
set W is used, not W_exit, and the entry state is checked even when no
state returns.

An admitted inner lexical sweep records the holder bindings it rebuilds
in W. The operations that rebuild bindings outside W are refused for
another reason. They include other lexical sweeps (`sweep`), the
release of automatic blocks at a return (`deallocation`, in the caller), the
states from a memexec hit (`nested-call`), unsupported builtins
and specifications (`builtin`, `contract`). The reductions by `requires` clauses happen at the
call site, before the body; the values they keep are designated by the loads
of the clauses. When W is Top, the body is already refused by the operation
that wrote an unknown set, and the contents are not checked.

**Evidence.** Execution, in `contents.c`: `main` stores a pointer to an
allocated block in a union and overwrites its first byte, so that the union
holds part of the pointer. `partial` writes the next field of the same
structure on two paths, which the analysis joins, and `partial_once` writes
it once. Neither reads the union; the module asserts that no allocated block
is in R, in W or among the designated blocks. Both read `allocated-block,
owners __malloc_main_l41`; before the fixes both read `would-store`.
`control`, the same writes to a structure without pointer, reads
`would-store`.

**Open.** The kernel caches are unchanged: their results depend on the
weakness of the blocks designated by the values they combine, which they do
not repeat on a hit. This holds at the base revision. Reproduction, with a
test module loaded by Frama-C on any program:

```ocaml
module M = Cvalue.V_Offsetmap
module U = Cvalue.V_Or_Uninitialized
let get = function `Bottom -> assert false | `Value x -> x
let run () =
  let z = Z.of_int in
  let vv = Base.create_variable_validity ~weak:false
      ~min_alloc:(z 63) ~max_alloc:(z 63) in
  let v = Cil.makeGlobalVar ~source:false "target" Cil_const.intType in
  let b = Base.register_allocated_var v Base.Malloc (Base.Variable vv) in
  let p offsets = U.C_init_noesc (Cvalue.V.inject b offsets) in
  (* Two offsetmaps of 64 bits: bits 0-15 hold one part of a pointer,
     bits 16-63 another part of the same pointer. *)
  let halves low high =
    let m = M.create ~size:(z 64) high ~size_v:(z 64) in
    M.add (z 0, z 15) (low, z 64, Abstract_interp.Rel.zero) m in
  let a = halves (p Ival.zero) (p Ival.zero_or_one)
  and c = halves (p Ival.zero_or_one) (p Ival.zero) in
  let test stage =
    let m = get (M.narrow a c) in
    let v = get (M.find ~offsets:Ival.zero ~size:(z 64)
                   ~validity:(Base.Known (z 0, z 63)) m) in
    Format.printf "%s single=%b value=%a@." stage
      (M.is_single_interval m) U.pretty v in
  test "strong miss";
  Base.update_variable_validity vv ~weak:true
    ~min_alloc:(z 63) ~max_alloc:(z 63);
  test "weak hit";
  M.clear_caches ();
  test "weak miss"
let () = Boot.Main.extend run
```

Loaded as a plug-in (`-load-module eva,shape.cmxs` on any program), it
prints the same at the base revision and with the changes of this entry:

```text
strong miss single=true value={{ &target }}
weak hit single=true value={{ &target }}
weak miss single=false value={{ garbled mix of &{target}
(origin: Misaligned read {<generated by Frama-C kernel>}) }}
```

The second narrowing is answered by the cache with the glued pointer of the
first; once the cache is cleared, the same narrowing gives a garbled mix.
Whether a C program reaches two such offsetmaps in one analysis is not
shown. The check of this claim covers the bodies; a cache that replaces
memexec, and any hit that reuses the kernel caches across a change of
weakness, must account for this dependence.

## Allocation effects

**Claim.** The collector refuses a body that performs an allocation, a
reallocation or a deallocation, or that updates a validity record, with the
reasons `allocation`, `reallocation`, `deallocation` and `validity-mutation`.
The detection follows what the builtins do, not their reported assigns. It
covers variable-length arrays, `alloca`, the updates made by the widening of
a memory map, and the automatic deallocation of the blocks of a call at its
return, which the collector predicts.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Builtins_malloc.alloc_fresh`, `Builtins_malloc.alloc_by_stack`,
`Builtins_malloc.alloc_weakest_base`, `Builtins_malloc.free_aux`,
`Builtins_malloc.realloc_builtin_aux`,
`Builtins_malloc.deallocates_at_return`,
`Builtins_malloc.free_automatic_bases`,
`Cvalue_domain.State.finalize_call`, `Transfer_stmt.Make.do_one_call`,
`Compute_functions.Make.compute_and_cache_call`,
`Base.update_variable_validity`, `Base.observe_validity_updates`.

**Argument.** Each builtin refuses at the operation, when it runs: the three
functions that return a base for an allocation (a new base, a base reused
from the same call stack, and the single weak base of the imprecise mode),
the release `free_aux` (also used by `realloc`, `__fc_vla_free` and the
automatic deallocation) and `realloc` on a pointer it accepts. A reused
base is an allocation even when no base is created: the state gains its block.
`__fc_vla_alloc` and `alloca` go through the same functions.

The automatic blocks of a call are released by the caller:
`do_one_call` finalizes each state that the call returns, and
`Cvalue_domain.State.finalize_call` frees the blocks that the allocation
registry holds for the call stack of the callee. This runs after the
observation of the callee, so `compute_and_cache_call` predicts it at the end
of the body: it refuses the callee with `deallocation` when the call
returns at least one state, the callee has a caller (the entry point has
none), and the registry holds an automatic block for its call stack. The
registry is read when the body ends, so a call that returns without
allocating, on a call stack that allocated before, is also refused. The
prediction is conservative: a returned state that the caller drops before
finalizing it (an argument reduced to bottom) frees nothing. The release
itself, in the caller, refuses the caller.

`Base.update_variable_validity` is the only function that changes a
validity record. The kernel runs the observer of `observe_validity_updates`
before each update, and the collector refuses the active body. The callers
are the reuse of a base by an allocation, which also changes the type and the
name of its variable, and the widening of a memory map, which increases the
maximal validity of a weak block whose binding changed.

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

In `finalisation.c`, the second call of `scratch` never returns: it reads
`would-store`, and the caller frees the block once, after the first call.
The entry point `entry` calls `alloca` and is refused with `allocation`, not
`deallocation`. Before the fixes, both read `deallocation`.

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
are the owners of the observation. A memoised result that depends on this
metadata does not report it on a hit: the dependencies through the values of
the bindings are covered by
[Allocated blocks among the observed blocks](#allocated-blocks-among-the-observed-blocks)
and [Contents of the written blocks](#contents-of-the-written-blocks), and
the dependencies through the tags of the nodes of offsetmaps by
[Weakened blocks and the partitioning index](#weakened-blocks-and-the-partitioning-index).

**Kind.** OCaml obligation.

**Depends on.** [Allocation effects](#allocation-effects).

**Symbols.** `Base.validity`, `Base.is_weak`, `Base.typeof`,
`Base.bits_sizeof`, `Base.alignof`, `Base.metadata_read`,
`Base.observe_metadata_reads`, `Cvalue.Default_offsetmap.default_offsetmap`,
`Body_access.set_recorders`, `Body_access.Result.owners`.

**Argument.** The kernel accessors of an allocated base run the observer of
`observe_metadata_reads`. The collector adds the refusal and the base to the
owners of the active body, or of the body whose call site is analysed. The
functions that match the `Allocated` constructor without an accessor call
`Base.metadata_read`. The other reads of a validity record go through a
validity extracted by one of these accessors. The paths are listed in
[Read paths of the validity record](#read-paths-of-the-validity-record).

The kernel holds one observer of each kind. `Base.observe_metadata_reads`
and `Base.observe_validity_updates` return the observer they replace, and
the kernel counts their calls (`Base.observer_changes`). The collector makes
its observers the observers of the kernel each time a recorder becomes
active; each calls the observer it replaced after its own work, and does
nothing when entered again from its own call, separately for reads and for
updates. When no recorder is active, the collector puts the replaced
observers back, unless another client installed one in the meantime: that
one is kept. Without recorder and without other client, and with
`-eva-no-cache-collect`, an accessor tests one reference and calls no
function. A client that restores an observer of the collector it had
replaced leaves it installed while no recorder is set: it then forwards
and records nothing.

A change of the observers by another client while a recorder is set may
hide an event from the collector, whether or not the client forwards or
restores. The collector compares the count of the kernel with the value
after its own last call at each change of recorder: when it moved, every
recording in progress is refused with `allocation-metadata`, with no owner
for the hidden event.

The observation is conservative. A write to an allocated block reads its
metadata in the collector's own location queries, and the body is already
refused for `allocated-block`. The exit sets and the contents of the written
blocks are computed with recording suspended. The cache lookup and storage
run with recording suspended: they are not part of the body (see
[the windows](#windows-where-recording-is-suspended)).

**Evidence.** Execution, in `widening.c`: the loop of `shift` changes
integers only. Its first call, before any allocation, reads `shift before
the allocation: no owner`; its second call, after `keep = malloc(...)`,
reads `shift after the allocation: owners __malloc_main_l43`. The module
asserts that `shift` reads, writes and designates no allocated block and
performs no allocation effect: the owner comes from an operation that the
program does not select. Source inspection attributes it to the visit of the
bindings common to both states by the widening; the test does not isolate
that path. `quiet` converges before the widening and reads `quiet
would-store` after the allocation. At the base revision, the probe module
gave only `side-table` for both calls of `shift`.

**Open.** No committed test traces the call chain of a metadata read, and
none measures the cost of the observers.

## Weakened blocks and the partitioning index

**Claim.** The collector refuses a body with `allocation-metadata` when its
analysis compares states through the partitioning index after a block has
been made weak in the analyses of the current program. The weakened blocks
are owners.

**Kind.** OCaml obligation.

**Depends on.** [Owners of allocation metadata](#owners-of-allocation-metadata).

**Symbols.** `Body_access.weakened`, `Body_access.read_node_tags`,
`Base.weakenings`, `Base.update_variable_validity`,
`Builtins_malloc.update_variable_validity`,
`Partitioning_index.Make.add`, `Cvalue_domain.distinct_subpart`,
`Cvalue_domain.find_subpart`, `Lmap.comp_prefixes`, `Lmap.find_prefix`,
`Offsetmap.nNode`, `Offsetmap.cardinal_zero_or_one`.

**Argument.** The tag of a node of an offsetmap is computed in `nNode` from
the weakness of the bases of the node's value, before the node is merged with
the hash-consing table. The table ignores the tag when it compares nodes: a
node built again with the same content keeps the tag of its first
construction. A tag can therefore be stale only for a node that holds a
pointer to a base made weak after the node was first built. The tags feed
`Offsetmap.cardinal_zero_or_one`, the compositional bool of `Lmap`, and
`Lmap.comp_prefixes` and `Lmap.find_prefix`; their only user in Eva is
`Partitioning_index.add`, through `distinct_subpart` and `find_subpart`, to
select the stored states that it compares by inclusion with a new state.
A test module that builds four states (not committed) showed that a stale
tag keeps a state that a fresh tag drops, and that the observation reported
no owner.

A base becomes weak in `Builtins_malloc.update_variable_validity`, when an
allocation reuses a strong base of its call stack as a weak one. The other
caller of `Base.update_variable_validity`, the widening of `Lmap`, updates
only bases that are already weak. `Builtins_malloc` records the base when it
makes it weak, whether or not a body is observed, in a set that lasts as
long as the bases (it depends on the AST, as the registry of allocated
bases): a node built in an earlier analysis of the same program can be found
again by the hash-consing table. `read_node_tags`, run before the index
consults the tags, refuses the body when the set is not empty, and adds the
recorded blocks to its owners. `Base.update_variable_validity` is public: the
kernel counts the calls that make a strong record weak (`Base.weakenings`),
whoever the caller is, and `read_node_tags` also refuses when the count is
not zero. The count belongs to the process: no operation on the states of
a project clears, copies or omits it, and it covers a node or a validity
record used from another project. A session carries no count. When a node
is loaded, `Offsetmap.rehash_node` computes its singleton bit again from
the loaded value and subtrees, which are rehashed first, and keeps the rest
of the tag; `Hptmap.rehash_node` rebuilds the leaves and branches of a
loaded map, and with them the compositional bool of `Lmap`. A node loaded
through its datatype therefore has the tag of the weakness that its targets
have in the session, and a weakening made after the load is counted in the
loading process. This does not hold for every loaded node: see the open
items. A second call of `Base.register_allocated_var`
on a variable replaces the validity of a base that existing nodes may
designate: it is counted as a weakening. A weakening counted without a call to
`Body_access.weakened` adds no owner. This is the plain form of the rule: it does
not check whether a compared state holds a pointer to a weakened block. The
first state that reaches a point is stored without reading a tag.

**Evidence.** Execution, in `weakening.c` (`-eva-slevel 4`): `alloc`
reuses its base at its second call, which makes the base weak. `branch`
leaves two states, which the index compares; called after the weakening, it
reads `allocation-metadata, owners __malloc_w_alloc_l10`, and before the
rule it read `would-store`. Called before the weakening, it reads
`would-store`. `straight` has one state at each point and reads
`would-store` after the weakening. On the Eva ptests run with collection
(`dev/collector-counts.sh`), the verdicts are the same at revision
`b6a0e9c2a443bb8b19c039008f3e2e9f5072321d`, before the rule, and with the
rule: 998 bodies would be stored in both runs, and every count of a first
reason is unchanged.
The same count is 998 at revision
`9bc5c9a4c974218e8ed9963c6e8440539b992e13`, where the count of the kernel
is part of the rule, and `allocation-metadata` is the first reason of no
body. The last cases of `run.t` do not use the allocation builtins.
`kernel-save` makes a record weak through `Base.update_variable_validity`
alone, while another project is current: `read_node_tags` reads
`would-store` before and `allocation-metadata` after, with no owner, and a
node and a state built while the target was strong keep their tags (`node
tag true, state tag true`). `kernel-load`, in another process, finds them
with the tags of the loaded value (`node tag false, state tag false`); a
node and a state built again there are the loaded ones, the join of both
states is the loaded state, and `read_node_tags` reads `would-store`. With
the saved tag kept at load, the loaded node read `node tag true`.
`kernel` registers a variable a second time with a weak record and reads
`allocation-metadata`. It also sets an observer of metadata reads before a
recording, which runs before, during and after it, and one during a
recording, which is kept after it while the collector records the read of
the next recording. An observer that does not forward, set during a
recording, hides the read: the recording reads `allocation-metadata` with
no owner, also when the observer is removed before the recording ends, and
the next recording reads `would-store`.

**Open: nodes loaded without their datatype.** A session may hold a state
that the loading process does not know (a plug-in that is not loaded): the
project library reads it without the transforms of its datatypes. A node
whose first occurrence in the session is inside such a state is not
rehashed, and a known state that shares it receives it as decoded, with the
saved tag, in a process whose count is zero. A body analysed there after
consulting that tag is not refused. An independent check reproduced it with
a node and a `Cvalue.Model` state saved in two states, one of them unknown
at load (`loaded: node tag true, state tag true`, then `would-store`). The
claim above is limited to sessions whose states are all known to the
loading process. Removing the limit is not decided: issue #43 lists the
options.

**Open: identifiers of loaded nodes.** A loaded node keeps the numeric
identifier given by the process that saved it, and the loading process
allocates identifiers from its own counter: an unrelated node can receive
the same one, and `compare`, which reads the tag only, then returns zero
for two distinct nodes. This holds at the base revision and is not changed
here (issue #68).

**Open.** The rule applies to the
bodies analysed after a weakening: an entry stored before a weakening and
matched after it is not covered, and the lookup must account for it. The
rule refuses more than the stale tags require: a finer rule would check
whether a compared state can hold a pointer to a weakened block.
`Partitioning_index` also consults the tags of all the bindings, including
blocks outside R; whether a match on a projection of the input preserves its
choices belongs to the frame claim and is not argued here.

## Refusals inherited by an enclosing body

**Claim.** A body inherits the reasons `reallocation`, `allocation`,
`deallocation`, `validity-mutation`, `allocated-block` and
`allocation-metadata`, and the owners, of every body analysed during its own
analysis.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Body_access.at_call_site`, `Body_access.include_fresh`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument.** When a fresh child's observation completes, the call seam
includes all the child's reasons and owners in the enclosing observation.
The caller observes the requires checks, while the callee retains the
allocation checks. With a memexec hit there is no child memory observation,
so the enclosing body refuses as `nested-call`. Its used functions travel
separately through [the call trace](collector-effects.md#calls-and-recursion).
The caller then checks the
`requires` clauses of the callee again, to update their statuses at this
call: `compute_and_cache_call` runs `check_fct_preconditions` in the caller,
with the caller's full recording. The reads, designations and metadata
reads of these clauses are therefore recorded as those of the caller.

**Evidence.** Execution: `main` of `effects.c` calls the bodies above and
reads `main reallocation`; the module asserts the three effect reasons and a
non-empty set of owners. In `release.c`, `main` reads `main allocation`. In
`hit.c`, run with memexec, `warm` calls `leaf`, whose clause `\valid(p)`
reads a pointer to an allocated block, and `hit_only` calls it again. The
second call is a memexec hit and no body of `leaf` runs during the analysis
of `hit_only`. Its reasons include `nested-call allocated-block
allocation-metadata` and its owner is `__malloc_main_l16`. The check in the
caller is not new: at the base revision, the probe module gave `nested-call
allocated-block side-table` for `hit_only`.

**Open.** None for this claim.

## Read paths of the validity record

**Claim.** The table lists every transitive read of the validity record or of
the type of an allocated block reachable from the analysis of a body by the
cvalue domain and the kernel memory maps, with its treatment. Where the audit
is not conclusive, the treatment is a refusal.

**Kind.** OCaml obligation.

**Depends on.** [Owners of allocation metadata](#owners-of-allocation-metadata).

**Argument.** A read of the metadata of an allocated base goes through an
accessor of `Base`, which reports it at the read, or matches the `Allocated`
or `Variable` constructor, or uses a validity extracted earlier by an
accessor. A memo is the only way to use the result of a read without
repeating it. The rows list the constructor matches and the extracted
validities, found by searching `src/kernel/services/abstract_interp` and
`plugins/eva/src` for the constructors, the fields of the record and the
accessors; the callers of the accessors; and the persistent memos of these
directories.

Each row gives the path, what it reads, its treatment and its evidence.
"Regression" names a committed test whose observation can only come from
that path. "Inspected" means source inspection; where a fixture reaches the
path without isolating it, the row says so. A tracing module printed the call
chains of the metadata reads before the rebase on the integration branch; it
is not committed, and no row relies on it.

Accessors of `Base`:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Base.validity`, `Base.is_weak`, `Base.typeof`, `Base.bits_sizeof`, `Base.alignof` | validity, weakness, type | reported | inspected; the fixtures observe owners without isolating an accessor |
| `Base.valid_offset`, `Base.is_valid_offset` | validity, through `Base.validity` | reported | inspected |
| `Base.is_weak_validity`, `Base.valid_range`, `Base.pretty_validity` | a validity given as argument | extracted by a reported accessor | inspected |
| `Base.update_variable_validity` | updates the record | `validity-mutation` | regression: `fill` (only the observer of this function raises the reason) |
| `Base.pretty`, `Base.to_varinfo` | name of the variable | text and identity, not metadata | inspected |

Kernel memory maps and values:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Lmap.add_binding`, `Lmap.find`, `Lmap.paste_offsetmap`, `Lmap.copy_offsetmap` | `Base.validity` of the target | reported | inspected |
| `Lmap.widen`, visit of the common bindings | `Base.is_weak`, `Base.validity` | reported | inspected; `shift` observes an owner without access, not attributed to this path by the test |
| `Lmap.widen`, maximal validity of a weak block | updates the record | `validity-mutation` | regression: `fill` (allocates nothing; the other caller is an allocation builtin) |
| `Cvalue.Default_offsetmap.default_offsetmap` | constructor of an allocated base | `Base.metadata_read` | inspected |
| `Addresses.cardinal_zero_or_one` | `Base.is_weak` | reported | inspected (callers: `Locations.cardinal_zero_or_one`, `Cvalue.forward_eq_int`, `Eval_op.add_if_singleton`, `Offsetmap` node tags and gluing) |
| `Offsetmap.are_mergeable_nodes`, `Offsetmap.make_node`: gluing of two parts of a value | `V.cardinal_zero_or_one`, hence `Base.is_weak` | reported when computed; see the caches below | inspected |
| `Offsetmap.nNode`: tag of a node | `V.cardinal_zero_or_one` of the node's value | reported when computed, also on a hit of the hash-consing table | inspected |
| `Map_lattice.With_Cardinality.find_lonely_key`, `find_lonely_binding` | `Base.is_weak` | reported | inspected (callers: `Cvalue.V.project_ival`, `Precise_locs`, the pointer comparisons of `Cvalue_forward`, `Eval_typ.offsetmap_matches_type`) |
| `Addresses.widen`, thresholds from the target | `Base.validity` | reported | inspected |
| `Addresses.is_relationable`, `Addresses.cardinal` | `Base.validity`, `Base.is_weak` | reported | inspected |
| `Locations.valid_part`, `Locations.enumerate_valid_bits_under_over`, `Locations.interval_from_ival_under` | `Base.valid_offset`, `Base.validity` | reported | inspected |
| `Locations.is_valid`, `Locations.valid_cardinal_zero_or_one` | `Base.is_valid_offset`, `Base.is_weak` | reported | inspected |
| `Offsetmap` and `Tr_offset` functions with a `~validity` argument, `Offsetmap.size_from_validity` | a validity given as argument | extracted by a reported accessor in `Lmap` | inspected |
| `Lmap_bitwise` default bindings | `Base.validity` | reported | inspected |

Eva:

| Path | Reads | Treatment | Evidence |
| --- | --- | --- | --- |
| `Cvalue_forward`: pointer comparison, alignment, `nearly_valid_bits` | `Base.is_valid_offset`, `find_lonely_key`, `Base.alignof`, an extracted validity | reported | inspected; `equal_live` reaches the comparison |
| `Main_locations`: validity of a location and its reduction | `Base.is_valid_offset`, `find_lonely_key` | reported | inspected |
| `Eval_op.add_if_singleton` | `Base.is_weak` | reported | inspected |
| `Eval_op.reduce_by_initialized_defined` | `Base.is_weak` | reported | inspected |
| `Eval_terms`, `\block_length` | `Base.validity` | reported | inspected; `length_only` reaches it at the call site |
| `Builtins_malloc`: sizes, initial contents, release, reallocation, weak check | `Base.validity`, `Base.is_weak`, constructor | reported, in a body refused for the effect | inspected |
| `Builtins_malloc.is_automatically_deallocated`, `Main_values` | constructor and kind of deallocation | immutable | inspected |
| `Builtins_malloc.update_variable_validity` | changes the type and the name of the variable, and may make the base weak | followed by `Base.update_variable_validity` in the same function; the weakening is recorded | regression: `alloc` (calls 2 and 3, `validity-mutation`) and `branch` (call 2) of `weakening.c` |
| `Builtins_memory` (`memset`), `Cvalue.pretty_base_offsets_typ` | type of the variable through `Base.to_varinfo` | builtin refused; message text | inspected |
| `Auto_loop_unroll`, `Logic_inout` | the variable of a base | identity only | inspected |
| `Mem_exec` | `Base.validity` in `diff_base_full_zone` | outside recording | inspected |
| `Cvalue_init` | validity of globals | before any body | inspected |
| Other domains, `Concurrency`, Mthread | various | the body is refused at admission | inspected |

### Windows where recording is suspended

| Site | Runs | Treatment | Evidence |
| --- | --- | --- | --- |
| `Transfer_logic.Make.check_fct_preconditions` | `requires` clauses of the body, and the statuses of the `requires` of an inactive behavior | `at_call_site`: allocation family and `footprint-top` recorded | regression: `requires.c`, `call-site.c`, `strings.c` |
| `Compute_functions.Make.compute_and_cache_call`, lookup | the lookup in the supplied entries or in memexec: extraction of the evaluated arguments, matching, filtering of the domain states and reconstruction of the exit states on a hit, counters, reporting | outside the body | inspected |
| `Compute_functions.Make.compute_and_cache_call`, storage | memexec storage, including `Mem_exec` reads of `Base.validity`, the collector verdict, the production of an entry, counters, reporting | outside the body | inspected |
| `Compute_functions.Make.compute_and_cache_call`, hit | `requires` checked again in the caller | caller's full recording | regression: `hit.c` |
| `Body_access.capture` | computation of W_exit and W_sure; observers of the result | the collector's own work; observers must not change the analysis | inspected |
| `Body_access.check_written` | contents of the written blocks | refusals and owners added explicitly | regression: `contents.c` |
| `Cvalue_callbacks.run_hook` | call hooks | an unclassified hook refuses with `callback`; the classified protocols do not change the analysis of the body | inspected; executed in [`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t) |
| `Iterator` | `Async.yield` | no analysis | inspected |

The operations of the cache run outside the observation of the caller
because memexec is not the cache of this effort. The matching, the
reconstruction of the states and the replay of the cache that replaces it
use the metadata of the blocks they handle, and the kernel caches
([Contents of the written blocks](#contents-of-the-written-blocks)). Before
they move inside such a window, they need explicit dependency handling: the
metadata they read must be recorded as owners of the entry or compared at
the hit.

### Persistent memos

| Memo | Depends on | Treatment | Evidence |
| --- | --- | --- | --- |
| `Offsetmap` node tag of a node the body builds (hash-consing) | `V.cardinal_zero_or_one`, hence `Base.is_weak`, of the node's value | read before the merge with the table: reported on a hit as on a miss | inspected |
| tags of nodes the body does not build, `Lmap` compositional bool | weakness of the bases when the node was first built | refused when the index consults them after a weakening ([Weakened blocks and the partitioning index](#weakened-blocks-and-the-partitioning-index)) | regression: `weakening.c` |
| `Offsetmap` join, narrowing, narrowing with reinterpretation and `map2` caches | values, and the gluing and tags computed from the weakness of their targets | not reported on a hit: covered by the designations of the values read and the contents of the written blocks; the caches are unchanged (open item of [Contents of the written blocks](#contents-of-the-written-blocks)) | the narrowing: kernel reproduction; `contents.c` |
| `Lmap` join, widening without hints, narrowing and inclusion caches | the operations of `Offsetmap` on the common bindings; default bindings | as the line above for the common bindings; default bindings: size `max_allocable + 1`, which is immutable, and the join of cvalue does not read default bindings | inspected |
| `Lmap_bitwise` join, inclusion and `fold_on_zone` caches | default bindings | size from `max_allocable` | inspected |
| `Addresses.contains_addresses_of_any_locals` cache | constructor of the base | immutable | inspected |
| `Map_lattice`, `Int_Intervals` and `Addresses` binary caches | values and intervals of the `Addresses` instantiation | no metadata | inspected |
| `Widen` hints per function, valuation of a transfer | no metadata; scope of one transfer | none needed | inspected |

For the default bindings: the two functions that create an allocated base
give it a `Variable` validity, and `Offsetmap.size_from_validity` sizes it
by `max_allocable`, which is immutable. Moreover, the inclusion of two
states reads the default binding only for a base bound in one state and not
the other. Within a body, every state comes from one entry state. Adding
or removing an allocated binding requires an allocation or release, which
refuses for the effect itself, including when it occurs in a nested call.

**Evidence.** As in each row.

**Open.** The rows marked "inspected" have no regression. The audit does not
claim that every designation of an allocated block is observed: it lists
the reads of metadata and the memos found by the search above.
