# What stays stable across two parses of a program in Frama-C

Research note for issue #4. Source tree: Frama-C 35~dev, commit `71986dadcb`.
All paths are relative to the repository root.

Method: code reading only. Frama-C was not built or run. Each claim is tagged:

- **[read]**: the cited lines state it.
- **[inferred]**: a conclusion drawn from the cited lines, not observed at run time.

## Summary

Every bullet here is **[inferred]** from the sections below, which carry the
evidence.

- Every numeric identifier in the AST (`vid`, `sid`, `eid`, `annot_id`, `ip_id`,
  `it_id`, `ext_id`, `ckey`, `lv_id`) is the next value of a process-global
  counter. Nothing in the allocation is random, so two runs with the same
  sources, command line and plug-in set should give the same numbers
  **[inferred]**. Any difference in what is parsed before an entity shifts its
  number. Ids cannot identify an entity in version N+1.
- Names are more stable than ids. Function and global variable names survive.
  Local names survive unless a global with the same name stem appears anywhere
  in the program, or a same-named local is added before it in its function.
  Several generated names carry a counter scoped to the translation unit or to
  the whole process.
- An Eva `Base` is identified by the `vid` of its variable. `Null` is the only
  base with a fixed identity. Heap base names embed the caller name and a source
  line.
- Properties and alarms are identified by ids of annotations, statements and
  expressions.
- The kernel has one facility that maps an old AST to a new one: `Ast_diff`
  (option `-ast-diff`). It matches globals by name and function bodies by
  position. It needs the old AST as a live project, which across processes means
  `-load` of a saved session. No plug-in in the tree consumes its tables.

## 1. Identifier allocation

### Counters

| Id | Counter | Where allocated |
|---|---|---|
| `vid` (varinfo) | `Vid`, `src/kernel/services/ast_queries/cil_const.ml:77` | `Cil.makeVarinfo` calls `set_vid`, `src/kernel/services/ast_queries/cil.ml:171`, `src/kernel/services/ast_queries/cil_const.ml:85-87` |
| `lv_id` (logic var) | same `Vid` counter | `src/kernel/services/ast_queries/cil_const.ml:169-171` |
| `sid` (stmt) | `Sid`, `src/kernel/services/ast_queries/cil_const.ml:78` | `src/kernel/internals/typing/cfg.ml:134` |
| `eid` (exp) | `Eid`, `src/kernel/services/ast_queries/cil_const.ml:79` | `Cil.new_exp`, `src/kernel/services/ast_queries/cil.ml:40` |
| `annot_id`, `ip_id`, `it_id`, `ext_id` | four counters, `src/kernel/services/ast_queries/logic_const.ml:17-24` | `src/kernel/services/ast_queries/logic_const.ml:26-48` |
| `ckey` (compinfo) | `src/kernel/services/ast_queries/cil_const.ml:107-111` | `mkCompInfo`, `src/kernel/services/ast_queries/cil_const.ml:134` |
| string literal number | `src/kernel/services/ast_queries/cil.ml:4374-4398` | one per literal variable |
| usable emitter id | `src/kernel/services/plugin_entry_points/emitter.ml:177-178` | |
| alarm rank | `src/kernel/services/ast_data/alarms.ml:300` | `src/kernel/services/ast_data/alarms.ml:372` |

All **[read]**.

- `SharedCounter` is one OCaml `ref 0` shared by all projects. `next` increments
  it. `src/lib/project/state_builder.ml:834-869` **[read]**
- On loading a saved state the counter becomes the maximum of the saved and the
  current value. `src/lib/project/state_builder.ml:843-849` **[read]** So a
  session that loads version N and then parses version N+1 gives N+1 ids above
  all ids of N **[inferred]**.
- `Alarms.Rank` and `Origin.Id.Counter` use `State_builder.Counter`, which is
  per project and starts at 0. `src/lib/project/state_builder.mli:526-529`
  **[read]**
- The `Vid` counter also numbers absolute-address bases.
  `src/kernel/services/abstract_interp/base.ml:207-213` **[read]**

### Statement ids

- Cabs2cil builds statements with `sid = -1`.
  `src/kernel/internals/typing/cabs2cil.ml:27`,
  `src/kernel/services/ast_queries/cil.ml:87-94` **[read]**
- `Cfg.cfgStmt` assigns a fresh sid to each statement whose sid is -1, in
  traversal order. `src/kernel/internals/typing/cfg.ml:134-135` **[read]**
- Each call to `cfgFun` also consumes one sid for `smaxstmtid`.
  `src/kernel/internals/typing/cfg.ml:99-101` **[read]**
- `prepare_cil_file` first clears every sid and renumbers the whole file.
  `src/kernel/services/ast_queries/file.ml:1290`,
  `src/kernel/internals/typing/cfg.ml:286-304` **[read]**
