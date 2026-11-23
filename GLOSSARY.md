# Statement reuse in Eva

Vocabulary for reusing the result of analysing a statement, within one
analysis and across two versions of a program.

## Language

### The cache

**Cache entry**:
The stored result of analysing one statement from one abstract input. The
cache entry of a heap call holds full states and no hit uses it.
_Avoid_: Summary (names Eva's statistics report), memo, record

**Part**:
One component of a cache entry, tied to one claim about the concrete
executions of the statement.
_Avoid_: Facet, field

**Hit**:
A call or statement whose input matches the key of a cache entry, so that the
entry is used and the body is not analysed.
_Avoid_: Reuse (as a noun for one occurrence)

**Key group**:
The calls that use the same cache entry in one analysis, including the one
that computed it.
_Avoid_: Same-key group, equivalence class

**Hit log**:
The list of the members of each key group, each with the abstract state at
its call.

**Child entry**:
A cache entry used for a call nested in the statement of another entry, which
refers to it.

**Heap call**:
A call whose analysis, in its body or in a call nested in it, calls an
allocation builtin or `free`. Every caller of a heap call, up to the entry
point, is one. Its cache entry holds the full state before and after each
statement of its body, and memexec does not store it, so no hit reuses it. A
call that reads or writes an allocated block without allocating or freeing
one is not a heap call.
_Avoid_: Allocating call (leaves out `free`)

### Parts of an entry

**Exit part**:
The abstract states at the exits of the statement.

**Safety part**:
The alarms and the annotation statuses established while analysing the
statement.

**Reach part**:
The statements reached while analysing the statement.

**Inner part**:
The abstract state before each statement inside the body, on its locals and on
the blocks whose value at entry is checked by the match. A heap call has no
Inner part: its cache entry holds the full state before and after each
statement, on every block, and answers the queries at these points as it is.
_Avoid_: Intermediate states, per-statement states

### Blocks

**Block**:
A unit of memory that the abstract state names as a whole: a variable, a
string literal, a function, a heap allocation, the null block or a range of
absolute addresses.
_Avoid_: Base (the name of its implementation in Eva), variable, name

**Existing block**:
A block that exists in the input of a statement.
_Avoid_: Entry block (reads as a block of a cache entry), live block, input
block

**Created block**:
A block that the analysis of a statement brings into existence: one of its
locals, its return value, or a heap allocation it performs.
_Avoid_: Fresh block, local block

**Allocated block**:
A block created by an allocation builtin: a heap allocation, an `alloca` or a
variable-length array.
_Avoid_: Heap block (leaves out `alloca` and variable-length arrays), dynamic
base

**Validity record**:
What the analyzer holds about the extent of a block: its size, and whether it
stands for one concrete block or for several. It is a side table, keyed for
the mentioned blocks. Only the validity record of an allocated block can
change during an analysis.
_Avoid_: Validity (names the property, not the table)

**Matching key**:
The blocks whose values in the input are compared by the match. They decide
the Exit part.
_Avoid_: Exit key

**Footprint**:
The blocks the statement reads or writes. It contains no side table.
_Avoid_: Inner key

**Frame**:
The blocks the statement neither reads nor writes.

**Mentioned block**:
An allocated block of the matching key of a cache entry, or one that a
pointer value of the arguments or of the matching key may point to when the
statement starts. A mentioned block outside the matching key is not
compared by its content. This is the definition of #123, where no cache
entry of a heap call is used; when heap calls are stored, #120 adds the
candidate blocks of each allocation, absent ones included.
_Avoid_: Reachable block (reachability is transitive)

**Snapshot**:
The strength, validity record, type and kind (heap allocation, `alloca` or
variable-length array) of each mentioned block of a cache entry, when the
statement starts.
_Avoid_: Descriptor (names what the observer of the hit log captures)

**Numbered form**:
A cache entry in which each allocated block is replaced by the placeholder
block of its number. The blocks are numbered in a fixed order: the targets
of the arguments, then those of the blocks of the matching key that are not
allocated, then those of each numbered block of the matching key in the
order of the numbers, then the candidate blocks, then the allocated blocks
of the matching key that no value points to. Two entries that differ only
by the allocated blocks they use have the same numbered form; two entries
that a renaming maps to each other may not.
_Avoid_: Canonical form (a renaming does not always give the same form)

**Placeholder block**:
An allocated block that stands for a number in a numbered form. It has the
strength of the block it stands for, and nothing reads its validity record
or its type. It never appears in a state of the analysis.
_Avoid_: Dummy block, number (names its position)

### Versions

**Renaming**:
An injective map from the blocks a cache entry mentions to blocks of the
analysis that uses the entry.
_Avoid_: Substitution (names Eva's treatment of recursive calls), translation

**Version map**:
The correspondence between the program that produced the cache entries and
the program that uses them. It has three components: a renaming of blocks, a
map of statements and a map of functions.
_Avoid_: Diff, matching (as a noun)

**Image**:
The entity of the using program that the version map gives for an entity of
the producing program.
_Avoid_: Counterpart, match

**Unmapped**:
Said of an entity of the producing program that has no image.
_Avoid_: Unmatched, missing

**Import condition**:
What a cache entry must satisfy, when it is loaded, to be kept.
_Avoid_: Validity condition (validity is a property of a block), invalidation
rule

**Dropped**:
Said of a cache entry or a part that is not kept at import.
_Avoid_: Invalidated, stale

**Configuration**:
The settings that must be equal between the producing analysis and the using
analysis.
_Avoid_: Options, parameters

### Delivery

**Milestone**:
A set of cards delivered together. It is done when every one of its cards is
done, including the cards added by a review. The first three milestones are
named by the relation between the analysis that produces the cache entries and
the analysis that uses them: reuse within one analysis, reload on an unchanged
program, reuse on an edited program. Earlier tickets call these three "stage
1", "stage 2" and "stage 3".
_Avoid_: Stage, phase, step

**Unchanged program**:
A program in which every entity of the producing program has an image and
every function body is reported unchanged by the version map. Its text may
differ.
_Avoid_: Same program, same version

**Edited program**:
A program that is not unchanged.

**Card**:
One unit of work of a milestone. A card is a feature, a test card or a
bug-fix card.

**Feature**:
A card that delivers something demonstrable on its own, with its acceptance
evidence. It is a model feature, a mechanism feature or a reuse feature. A
milestone has at most one of each kind.

**Model feature**:
The feature of a milestone made of definitions in the reference model with
their theorems checked.

**Mechanism feature**:
The feature of a milestone made of a part of the analyzer that reuse depends
on and that is evaluated alone.

**Reuse feature**:
The feature of a milestone that makes the analyzer use cache entries in the
setting the milestone names.

**Test card**:
A card that produces evidence and changes no behaviour.

**Bug-fix card**:
A card opened by a review of features of the same milestone.

**Synthetic edit**:
One scripted change at one site of a program, of a fixed edit kind.
_Avoid_: Mutation, patch (the patch is its file)

**Edit kind**:
The syntactic class of a synthetic edit.

**Control edit**:
A synthetic edit whose expected set of dropped cache entries, computed for
its site, is empty. Being a control is a property of the case, not of the
edit kind.

### Domain laws

**Exact**:
Said of an operation of a domain whose result contains no concrete state
beyond those its specification asks for.
_Avoid_: Precise; exact as a name for from-scratch equality

**Closed**:
Said of a set of blocks in an abstract state when the state relates no block
of the set to a block outside it.
_Avoid_: Saturated, stable

**From-scratch equality**:
The property that an analysis using the cache gives the same result as the
analysis without it under the same configuration. It is tested, not proved.
_Avoid_: Exactness, parity

### Dependencies

**Side table**:
A table outside the abstract state that the analysis of a statement reads or
writes.
_Avoid_: Component, resource, global state

**Dependency**:
A block or a side table whose content at the entry of a statement is read
while analysing it.
_Avoid_: Input (names a zone of the Inout plug-in)

**Call mode**:
How a call is analysed: by the body of the function, by its specification or
by a builtin.
_Avoid_: Analysis target, kind

**Used functions**:
The functions called while analysing the statement of a cache entry, each
with its call mode.
_Avoid_: Function record, callees (reads as the calls written in the text)

**Keyed side table**:
A side table whose content at entry is compared by the match, as a block is.

**Fixed side table**:
A side table that does not change during one analysis. It is outside the
match and is compared by the import condition across versions.

**Recorded side table**:
A side table that a statement only writes, by a join.

**Refusing side table**:
A side table such that a statement reading or writing it gets no cache entry.
A side table with no other class is refusing.

### Effects

**Effect**:
A write made while analysing a statement: a designated write, a table write
or a sweep.

**Designated write**:
A write to a block that the statement designates through an lvalue or a
contract.

**Table write**:
A write to a side table.

**Sweep**:
A rewrite of every block whose content satisfies a condition, wherever the
block is.

**Recorded effect**:
An emission made while analysing a statement that is a join into a table, so
that repeating it changes nothing.

**Replay**:
Emitting the recorded effects of a cache entry in an analysis that did not
compute it.
_Avoid_: Re-emission
