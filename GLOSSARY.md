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
The abstract state before each statement inside the body, on the variables of
the inner key.
_Avoid_: Intermediate states, per-statement states

### Variables

**Exit key**:
The variables whose values in the input decide the Exit part.

**Inner key**:
The variables the statement reads or writes.

**Frame**:
The variables the statement neither reads nor writes.

### Effects

**Recorded effect**:
An emission made while analysing a statement that is a join into a table, so
that repeating it changes nothing.

**Replay**:
Emitting the recorded effects of a cache entry in an analysis that did not
compute it.
_Avoid_: Re-emission