- Later recomputations keep existing sids and number only new statements.
  `src/kernel/services/ast_queries/file.ml:1312-1323` **[read]**
- With `Kernel.SimplifyCfg`, each function is cleared and renumbered once more
  when it is registered. `src/kernel/services/ast_queries/file.ml:993-996`
  **[read]**
- The type documentation only promises that a sid is "unique in a function".
  `src/kernel/services/ast_data/cil_types.ml:1121-1123` **[read]**

### Same ids in two processes?

- The allocation reads no clock, pid or random source. Two processes given the
  same preprocessed text, the same command line and the same set of loaded
  plug-ins should produce the same ids. **[inferred]**, not run.
- The kernel treats sid values as something tests depend on.
  `src/kernel/services/ast_queries/cil.ml:88-93` **[read]**
- The kernel avoids depending on vid order where it can: function iteration is
  alphabetical "so that iteration stays independent from vid numbering scheme".
  `src/kernel/services/ast_data/globals.ml:180-186` **[read]**
- A search of the `.tex` sources under `doc/userman`, `doc/developer` and
  `doc/eva` for `sid`, `vid`, `eid` and `identifier` found no sentence that
  promises id stability across runs **[read]** (search result). The developer
  manual lists ids as the indices that link a copy to its original inside one
  session. `doc/developer/advance.tex:3748-3771` **[read]**

### What makes ids diverge

All of the following follow from the counters being global and sequential.
**[inferred]** from the cited lines.

- **Any edit.** One more expression, variable or statement shifts the id of
  everything allocated after it, in every later function and file.
- **File order.** Files are converted and merged in command-line order with the
  same counters. `src/kernel/services/ast_queries/file.ml:797-811`
- **Preprocessing.** The preprocessor command carries the machdep header
  directory, the Frama-C libc directory, `-D`/`-U` options and extra arguments.
  `src/kernel/services/ast_queries/file.ml:544-556`,
  `src/kernel/services/ast_queries/file.ml:588-602` A header change alters the
  number of entities created before user code.
- **Libc.** With `Kernel.FramaCStdLib` the libc headers are on the include
  path. `src/kernel/services/ast_queries/file.ml:545` Their declarations get
  ids before removal of unused globals at
  `src/kernel/services/ast_queries/file.ml:1301`.
- **Options.** `Kernel.SimplifyCfg` and `Kernel.KeepSwitch`
  (`src/kernel/services/ast_queries/file.ml:993-994`), unused-global retention
  and the entry point name (`src/kernel/services/ast_queries/file.ml:767-786`),
  constant folding (`src/kernel/services/ast_queries/file.ml:1263-1286`).
- **Code transformations.** The kernel and plug-ins register transformations
  that run before or after cleanup and create nodes.
  `src/kernel/services/ast_queries/file.ml:1235-1261`,
  `src/kernel/services/ast_queries/file.ml:1298`,
  `src/kernel/services/ast_queries/file.ml:1334` Registrations seen (for example
  `src/kernel/services/ast_transformations/variadic/variadic.ml:61`): variadic
  translation, inlining, loop unfolding, statement contract inlining,
  destructors, exception removal in the kernel; `instantiate` and
  `acsl-importer` among plug-ins. The loaded plug-in set therefore matters.
- **Static symbols.** The merger gives a renamed static variable a new vid.
  `src/kernel/internals/typing/mergecil.ml:2590-2604` **[read]**
- **Analysis-time variables.** Eva creates variables during the analysis from
  the same counter. `plugins/eva/src/utils/eva_utils.ml:37-42` Their vids
  depend on analysis order.
- **Loading.** After `-load`, new ids start above the loaded maximum (above).

`FRAMAC_DETERMINISTIC` switches hash-consing tables from weak to non-weak. It
does not touch id allocation. `src/lib/project/state_builder.ml:814-821`,
`src/lib/project/state_builder.mli:302-313` **[read]**

## 2. Names after normalisation

`vorig_name` keeps the source name and "need not be unique".
`src/kernel/services/ast_data/cil_types.ml:638-639` **[read]**

### Locals and formals

Two passes set the name.

1. Cabs2cil, per translation unit.
   - One alpha table, cleared in `startFile`, which `convFile` calls once per
     file. `src/kernel/internals/typing/cabs2cil.ml:927`,
     `src/kernel/internals/typing/cabs2cil.ml:1050-1056`,
     `src/kernel/internals/typing/cabs2cil.ml:10415-10419` **[read]**
   - A local is renamed against that table. The change is recorded on the
     outermost scope of the enclosing function and undone when that scope
     closes. `src/kernel/internals/typing/cabs2cil.ml:970-997`,
     `src/kernel/internals/typing/cabs2cil.ml:3575-3590` **[read]**
   - A clash produces `<name>_<n>` with the first free `n`.
     `src/kernel/internals/typing/alpha.ml:159-174` **[read]**
