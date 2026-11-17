# Statement reuse in Eva

Vocabulary for reusing the result of analysing a statement, within one
analysis and across two versions of a program.

## Language

### The cache

**Cache entry**:
The stored result of analysing one statement from one abstract input.
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
the blocks whose value at entry is checked by the match.
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

**Matching key**:
The blocks whose values in the input are compared by the match. They decide
the Exit part.
_Avoid_: Exit key

**Footprint**:
The blocks the statement reads or writes. It contains no side table.
_Avoid_: Inner key

**Frame**:
The blocks the statement neither reads nor writes.

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

### Dependencies

**Side table**:
A table outside the abstract state that the analysis of a statement reads or
writes.
_Avoid_: Component, resource, global state

**Dependency**:
A block or a side table whose content at the entry of a statement is read
while analysing it.
_Avoid_: Input (names a zone of the Inout plug-in)

**Keyed side table**:
A side table whose content at entry is compared by the match, as a block is.

**Fixed side table**:
A side table that does not change during one analysis. It is outside the
match and is compared by the validity condition across versions.

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
