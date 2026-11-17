# What Frama-C can save and reload between processes

Research note for issue 5 of `nyandrianinamamy/frama-c`.

- Code read at commit `71986dadcb` (Frama-C 35~dev). Paths are repo-relative.
- Nothing was built or run. Every claim is tagged **[read]** (the cited lines
  say it) or **[inferred]** (deduced from several read places, not observed).
- Manual text is cited from the LaTeX sources in this repository
  (`doc/developer`, `doc/userman`). They are the sources of the public
  [plug-in development guide](https://frama-c.com/download/frama-c-plugin-development-guide.pdf)
  and [user manual](https://frama-c.com/download/frama-c-user-manual.pdf).
  The published PDFs were not fetched.

## Summary

1. `-save` writes every project with every registered state into one file.
   `-load` deletes the projects of the loading process and replaces them by
   the saved ones, AST included.
2. Values are rebuilt by plain OCaml unmarshalling, plus a per-datatype
   `rehash` step that re-interns hash-consed nodes. Identity of AST nodes is
   an integer id, valid only together with the AST saved in the same file.
3. The Eva result tables, callers, function statuses, alarms and property
   statuses are saved. The memexec cache, the initial-state cache and the
   states of unmarshallable domains are not.
4. After `-load`, Eva does not run again unless one of its dependencies
   changes. When one does, all of Eva's states are cleared. No code path
   keeps part of the Eva states across an AST change.
5. The only global check is a string made of the version and codename. Then
   each state is checked by name and by type digest.
6. Outside the session file, the repository has write-only exports
   (CSV, flamegraph, ACSL), the audit JSON file (written and read back, used
   for checking only) and the WP proof cache (written and read back, keyed by
   a digest). Eva has no on-disk result cache.

## 1. What `-save` and `-load` write and read

### Entry points

- **[read]** `-save <file>` is the kernel option `SaveState`
  (`src/kernel/services/plugin_entry_points/kernel.ml:758-766`). `-load
  <file>` is `LoadState`, parsed at the `Loading` command-line stage
  (`kernel.ml:781-792`).
- **[read]** Saving happens at exit and calls `Project.save_all`
  (`src/kernel/internals/runtime/special_hooks.ml:136-155`). On `Ctrl-C` the
  file gets the suffix `.break`, on a user error `.error`, on any other
  error `.crash` (`special_hooks.ml:156-168`).
- **[read]** The user manual says something narrower: saving on fatal or
  unexpected error goes to `file.crash`, and "in other error cases, no saving
  is done" (`doc/userman/user-services.tex:48-54`). The code and the manual
  disagree on user errors.
- **[read]** Loading calls `Project.load_all` after the loading stage and
  aborts on `Project.IOError` (`special_hooks.ml:90-98`).

### File contents

- **[read]** `save_projects` writes, in this order: the seed string, the
  integer `magic` (9), the OCamlgraph vertex counter, then one value holding
  the list of `(project, [(state unique name, state_on_disk)])` and the
  "last created by copy" project (`src/lib/project/project.ml:513`,
  `project.ml:524-542`). The file is compressed by default
  (`project.ml:91`, `project.ml:527`).
- **[read]** `save_all` saves all projects, `save` saves one
  (`project.ml:544-552`). Both accept a state selection, so a save can be
  restricted to some states.
- **[read]** A `state_on_disk` holds the value, the `computed` flag, a
  `saved` flag and the digest of the state's type
  (`src/lib/project/state.mli:116-120`,
  `src/lib/project/state_builder.ml:250-263`).
- **[read]** The user manual states: when saving, all existing projects are
  dumped into one non-human-readable file; when loading, all existing
  projects are deleted, the saved ones are loaded, the saved current project
  is restored, and Frama-C is replayed with the saved parameters except those
  set explicitly on the new command line
  (`doc/userman/user-services.tex:56-66`). Existing projects are deleted even
  if reading fails (`user-services.tex:80-84`; code:
  `project.ml:738-746`).

### The dependency graph is not saved

- **[read]** The file contains state values only. The dependency graph is a
  static in-memory graph filled when each state is registered
  (`src/lib/project/state_dependency_graph.ml:32-60`,
  `state_builder.ml:312-320`).
- **[inferred]** So the graph used after `-load` is the one of the loading
  binary, not the one of the saving binary.
- **[read]** The graph is used on load in one place: when a state on disk has
  an incompatible type, the states that depend on it are cleared
  (`project.ml:275-292`).

### How a state opts out of marshalling

- **[read]** A state is saved unless the descriptor of its datatype is
  "unmarshable": `must_save = not (Descr.is_unmarshable
  Datatype.datatype_descr)` (`state_builder.ml:240`). When `must_save` is
  false, `()` is written in place of the value and `on_disk_saved` is false
  (`state_builder.ml:250-263`).
- **[read]** A datatype is unmarshable when its `structural_descr` is
  `Structural_descr.t_unknown`, which is what `Datatype.Undefined` provides
  (`src/lib/datatype/datatype.ml:99-103`,
  `src/lib/datatype/descr.ml:25-26`). `Structural_descr.Unknown` is documented
  as "values of types with this descriptor will never be written on disk"
  (`src/lib/datatype/structural_descr.mli:35-39`).
- **[read]** `Eva_utils.Do_Not_Marshal` wraps a datatype with
  `Datatype.Undefined` first (`plugins/eva/src/utils/eva_utils.ml:98-104`).
- **[read]** Weak hash tables use `Datatype.Undefined`
  (`datatype.ml:1210-1218`), so every hash-consing table registered through
  `State_builder.Hashconsing_tbl` is unmarshable
  (`state_builder.ml:635-648`, `state_builder.ml:684-741`).
- **[read]** A proxy state writes `()` with `on_disk_saved = false`
  (`state_builder.ml:71-96`).
- **[read]** A parameter is not saved when `Parameter_customize.do_not_save`
  or `do_not_projectify` was called for it
  (`src/kernel/services/cmdline_parameters/parameter_customize.ml:33-43`,
  `src/kernel/services/cmdline_parameters/parameter_state.ml:103-107`). The
  user manual lists `-help`, `-verbose`, `-debug`, `-explain`, `-quiet` and
  `-unicode` as not saved (`doc/userman/user-services.tex:86-93`).
- **[read]** `howto_marshal` lets a state give its own conversion pair and
  forces saving (`state_builder.ml:245-248`).
- **[read]** The developer manual says a registered state "is part of the
  information saved on disk for restoration in a later session"
  (`doc/developer/advance.tex:2320-2321`) and that an unregistered global "is
  never saved on the disk" (`advance.tex:2410-2412`).

## 2. How values with identifiers or hash-consing are rebuilt

### Mechanism

- **[read]** Reading goes through `Descr.input_val`, which calls
  `Unmarshal.input_val` with a descriptor built from the states' datatype
  descriptors (`project.ml:618-664`, `descr.ml:173-175`).
- **[read]** `Unmarshal` descriptors are `Abstract` (read like
  `Marshal.from_channel`, no check, no transformation), `Structure` (shape
  given, checked while reading), `Transform (d, f)` (read as `d`, then apply
  `f` and keep the result), `Return` and `Dynamic`
  (`src/lib/datatype/unmarshal.mli:35-45`, `unmarshal.mli:47-54`,
  `unmarshal.mli:79-91`).
- **[read]** A datatype's `rehash` function becomes a `Transform` on its
  descriptor. If `rehash` is `Datatype.identity`, the descriptor is used
  unchanged (`datatype.ml:164-183`).
- **[read]** Sharing inside the file is kept: a shared pointer is resolved
  through the table of already-read blocks, and that table stores the block
  after its transformation (`src/lib/datatype/unmarshal.ml:553-567`,
  `unmarshal.ml:586-592`).
- **[inferred]** All projects and states are written by one `output_value`
  (`project.ml:542`), so an AST node referenced from several states is one
  node again after loading. The Eva tables point to the same `varinfo` and
  `stmt` values as the loaded AST.
- **[read]** The developer manual says of a datatype: the structural
  descriptor "is used when marshaling" and "rehashing is used when
  marshaling" (`doc/developer/advance.tex:1914-1926`).

### AST nodes: `varinfo`, `stmt`, `kernel_function`

- **[read]** Cil datatypes use `Structural_descr.t_abstract` and `rehash =
  Datatype.identity` (`src/kernel/services/ast_queries/cil_datatype.ml:53-61`,
  `cil_datatype.ml:73-81`). They are read back as plain OCaml values.
- **[read]** Identity is the integer id: `stmt` by `sid`
  (`cil_datatype.ml:242-244`), `varinfo` by `vid`
  (`cil_datatype.ml:705-707`).
- **[read]** `kernel_function` has a non-identity `rehash` that re-registers
  the formals of a declaration (`cil_datatype.ml:2737-2741`). Its `equal`
  raises a fatal error when two physically distinct values have the same id
  (`cil_datatype.ml:2724-2734`).
- **[read]** The id counters `vid_counter`, `sid_counter` and `eid_counter`
  are states shared by all projects
  (`src/kernel/services/ast_queries/cil_const.ml:77-79`). On load a shared
  counter becomes the maximum of the loaded value and the current value
  (`state_builder.ml:836-866`).
- **[inferred]** So ids created after a load do not collide with loaded ids.

### `Base`

- **[read]** `Base.t` is abstract with `rehash = Datatype.identity`
  (`src/kernel/services/abstract_interp/base.ml:483-498`). Its id is the
  `vid` of its variable, the id of its logic variable, 0 for `Null`, or the
  id stored in an absolute range (`base.ml:107-111`).
- **[inferred]** A base is not rebuilt on load. It is read as it was written
  and keeps the id of the saved `varinfo`.

### Hptmaps and Cvalue states

- **[read]** An hptmap descriptor is a recursive sum: a leaf is (key, value,
  tag), a branch is (prefix, mask, left, right, tag)
  (`src/lib/utils/hptmap.ml:670-689`). Its `rehash` is `rehash_node`
  (`hptmap.ml:694-698`, `hptmap.ml:826`).
- **[read]** `rehash_node` re-interns each node in the hash-consing table of
  the loading process and gives it a fresh tag: a leaf goes through
  `wrap_Leaf`, a branch through `wrap_Branch` when the key descriptor is
  abstract. When the key descriptor is not abstract, the map is rebuilt by
  re-adding all bindings, because the key ids may have changed
  (`hptmap.ml:813-824`, `hptmap.ml:743-763`).
- **[read]** The hash-consing table of an hptmap is a
  `State_builder.Hashconsing_tbl` (`hptmap.ml:706-738`), hence not saved (see
  section 1).
- **[inferred]** Maximal sharing is restored on load by re-interning, not by
  saving the table. Tags differ between the saving and the loading process.
- **[read]** `Base` keys are abstract (`base.ml:487`), so maps keyed by bases
  take the `wrap_Branch` path: the shape of the tree, which depends on the
  ids, is trusted as saved.
- **[read]** `Cvalue.Model` is an `Lmap` over `Base`, built on `Hptmap`
  (`src/kernel/services/abstract_interp/cvalue.ml:1001-1004`,
  `src/kernel/services/abstract_interp/lmap.ml:87`). Offsetmaps have their
  own `rehash_node` and hash-consing table
  (`src/kernel/services/abstract_interp/offsetmap.ml:199-223`,
  `offsetmap.ml:309-314`). The state of the cvalue domain is a pair with
  descriptor `(Cvalue.Model, Locals_scoping)` and identity `rehash`
  (`plugins/eva/src/domains/cvalue/cvalue_domain.ml:82-99`).
- **[read]** Generic sets, maps and hash tables are rebuilt on load only when
  the key descriptor is not abstract (`datatype.ml:1014-1019`,
  `datatype.ml:1086-1095`, `datatype.ml:1162-1173`).

### What breaks with a different AST

- **[read]** `-load` never pairs saved states with an AST parsed by the
  loading process. `load_all` removes all projects first
  (`project.ml:738-746`), and source files given on the same command line are
  ignored with a warning
  (`src/kernel/services/cmdline_parameters/cmdline.ml:897-901`; manual:
  `doc/userman/user-sources.tex:556-557`).
- **[read]** `Project.load` (one project, API only) creates a new project
  beside the existing ones (`project.ml:728-736`, `project.ml:584-592`).
- **[inferred]** Ids are allocated by counters at parse time
  (`cil_const.ml:77-82`), so the `vid` and `sid` of a program element in the
  AST of version N+1 have no relation to those in the saved AST of version N.
  A saved table keyed by `stmt`, `varinfo`, `kernel_function` or `Base`
  cannot be looked up with nodes of another AST: equality by id would match
  unrelated nodes or none, and `Kf.equal` aborts on two distinct values with
  one id (`cil_datatype.ml:2724-2734`).
- **[inferred]** Hptmaps keyed by `Base` take the fast `rehash` path that
  assumes ids are unchanged (`hptmap.ml:817-820`). Translating bases to
  another AST's ids would need a rebuild of every map, which no code does.
- **[inferred]** A saved Cvalue state contains its bases by pointer, and a
  base contains its `varinfo` (`base.ml:100-105`). Unmarshalling a Cvalue
  state alone therefore brings a private copy of each `varinfo` it mentions,
  not the `varinfo` of any AST in memory.

## 3. Which Eva states are saved

### Saved (datatype marshallable, registered state)

All are **[read]** unless tagged otherwise.

| Content | State | Evidence |
|---|---|---|
| Cvalue state per control point, joined and per callstack | `Cvalue_results` = `Domain_store.Make(Cvalue.Model)`: `Table`, `TableByCallstack`, `Save` | `plugins/eva/src/domains/cvalue/cvalue_results.ml:9-12`, `plugins/eva/src/domains/domain_store.ml:55-86` |
| States of other domains built with `Domain_builder`, when their datatype is marshallable | `Domain_store.Make(Domain)` | `plugins/eva/src/domains/domain_builder.ml:89`, `domain_store.ml:66-76` |
| Callers and callsites of each function | `Function_calls.CallersTable` | `plugins/eva/src/engine/function_calls.ml:22-24` |
| Analysis status of each function (unreachable, spec, builtin, analyzed) | `Function_calls.StatusTable` | `function_calls.ml:69-90` |
| Analysis state (not computed, computing, computed, aborted) | `Self.ComputationState` | `plugins/eva/src/self.ml:39-63` |
| Alarms | kernel `Alarms.State`, `Alarms.Alarm_of_annot` | `src/kernel/services/ast_data/alarms.ml:302-333` |
| Property statuses | kernel `Property_status.Status` | `src/kernel/services/ast_data/property_status.ml:131-148` |
| Alarms already emitted | `Alarmset.Alarm_cache` | `plugins/eva/src/alarmset.ml:221-227` |
| Red statuses per program point | `Red_statuses.RedStatusesTable` | `plugins/eva/src/utils/red_statuses.ml:48-55` |
| Degeneration points | `Eva_utils.DegenerationPoints` | `plugins/eva/src/utils/eva_utils.ml:22-29` |
| Main arguments and initial state given through the API | `Eva_results.MainArgs`, `Eva_results.VGlobals` | `plugins/eva/src/utils/eva_results.ml:29-53` |
| Per-function summary, statistics, timing | `Summary.FunctionStats`, `Statistics.IntState`, `Statistics.FloatState`, `Eva_perf.StatByCallstack` | `plugins/eva/src/utils/summary.ml:204-212`, `plugins/eva/src/utils/statistics.ml:173-191`, `plugins/eva/src/utils/eva_perf.ml:74-81` |
| Eva parameters | parameter states | `parameter_state.ml:103-107` |

- **[inferred]** For the rows other than `Domain_store` and
  `Do_Not_Marshal`, "saved" follows from the rule of section 1 and from the
  datatypes named in the registration. The marshallability of each element
  datatype (for instance `Alarms`, `Property`, `Callstack`) was not checked
  one by one.
- **[read]** Cvalue states are recorded only when `-eva-results` is on and
  the function is not listed in `-eva-no-results-function`
  (`function_calls.ml:12-13`, `domain_store.ml:83-93`,
  `plugins/eva/src/parameters.ml:371-389`). What was not recorded is not
  saved.

### Not saved

- **[read]** The memexec cache: `Mem_exec.PreviousCalls` is built on
  `Eva_utils.Do_Not_Marshal` (`plugins/eva/src/engine/mem_exec.ml:62-69`).
  It is also emptied at the end of each analysis (`mem_exec.ml:71-72`,
  `plugins/eva/src/engine/analysis.ml:117`).
- **[read]** The cached initial state of the analysis:
  `Initialization.InitialState` uses `Do_Not_Marshal`
  (`plugins/eva/src/engine/initialization.ml:410-417`).
- **[read]** States of a domain whose datatype is unmarshable. Eva then
  saves the `Save` flag as false and warns "Cannot save states of %s domain
  on disk" (`domain_store.ml:66-76`). Domains read to be in this case: Apron,
  with an explicit `t_unknown`
  (`plugins/eva/src/domains/apron/apron_domain.ml:356-362`), and domains
  built by the simple-domain functor, which uses `Datatype.Undefined`
  (`domain_builder.ml:185-197`). Other domains were not classified.
- **[read]** Per-statement slevel tables: `Per_stmt_slevel.ForKf` holds
  closures and uses `Datatype.Undefined`
  (`plugins/eva/src/partitioning/per_stmt_slevel.ml:33-50`,
  `per_stmt_slevel.ml:130-138`).
- **[read]** All hash-consing tables (section 1).
- **[read]** Caches kept in plain OCaml tables, for instance the binary
  operation caches cleared by `clear_caches`
  (`plugins/eva/src/engine/analysis.ml:12-25`).

### `plugins/eva/src/utils/eva_results.ml`

- **[read]** It has two parts. The first registers two saved states, the
  main arguments and the initial Cvalue state supplied through the API
  (`eva_results.ml:29-57`).
- **[read]** The second part is `get_results` and `set_results` over an
  abstract record `results` (`eva_results.ml:68-76`,
  `plugins/eva/src/utils/eva_results.mli:37-42`). This is an in-memory
  snapshot. The type has no datatype and no descriptor, and the module does
  no file input or output.
- **[read]** `get_results` copies: the Cvalue state per callstack at
  `Initial`, at the start of each function, and before and after each
  statement of each defined function (`eva_results.ml:78-109`); the callers
  and statuses of functions (`eva_results.ml:110`); the main arguments
  (`eva_results.ml:111`); the status of each alarm emitted by Eva
  (`eva_results.ml:119-125`); the statuses emitted by Eva on other properties
  (`eva_results.ml:126-141`).
- **[read]** `set_results` clears all states depending on `Self.state`,
  bumps the correctness counter, then writes back the main arguments, the
  states, the callers and statuses, re-registers the alarms, re-emits the
  statuses and marks the analysis as computed (`eva_results.ml:144-183`).
- **[read]** Left out by `get_results`:
  - states of every domain other than cvalue (only `Cvalue_results` is
    read, `eva_results.ml:82-87`);
  - the joined, callstack-independent table (only the per-callstack states
    are read, `eva_results.ml:86-95`);
  - statuses of `IPReachable` properties, with a `TODO` comment
    (`eva_results.ml:137-138`);
  - statuses not emitted by the Eva emitter (`eva_results.ml:112-117`);
  - red statuses, degeneration points, summaries, statistics, the initial
    Cvalue state `VGlobals`, the memexec cache: none is read in
    `get_results` (`eva_results.ml:78-142`).
- **[read]** A test says these two functions "are no longer used in Eva, but
  may still be used by third-party plugins"
  (`plugins/eva/tests/utils/get-set-results.t/test_get_set_results.ml:1-2`).
  The test uses them inside one process, on one AST, with two entry points.
- **[inferred]** `eva_results.ml` does not move results between processes.
  Its record holds `stmt`, `kernel_function` and Cvalue states of the current
  AST, so it has the same identity constraints as section 2.

## 4. Can Eva run again after `-load`

### Same AST

- **[read]** `Analysis.compute` does nothing when the analysis is already
  computed (`plugins/eva/src/engine/analysis.ml:275-283`). The user manual
  states the same: `frama-c -load foo.sav -eva` runs the analysis "if and
  only if it was not already computed at save time"
  (`doc/userman/user-services.tex:68-74`).
- **[read]** When Eva does run, it starts by clearing everything that
  depends on `Self.state` (`analysis.ml:68-69`, `self.ml:72-75`).
- **[read]** Setting a parameter to a different value clears every state
  that depends on it (`parameter_state.ml:186-198`,
  `parameter_state.ml:211-213`). The user manual gives the example
  `frama-c -load foo.sav -absolute-valid-range 0-0x2000`: the saved results
  are discarded and the analysis is recomputed on the same source code
  (`doc/userman/user-services.tex:120-133`).
- **[inferred]** So Eva can run again after `-load` on the saved AST, and it
  then starts from empty Eva states. The saved AST and kernel tables are
  reused. The saved Eva results are not.

### What clears Eva's states

- **[read]** `Self.state` is a proxy that depends on `Ast.self`,
  `Alarms.self` and `Annotations.code_annot_state` (`self.ml:31-37`;
  `Forward` means the proxy depends on the listed states,
  `src/lib/project/state_builder.mli:481-485`).
- **[read]** Every Eva parameter registered with `add_dep`,
  `add_correctness_dep` or `add_precision_dep` is added to the proxy
  (`plugins/eva/src/parameters.ml:34-48`), as are 17 kernel options
  (`parameters.ml:12-30`, `parameters.ml:50`).
- **[read]** `MainArgs` and `VGlobals` are added to the proxy
  (`eva_results.ml:39`, `eva_results.ml:53`).
- **[read]** The result tables, callers, statuses, red statuses, memexec and
  the other Eva states listed in section 3 declare `dependencies =
  [Self.state]` (for instance `domain_store.ml:58-63`,
  `function_calls.ml:15-20`, `mem_exec.ml:67`).
- **[read]** `Ast.mark_as_changed` clears all states depending on `Ast.self`
  except the "linked" states. `Ast.mark_as_grown` also keeps the "monotonic"
  states (`src/kernel/services/ast_data/ast.ml:54-70`). The developer manual
  requires this clearing, or a new project, for any AST modification
  (`doc/developer/advance.tex:2671-2686`).
- **[read]** Monotonic states include the kernel alarm table
  (`alarms.ml:336`), `MainArgs` (`eva_results.ml:38`) and the Eva
  initial-state cache (`initialization.ml:417`).
- **[inferred]** `Self.state` is neither linked nor monotonic, so both
  `mark_as_changed` and `mark_as_grown` clear the Eva result tables. Only
  whole-table clearing exists: a state's `clear` empties it for the project
  (`state_builder.ml:211-216`).
- **[read]** Property statuses of an emitter are also tied to the values of
  its correctness parameters
  (`src/kernel/services/plugin_entry_points/emitter.ml:313-328`). Eva uses a
  hidden counter parameter to force this reset when the initial state changes
  through the API (`parameters.ml:1150-1166`).

### Changed sources

- **[read]** Source files on a `-load` command line are ignored (section 2).
  The manual says files must be given after `-then`
  (`doc/userman/user-sources.tex:556-562`).
- **[read]** `Ast.self` depends on `Kernel.Files`
  (`src/kernel/services/ast_data/ast.ml:14-30`).
- **[inferred]** `frama-c -load s.sav -then new.c` sets `Kernel.Files`, which
  clears `Ast.self` and its dependents in the loaded project, Eva's states
  included. The new files are then parsed into a fresh AST. Nothing of the
  saved Eva results remains in that project. Not run.
- **[inferred]** A parameter is cleared and set only when the new value
  differs (`parameter_state.ml:211-213`). If the file list after `-then` is
  equal to the saved one, `Kernel.Files` does not change and the saved AST is
  kept, even if the file contents changed on disk. Not run.
- **[read]** `-ast-diff` is the one mechanism that relates a loaded AST to
  re-parsed sources. Before the files are set, it copies the current project
  into a project named `orig_<name>` and records it in `Orig_project`. After
  the files are set, it computes the new AST and fills correspondence tables
  (`src/kernel/services/ast_queries/ast_diff.ml:1551-1575`; the
  after-configuring hooks run before `set_files`,
  `cmdline.ml:742-754`, `cmdline.ml:933-944`).
- **[read]** The tables map an item of the original AST to `Same` item of
  the new AST, `Not_present`, or for statements and functions `Partial` with
  the kind of change (spec, body, callees)
  (`src/kernel/services/ast_queries/ast_diff.mli:20-41`,
  `ast_diff.ml:1371-1388`). There are tables for varinfos, statements,
  kernel functions, types and logic symbols (`ast_diff.mli:48-104`).
- **[read]** The user manual presents this as support "for future
  incremental analyses" and notes that parsing and type-checking are always
  redone (`doc/userman/user-sources.tex:546-565`).
- **[read]** No plug-in in `plugins/` refers to `Ast_diff`. The only users
  are the kernel and the test `tests/syntax/ast_diff_1.ml`.
- **[inferred]** With `-load s.sav -then -ast-diff new.c`, the `orig_`
  project is a full copy made by `Project.create_by_copy`
  (`ast_diff.ml:1560-1566`, `project.ml:752-766`), so it still holds the old
  AST and the old Eva states while the current project holds the new AST.
  Old results can then be read with `Project.on` and translated through the
  tables. Eva does not do this. Not run. Options given in the same `-then`
  step that are dependencies of `Ast.self` are set before the copy and may
  clear the AST first.

## 5. Compatibility checks on load

- **[read]** Version: the first value in the file is the seed
  `"Frama-C." ^ id_and_codename`, where `id_and_codename` is the version
  string and codename (`cmdline.ml:30-32`,
  `src/kernel/internals/runtime/system_config.ml.in:11-14`). The second is
  `magic = 9`. A mismatch on either raises `IOError "project saved with an
  incompatible version ..."` (`project.ml:673-687`), and `-load` aborts
  (`special_hooks.ml:93-97`). A truncated file gives "unexpected end of
  file" (`project.ml:697-702`).
- **[inferred]** Two builds with the same version string and codename, for
  instance two commits of 35~dev, pass this check. The check does not cover
  the commit, the OCaml version or the plug-in set.
- **[read]** Per state, by unique name (`project.ml:230-260`):
  - on disk and in memory, same type digest: loaded
    (`state_builder.ml:265-284`);
  - on disk and in memory, different digest: the state is cleared and
    `Incompatible_datatype` is raised (`state_builder.ml:285-288`); after all
    states are read, the states depending on it are cleared with the warning
    "N state(s) in memory reset to their default value"
    (`project.ml:247-252`, `project.ml:275-292`);
  - on disk but unknown to the loading binary (plug-in absent): ignored with
    the warning "N state(s) in saved file ignored" (`project.ml:263-270`);
    its bytes are read with a dummy descriptor (`project.ml:619-624`);
  - in memory but not on disk (plug-in added): silently left at its default
    value (`project.ml:253-259`).
- **[read]** The digest of a type is the MD5 of its name alone when the type
  is unmarshable, otherwise of its name, structural descriptor and
  representants (`src/lib/datatype/type.ml:73-80`).
- **[inferred]** For a type declared `t_abstract`, the digest does not
  reflect the OCaml definition. A layout change under an unchanged name and
  unchanged representants is not detected. `unmarshal.mli` states that its
  checks are partial (`src/lib/datatype/unmarshal.mli:20-33`).
- **[read]** Options: parameters are states, so they are restored with the
  project. Options given on the loading command line are parsed after the
  loading stage and override them (`cmdline.ml:929-934`;
  `doc/userman/user-services.tex:64-65`). There is no check that options
  match. A changed option clears its dependents (section 4).
- **[read]** A correctness parameter recorded by an emitter that no longer
  exists gives the warning "correctness parameter %s does not exist anymore.
  Ignored." (`emitter.ml:315-328`).
- **[read]** After a load, projects referenced from loaded states but not
  present are removed from those states, with the warning "clearing dangling
  project pointers" (`project.ml:187-210`, `project.ml:603-616`).

## 6. Data stored outside the saved session

Written and read back by another process:

- **[read]** Audit file. `-audit-prepare <path>` writes JSON with the source
  files and their checksums; `-audit-check <path>` reads it and warns on
  mismatch (`kernel.ml:1029-1060`). Eva adds its correctness parameters and
  compares them on check (`plugins/eva/src/utils/eva_audit.ml:11-60`,
  `plugins/eva/src/engine/analysis.ml:96`). It carries configuration and
  checksums, not analysis results.
- **[read]** WP proof cache. `-wp-cache` has modes none, update, cleanup,
  replay, rebuild and offline; entries live in the WP session directory or in
  `-wp-cache-dir` (`plugins/wp/src/wp_parameters.ml:654-689`). An entry is a
  JSON file named after a digest of the prover and the goal, read with
  `Json.load_file` and written with `Json.save_file`
  (`plugins/wp/src/Cache.ml:122-153`, `Cache.ml:201-227`). This is the only
  result cache found that is keyed by content and not by AST ids.
- **[read]** Session files themselves used as an external store: the mthread
  fixpoint can call `Project.save` at each iteration
  (`plugins/eva/src/mthread/mt_analysis_fixpoint.ml:242-251`).

Written only (nothing in the repository reads them back into an analysis):

- **[read]** `-eva-flamegraph <file>`, `-eva-report-red-statuses <csv>`,
  `-eva-statistics-file <csv>`
  (`plugins/eva/src/parameters.ml:1059-1069`, `parameters.ml:1099-1110`,
  `parameters.ml:1113-1121`).
- **[read]** `-report-csv` (`plugins/report/src/report_parameters.ml:64`)
  and the markdown and SARIF reports, which the manual shows being produced
  from a loaded session (`plugins/markdown-report/src/mdr_params.ml:20-32`,
  `doc/userman/user-analysis-scripts.tex:375`).
- **[read]** Eva values exported as ACSL assertions on l-values read by the
  code, with `-eva-annot` (`plugins/eva/src/parameters.ml:1279-1288`,
  `plugins/eva/src/utils/export.mli:15-45`).
- **[inferred]** Such assertions printed with `-print` would be parsed again
  by a later run as ordinary annotations to verify, not as trusted results.
  Not run.

Not found:

- **[read]** No Eva option stores or loads analysis states in a separate
  file. A search for options with `save`, `load`, `dump`, `export`, `json`
  or `csv` in `plugins/eva/src/parameters.ml` returns only the three
  write-only options above.

## Facts that bear on the later decision

- **[read]** A saved session is an all-or-nothing image tied to one AST. Its
  granularity is the state: a state is loaded whole or reset whole.
- **[inferred]** Reusing Eva results of version N on version N+1 through
  `-load` requires both ASTs in one process (`-ast-diff` gives that, in two
  projects) and a translation of every `stmt`, `varinfo`, `kernel_function`
  and `Base` in the reused values. The kernel gives the correspondence
  tables. No translation of Cvalue states exists.
- **[inferred]** A separate store would need its own keys independent of
  `vid` and `sid`, and its own serialization of Cvalue states, since their
  descriptors embed `Base` and `varinfo` by pointer.
- **[read]** The memexec cache, the natural unit of per-call reuse, is
  deliberately unmarshallable and is emptied after each analysis.

## Not checked

- Nothing was executed. Every described behaviour of `-load`, `-then` and
  `-ast-diff` comes from reading code.
- The published manual PDFs were not fetched. Only their LaTeX sources in
  this repository were read.
- Marshallability of each element datatype of the Eva tables (`Alarms`,
  `Property`, `Callstack`, `Locals_scoping`, red-status keys) was not checked
  one by one.
- Eva domains other than cvalue, Apron and the simple-domain functor were
  not classified as saved or not saved (octagons, equality, gauges, symbolic
  locations, multidim, taint, traces, inout, numerors, mthread).
- `plugins/eva/src/mthread` states and the server plug-in's
  `Project.load` and `Project.save` requests were not read beyond the cited
  lines.
- The full dependency list of `Ast.self` (some dependencies are added later
  in the kernel) and which preprocessing options trigger a re-parse.
- Whether `Kernel.Files` compares paths or contents was deduced from the
  generic parameter code only.
- `Ast_diff` was read for its interface, its entry points and one
  correspondence function. Its precision and its treatment of statements
  were not studied.
- The cost of loading (re-interning every hptmap node) and the size of
  saved sessions.
- The interaction of `-load` with `Project.load ~selection` (loading a
  subset of states) was not explored.
- The Ivette and GUI paths for saving and loading.
- The two articles cited by the developer manual on the datatype library and
  on unmarshalling were not read.