2. After the link, `Cil.uniqueVarNames` renames again.
   `src/kernel/internals/typing/mergecil.ml:3344` **[read]**
   - It registers the name of every global variable and function of the merged
     program. `src/kernel/services/ast_queries/cil.ml:6397-6415` **[read]**
   - For each function it renames formals, then locals, starting from
     `vorig_name`, and undoes the changes at the end of the function.
     `src/kernel/services/ast_queries/cil.ml:6418-6459` **[read]**

Result **[inferred]**: the final name of a local is a function of its source
name, the order of formals and locals in its own function, and the set of
global names of the whole program that share its name stem. It does not depend
on other functions' locals. Adding a global `i` in any file renames a local `i`
to `i_0`.

### Temporaries

- Cabs2cil temporaries are named from the stem `tmp` (`g_tmp` in ghost code),
  have `vtemp = true` and a `vdescr`.
  `src/kernel/internals/typing/cabs2cil.ml:1176-1195` **[read]** They go
  through the same two passes as locals, so their numbering follows the order
  of creation in the function **[inferred]**.
- The single-return variable is `__retres`.
  `src/kernel/internals/typing/oneret.ml:194` **[read]**
- Variables made by `Cil.makeLocalVar` and `makeTempVar` (default stem
  `__cil_tmp`) get a suffix from the per-function counter `smaxid` on a clash.
  `src/kernel/services/ast_queries/cil.ml:4247-4264`,
  `src/kernel/services/ast_queries/cil.ml:4285-4286` **[read]**
- Loop unfolding names copies `<name>_unfold_<n>` with a process-global
  counter. `src/kernel/internals/typing/unfold_loops.ml:87-99` **[read]**

### Globals, statics, types, literals

| Entity | Generated name | Scope of the counter or clash | Evidence |
|---|---|---|---|
| Static local | `<function>_<name>`, then alpha at global scope | enclosing function name, plus global names of the file | `src/kernel/internals/typing/cabs2cil.ml:8799-8806` **[read]** |
| Static global, clash across files | `<name>_<n>` | all files, in file order | `src/kernel/internals/typing/mergecil.ml:2590-2603` **[read]** |
| Inline definition | `<name>__fc_inline` | none | `src/kernel/internals/typing/cabs2cil.ml:10400-10407` **[read]** |
| Anonymous struct, union, enum | `__anon<kind>[_<hint>]_<n>` | counter per translation unit, headers included | `src/kernel/internals/typing/cabs2cil.ml:1040-1044`, `src/kernel/internals/typing/cabs2cil.ml:1056` **[read]** |
| Compound literal | `__constr_expr_<n>` | counter per translation unit | `src/kernel/internals/typing/cabs2cil.ml:5877-5878`, `src/kernel/internals/typing/cabs2cil.ml:10461` **[read]** |
| String literal | `__fc_lit_string<n>`, `__fc_lit_wstring<n>` | process-global counter | `src/kernel/services/ast_queries/cil.ml:4374-4398` **[read]** |

- Since 32.0 a string literal is a global const array variable.
  `src/kernel/services/ast_data/cil_types.ml:951-956` **[read]** Each
  occurrence in the source creates its own variable.
  `src/kernel/internals/typing/cabs2cil.ml:5709`,
  `src/kernel/internals/typing/cabs2cil.ml:5732`,
  `src/kernel/internals/typing/cabs2cil.ml:9001-9005` **[read]** The number in
  the name counts every literal parsed before it in the process, headers
  included **[inferred]**.
- Functions and non-static globals keep their source name **[inferred]**: the
  renaming branch of the merger is taken only for `Static` storage
  (`src/kernel/internals/typing/mergecil.ml:2590`).

### Generated functions

- Variadic specialisation: `<name>_va_<n>`, `n` counted per variadic function
  over the whole program.
  `src/kernel/services/ast_transformations/variadic/standard.ml:460-462`,
  `src/kernel/services/ast_transformations/variadic/classify.ml:162` **[read]**
- Variadic fallback: `<name>_fallback_<n>`.
  `src/kernel/services/ast_transformations/variadic/standard.ml:188-190`
  **[read]**
- Clone: `__fc_clone_<n>_<name>`, process-global counter.
  `src/kernel/services/ast_transformations/clone.ml:14-17` **[read]**

### Labels

- User labels keep their name; a duplicate is an error.
  `src/kernel/internals/typing/cabs2cil.ml:2371-2377` **[read]**
- Cabs2cil generated labels use the alpha table with kind `label`, undone per
  function: `__Cont`, and copies suffixed `_LAND` / `_LOR`.
  `src/kernel/internals/typing/cabs2cil.ml:2279`,
  `src/kernel/internals/typing/cabs2cil.ml:2289`,
  `src/kernel/internals/typing/cabs2cil.ml:7746-7751` **[read]**
- CFG preparation generates `switch_<n>_...`, `while_<n>_break`,
  `while_<n>_continue`. `n` is incremented on entering each nested switch or loop,
  and uniqueness comes from a label table cleared for each function.
  `src/kernel/internals/typing/cfg.ml:311-315`,
  `src/kernel/internals/typing/cfg.ml:497`,
  `src/kernel/internals/typing/cfg.ml:615`,
  `src/kernel/internals/typing/cfg.ml:422-426`,
  `src/kernel/internals/typing/cfg.ml:619-621`,
  `src/kernel/internals/typing/cfg.ml:731-734` **[read]**
- Oneret generates `return_label`.
  `src/kernel/internals/typing/oneret.ml:303` **[read]**
- Loop unfolding generates `[<label>_]unfolding_<n>_loop` with a process-global
  counter. `src/kernel/internals/typing/unfold_loops.ml:73-82` **[read]**

Function of the enclosing function only: locals, temporaries, cabs2cil and CFG
labels, `__retres`, except for clashes with global names. Function of the whole
file or process: anonymous types, compound literals, string literals, unfolding
labels and copies, clones, variadic specialisations, static clashes.
**[inferred]**

## 3. Eva bases

`Base` is defined in the kernel, not in Eva **[read]** (file path below).

```
type base =
  | Var of varinfo * validity
  | CLogic_Var of logic_var * typ * validity
  | Null
  | Absolute of absolute_range
  | Allocated of varinfo * deallocation * validity
```
`src/kernel/services/abstract_interp/base.ml:100-105` **[read]**

- Identity is one integer: `vid` for `Var` and `Allocated`, `lv_id` for
  `CLogic_Var`, 0 for `Null`, a private id for `Absolute`.
  `src/kernel/services/abstract_interp/base.ml:107-111` **[read]**
- `hash`, `compare` and `equal` use only that integer.
  `src/kernel/services/abstract_interp/base.ml:113`,
  `src/kernel/services/abstract_interp/base.ml:144`,
  `src/kernel/services/abstract_interp/base.ml:404` **[read]**
- Maps and sets over bases are Patricia trees keyed by that integer.
  `src/kernel/services/abstract_interp/base.ml:497-509`,
  `src/lib/utils/hptmap.mli:31-33` **[read]** The shape of every memory state
  therefore depends on vids **[inferred]**.

| Base | Constructor | Identity | Name | Embeds |
|---|---|---|---|---|
| Global, local, formal | `Var`, memoised per source varinfo, `src/kernel/services/abstract_interp/base.ml:525-528`, `src/kernel/services/abstract_interp/base.ml:562-569` | vid | `vname` | an id; no line, no call stack |
| String literal | `Var` on the literal variable, `src/kernel/services/abstract_interp/base.ml:119-121` | vid | `__fc_lit_string<n>`; printed as its content, `src/kernel/services/abstract_interp/base.ml:128-129` | an id and a counter |
| Heap, VLA, alloca | `Allocated`, `src/kernel/services/abstract_interp/base.ml:550-554` | vid of a variable created during analysis | see below | an id, a source line, a caller name |
| Null | constant, `src/kernel/services/abstract_interp/base.ml:115` | 0 | `NULL` | nothing |
| Absolute range | `src/kernel/services/abstract_interp/base.ml:207-213` | value of the vid counter at creation | address | an id |
| Eva hidden base | `Var`, non-source, `src/kernel/services/abstract_interp/base.ml:544-548` | vid | `S_<name>`, `WELL_<name>` | an id |

All **[read]**.

- The content of a string literal is reachable from its variable.
  `src/kernel/services/ast_data/globals.ml:54-62` **[read]** Two occurrences of
  the same text are two bases **[inferred]** from one variable per occurrence.

### Heap allocations

- The variable is created at analysis time with `vsource = false`.
  `plugins/eva/src/utils/eva_utils.ml:37-42`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:156-163` **[read]**
- Name: `__<prefix>_<caller>_l<line>`, `<prefix>` being `malloc` or `alloca`,
  with `_w` after the prefix for a weak base. `<line>` is the source line of the
  call site. `plugins/eva/src/domains/cvalue/builtins_malloc.ml:126-160`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:493-498` **[read]**
- The full call stack is not in the name: `full_name` is `false`.
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:148` **[read]**
- The name is made unique with `Cabs2cil.fresh_global`, which appends `_<n>` on
  a clash. `plugins/eva/src/domains/cvalue/builtins_malloc.ml:161`,
  `src/kernel/internals/typing/cabs2cil.ml:931-933` **[read]** The suffix
  depends on the order of allocations during the analysis **[inferred]**. The
  table behind `fresh_global` is a plain hash table of cabs2cil, cleared at the
  start of each parsed file (`src/kernel/internals/typing/cabs2cil.ml:927`,
  `src/kernel/internals/typing/cabs2cil.ml:1055`). It is not a project state,
  so the suffix also depends on what that table holds when the analysis runs,
  and nothing shows it being restored by `-load` **[inferred]**.
- The name is mutated when a base becomes weak, and the type and validity are
  mutated on resize.
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:169-178`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:417-440` **[read]**
- Call stacks are kept in side tables, not in the base: base to call stack, and
  call stack to list of bases.
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:50-61`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:88-93`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:405-413` **[read]**
- The default strategy, `by_stack`, reuses bases by call stack up to
  `MallocLevel`. `plugins/eva/src/parameters.ml:1216-1227`,
  `plugins/eva/src/domains/cvalue/builtins_malloc.ml:443-473` **[read]** An
  `eva_allocate` annotation on the call statement overrides it.
  `plugins/eva/src/utils/eva_annotations.ml:364-366` **[read]**
- A call stack is a thread number, an entry point and a list of (function,
  call statement) pairs. `plugins/eva/src/types/callstack.ml:20-24` **[read]**
  Its comparison goes through function and statement datatypes, which compare
  by id (section 6) **[inferred]**.

### Other Eva-created bases

- Initial state: `S_<name>` and `WELL_<name>`, made unique by `fresh_global`.
  `plugins/eva/src/domains/cvalue/cvalue_init.ml:134`,
  `plugins/eva/src/domains/cvalue/cvalue_init.ml:166`,
  `plugins/eva/src/domains/cvalue/cvalue_init.ml:320-328` **[read]**
- Eva creates one variable named `\result<f>` per function `f` with a non-void
  return type. `plugins/eva/src/utils/library_functions.ml:24-34` **[read]**
  Where it is used and how it becomes a base was not read.
- Garbled-mix origins embed a source location, not a statement, and a
  per-project counter id.
  `src/kernel/services/abstract_interp/origin.ml:30-37`,
  `src/kernel/services/abstract_interp/origin.ml:116` **[read]**

## 4. Generated annotations and properties

### Identity

- Code annotation: `annot_id`.
  `src/kernel/services/ast_queries/cil_datatype.ml:2494-2496` **[read]**
- Identified predicate: `ip_id`.
  `src/kernel/services/ast_queries/cil_datatype.ml:2549-2552` **[read]**
- Identified term: `it_id`.
  `src/kernel/services/ast_queries/cil_datatype.ml:2178-2183` **[read]**
- `Property.t` hashes and compares on a mix of ids and names. Ids: `ip_id`,
  `annot_id`, `ext_id`, `it_id`, the function (vid) and the statement (sid).
  Names: lemma, axiomatic, module, behaviour, type and global invariant,
  `IPOther`. `src/kernel/services/ast_data/property.ml:551-596`,
  `src/kernel/services/ast_data/property.ml:646-690` **[read]**

### Property names

- `Property.Names` builds a base name from the function name, behaviour name,
  clause kind and predicate names. A statement contributes `s<sid>`.
  `src/kernel/services/ast_data/property.ml:984-989`,
  `src/kernel/services/ast_data/property.ml:1002-1030` **[read]**
- The unique name adds `_<n>`, numbered in the order in which names are first
  requested. `src/kernel/services/ast_data/property.ml:1139-1156` **[read]**
- So a property name is stable only when it has no statement part and no
  duplicate base name **[inferred]**.

### Alarms

- An alarm is a kind plus expressions or lvalues.
  `src/kernel/services/ast_data/alarms.ml:24`,
  `src/kernel/services/ast_data/alarms.ml:114-170` **[read]** Its comparison
  uses `Exp.compare` and `Lval.compare`, which compare eids and vids.
  `src/kernel/services/ast_queries/cil_datatype.ml:632-634`,
  `src/kernel/services/ast_queries/cil_datatype.ml:1191-1193` **[read]**
- The alarm table is keyed by `Kinstr` (sid), then emitter, then alarm.
  `src/kernel/services/ast_data/alarms.ml:302-314` **[read]**
- The first registration of an alarm at a statement creates a code annotation
  with a fresh `annot_id`. `src/kernel/services/ast_data/alarms.ml:684-710`,
  `src/kernel/services/ast_queries/logic_const.ml:26-27` **[read]**
- Each registration takes a rank from a per-project counter.
  `src/kernel/services/ast_data/alarms.ml:369-374` **[read]**
- RTE and Eva register alarms through the same function.
  `plugins/rte/src/visit.ml:408`, `plugins/eva/src/alarmset.ml:266` **[read]**
- The stable part of an alarm is its kind and the structure of its expression.
  Its statement, its expression identity and its annotation id are counters
  **[inferred]**.

### Generated specifications

- `Populate_spec` builds predicates with fresh `ip_id`s and adds the
  specification under the emitter "Populated spec".
  `src/kernel/internals/typing/populate_spec.ml:62-63`,
  `src/kernel/internals/typing/populate_spec.ml:171`,
  `src/kernel/internals/typing/populate_spec.ml:893` **[read]**
- Annotations generated by the single-return transformation are recorded in
  `File.Implicit_annotations`.
  `src/kernel/services/ast_queries/file.ml:827-834`,
  `src/kernel/services/ast_queries/file.ml:1003-1010` **[read]**

Stability is the same as in section 1: these ids are counter values.
**[inferred]**

## 5. Order

### Globals

- Files are parsed and merged in command-line order.
  `src/kernel/services/ast_queries/file.ml:799-811` **[read]**
- The merged file lists type definitions first, then the other globals in
  merge order. `src/kernel/internals/typing/mergecil.ml:655-657`,
  `src/kernel/internals/typing/mergecil.ml:3325-3333`,
  `src/kernel/services/ast_queries/cil.ml:6480`,
  `src/kernel/services/ast_queries/cil.ml:6502-6506` **[read]**
- Unused globals are then removed according to options.
  `src/kernel/services/ast_queries/file.ml:767-786`,
  `src/kernel/services/ast_queries/file.ml:1301` **[read]**
- A string literal added after parsing is inserted before the first variable or
  function global. `src/kernel/services/ast_data/globals.ml:73-90` **[read]**
- `File.reorder_ast` exists and is applied only on request.
  `src/kernel/services/ast_queries/file.ml:1755-1759`,
  `src/kernel/services/ast_queries/file.ml:1945-1946` **[read]**
- `Globals.Functions.iter` is alphabetical by name, then by vid.
  `src/kernel/services/ast_data/globals.ml:180-186`,
  `src/kernel/services/ast_data/globals.ml:315` **[read]** It is independent of
  file order **[inferred]**.
- `Globals.Vars` is a hash table keyed by varinfo. File order is available
  through `iter_in_file_order`.
  `src/kernel/services/ast_data/globals.ml:44-50`,
  `src/kernel/services/ast_data/globals.ml:152-153` **[read]**

### Statements in a function

- `sallstmts` is the list of statements in CFG traversal order, parent before
  children, siblings in block order.
  `src/kernel/internals/typing/cfg.ml:99-101`,
  `src/kernel/internals/typing/cfg.ml:113-135` **[read]**
- After the first full renumbering, sids increase along that order. Statements
  added later (single return, annotation synchronisation, transformations) get
  larger sids wherever they sit. `src/kernel/services/ast_queries/file.ml:1312-1323`
  **[read]** Sid order is therefore not textual order in general **[inferred]**.
- The position of a statement in the block tree of its function is the only
  ordering that does not involve a counter **[inferred]**. `Ast_diff` matches
  statements that way (section 6).

## 6. Existing tools

### 6.1 `Ast_diff` and `-ast-diff`

- Introduced in 25.0 as a "Prototype of AST comparison between two versions of
  the same program". `Changelog:733-734`,
  `src/kernel/services/ast_queries/ast_diff.mli:9-12` **[read]**
- Option: `src/kernel/services/plugin_entry_points/kernel.ml:732-739` **[read]**
- User manual, section "Incremental parsing (experimental)": the difference is
  computed between an AST loaded with `-load` and the AST of the current
  sources, "is stored by the Frama-C kernel and can be used by plug-ins which
  support it". Parsing and type-checking are still done in full; the comparison
  is on normalised ASTs. `doc/userman/user-sources.tex:544-566` **[read]**

**How it works**

- At the configuring stage it copies the current project into `orig_<name>` and
  stores it as the original project.
  `src/kernel/services/ast_queries/ast_diff.ml:1560-1568` **[read]**
- After the files are set it computes the AST of the current project and walks
  the globals of the original AST.
  `src/kernel/services/ast_queries/ast_diff.ml:1551-1554`,
  `src/kernel/services/ast_queries/ast_diff.ml:1570-1575` **[read]**
- Candidates are looked up in the current project by name: typedefs, structs,
  unions, enums, global variables, functions.
  `src/kernel/services/ast_queries/ast_diff.ml:324-362` **[read]** Renaming is
  not detected: "TODO: use location info to detect potential renaming".
  `src/kernel/services/ast_queries/ast_diff.ml:322-323` **[read]**
- Functions: return type and formals are compared by position, then the
  specification, then the body.
  `src/kernel/services/ast_queries/ast_diff.ml:1378-1403` **[read]**
- Bodies: blocks are compared statement by statement in order. Locals are
  paired by position and compared by type and attributes, not by name.
  `src/kernel/services/ast_queries/ast_diff.ml:1156-1174`,
  `src/kernel/services/ast_queries/ast_diff.ml:1223-1229` **[read]**
- Statements: ghost status, attributes, `case` and `default` labels, kind,
  annotations. Plain labels are left out of this comparison.
  `src/kernel/services/ast_queries/ast_diff.ml:1062-1080`,
  `src/kernel/services/ast_queries/ast_diff.ml:1082-1113` **[read]**
- Expressions: structure, with variables resolved through the correspondence
  tables. `src/kernel/services/ast_queries/ast_diff.ml:937-982` **[read]**

**What it produces**

- Hash tables keyed by entities of the original AST, with the entity of the
  current AST as data: `Varinfo`, `Compinfo`, `Enuminfo`, `Enumitem`,
  `Typeinfo`, `Stmt`, `Logic_info`, `Logic_type_info`, `Logic_ctor_info`,
  `Fieldinfo`, `Model_info`, `Logic_var`, `Kernel_function`, `Fundec`.
  `src/kernel/services/ast_queries/ast_diff.mli:48-104` **[read]** Direction:
  the key function is fetched in the original project and the candidate in the
  current one. `src/kernel/services/ast_queries/ast_diff.ml:395-399`,
  `src/kernel/services/ast_queries/ast_diff.ml:1374-1376`,
  `src/kernel/services/ast_queries/ast_diff.ml:1418` **[read]**
- Data: `` `Same x ``, `` `Not_present ``, and for functions and statements
  `` `Partial (x, c) `` with `c` one of `Spec_changed`, `Body_changed`,
  `Callees_changed`, `Callees_spec_changed`.
  `src/kernel/services/ast_queries/ast_diff.mli:20-41` **[read]**
- Locals of a function enter the `Varinfo` table only when its body is
  unchanged or only its callees changed.
  `src/kernel/services/ast_queries/ast_diff.ml:1211-1220` **[read]**

**Guarantee**

- `` `Same `` means the comparison above found the specification and the body
  equal. `src/kernel/services/ast_queries/ast_diff.ml:242-252` **[read]**
- No soundness or completeness statement was found in the manual section, the
  Changelog entry or the interface cited above **[read]** (those three texts
  only). The Changelog says prototype and the manual says experimental.
- A statement moved, a local reordered or a symbol renamed is reported as a
  change **[inferred]** from positional and by-name matching.

**Across processes**

- It works across two processes only through a saved session:
  `frama-c -load previous.sav -then -ast-diff file1.c file2.c`.
  `doc/userman/user-sources.tex:556-562` **[read]**
- The original AST must be a live project in the session. The original project
  is a `Project.t` reference and the comparison reads the original state with
  `Project.on`. `src/kernel/services/ast_queries/ast_diff.ml:11-16`,
  `src/kernel/services/ast_queries/ast_diff.ml:1086-1088`,
  `src/kernel/services/ast_queries/ast_diff.ml:1360-1362` **[read]** It cannot
  compare against a result file that does not carry the old AST **[inferred]**.
- The tables depend on `Ast.self` and the original project.
  `src/kernel/services/ast_queries/ast_diff.ml:148-153` **[read]**

**Users in the tree**

- A search for `Ast_diff`, `AstDiff` and `ast-diff` over the tree finds the
  module, the option, `acsl_extension` (hook to compare ACSL extensions,
  `src/kernel/services/ast_queries/acsl_extension.mli:44-48`), the manual and
  the test `tests/syntax/ast_diff_1.ml`. No plug-in reads the tables; Eva does
  not. **[read]** (search result)
- The test runs `-then -ast-diff` on a second file inside one process.
  `tests/syntax/ast_diff_1.i:5-6` **[read]**

### 6.2 `Cil_datatype` comparisons

- Default datatypes compare by id: `Stmt` by sid, `Exp` by eid, `Varinfo` by
  vid, `Compinfo` by ckey, `Fundec` and `Kf` by the vid of the function.
  `src/kernel/services/ast_queries/cil_datatype.ml:242-244`,
  `src/kernel/services/ast_queries/cil_datatype.ml:632-634`,
  `src/kernel/services/ast_queries/cil_datatype.ml:705-707`,
  `src/kernel/services/ast_queries/cil_datatype.ml:738-740`,
  `src/kernel/services/ast_queries/cil_datatype.ml:2664-2666`,
  `src/kernel/services/ast_queries/cil_datatype.ml:2678` **[read]**
- Structural modules: `ExpStructEq`, `LvalStructEq`, `OffsetStructEq` and their
  `Strict` / `Sized` variants, `PredicateStructEq`, `Logic_info_structural`.
  `src/kernel/services/ast_queries/cil_datatype.mli:86-114`,
  `src/kernel/services/ast_queries/cil_datatype.mli:150-169`,
  `src/kernel/services/ast_queries/cil_datatype.mli:274`,
  `src/kernel/services/ast_queries/cil_datatype.mli:306` **[read]**
- They compare the shape of the term. Their leaves are still ids: variables by
  vid, struct types by ckey.
  `src/kernel/services/ast_queries/cil_datatype.ml:1040`,
  `src/kernel/services/ast_queries/cil_datatype.ml:453-456` **[read]**
- Guarantee: equality of two expressions of the same AST up to their eids.
  They do not relate two parses, because the leaves differ **[inferred]**.
- `TypByName` and `Logic_type_ByName` compare struct types by name without
  unrolling. `src/kernel/services/ast_queries/cil_datatype.mli:195-196`,
  `src/kernel/services/ast_queries/cil_datatype.mli:282` **[read]** They do not
  depend on ckey, so they could compare types of two parses **[inferred]**.

### 6.3 Copy visitors and projects

- A copy visitor keeps maps between original and copied nodes, queried with
  `Get`, `Get_orig`, `Set`, `Set_orig`, indexed by the ids listed in the
  developer manual. `doc/developer/advance.tex:3726-3771`,
  `src/kernel/services/visitors/visitor_behavior.mli:26-41` **[read]**
- `File.create_project_from_visitor` builds a new project from such a visitor.
  `src/kernel/services/ast_queries/file.ml:1960-1974` **[read]**
- Scope: one session, two projects, the new AST derived from the old one. Not a
  comparison of two independent parses **[inferred]**.

### 6.4 Lookups by name

- `Globals.Functions.find_by_name`, `find_all_by_orig_name`.
  `src/kernel/services/ast_data/globals.ml:374-378` **[read]**
- `Globals.Vars.find_from_astinfo` (name and syntactic scope).
  `src/kernel/services/ast_data/globals.ml:97` **[read]**
- `Ast_diff` finds its candidates with `find_by_name` and `find_from_astinfo`.
  `src/kernel/services/ast_queries/ast_diff.ml:354-362` **[read]**

### 6.5 Save and load

- `-save` writes all projects; `-load` restores them and replays the saved
  parameters. `doc/userman/user-services.tex:46-66` **[read]**
- The loaded AST keeps its ids, and counters continue above them
  (section 1) **[inferred]**. This is the only way found to have version N's
  entities present in the process that parses version N+1.

### 6.6 Other items

- Call stack stable hash: built from function names, file path and line of call
  sites, reduced to four base-58 characters. Used for printing.
  `plugins/eva/src/types/callstack.ml:137-151`,
  `plugins/eva/src/types/callstack.mli:29-30` **[read]** It survives
  renumbering but changes when a call site moves to another line, and it can
  collide **[inferred]**.
- Source audit: digests of all source files, written and checked through
  `Kernel.AuditPrepare` and `Kernel.AuditCheck`. It detects that a file
  changed, at file granularity.
  `src/kernel/services/ast_queries/file.ml:1811-1837`,
  `src/kernel/services/ast_queries/file.ml:1854-1888`,
  `src/kernel/services/ast_queries/file.ml:1917-1922` **[read]**
- Server markers embed vid, sid or a session counter.
  `plugins/server/src/kernel_ast.ml:188-208` **[read]** They are as unstable as
  those ids **[inferred]**.

## Candidate keys for a second parse

**[inferred]** from the sections above; a starting point for the later decision.

| Entity | Unstable | Usable key |
|---|---|---|
| Function | vid | name; for a static one, name plus defining file |
| Global variable | vid | same as function |
| Formal | vid | function and position |
| Local, temporary | vid; `vname` when a global with the same stem appears | function, `vorig_name`, rank among declarations (what `Ast_diff` does by position) |
| Statement | sid | function and path in the block tree |
| Expression | eid | statement and structure |
| String literal base | vid, name counter | content and place of occurrence |
| Heap base | vid, clash suffix, line in the name | allocation call site, truncated call stack, rank in the per-stack list |
| `Null` | none | itself |
| Property, alarm | annotation, statement and expression ids; name suffix | function, statement key, kind, structure of the predicate |

## Not checked

- Nothing was executed. Determinism of ids across two processes is inferred
  from the code; no pair of runs was compared.
- The public PDF manuals were not fetched. The in-tree sources of the user and
  developer manuals (`doc/userman`, `doc/developer`) were read instead. The
  plug-in development guide is at
  <https://frama-c.com/download/frama-c-plugin-development-guide.pdf> (URL
  taken from `src/kernel/services/ast_data/cil_types.ml:630`).
- Whether any id allocation happens while iterating an OCaml `Hashtbl`, which
  would make the order depend on hashing.
- How many ids kernel initialisation consumes (machdep, builtins, logic
  builtins) and whether it varies with machdep.
- `rmtmps.ml`: only its call site was read, not how it treats names or order.
- `mergecil.ml`: only the static renaming, the output order and the call to
  `uniqueVarNames` were read. Merging of types, anonymous types, inline
  functions and logic declarations was not.
- Whether file locations stored in the AST are absolute or relative paths.
- How the `\result<f>` variable becomes a base.
- The keys of Eva's result tables and of its other domains; only bases, call
  stacks and alarms were examined.
- Whether Eva results stored with `-save` are still usable after `-ast-diff`
  replaces the AST in the same session.
- Plug-ins other than Eva, and RTE beyond its alarm registration call.
- `Ast_diff` on logic declarations and on ACSL extensions beyond the hook.
