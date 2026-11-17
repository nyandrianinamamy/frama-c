# Consumers of Eva's per-statement results after the main analysis

Research note for issue #2 of `nyandrianinamamy/frama-c`.

- Code read at commit `71986dadcb` (Frama-C 35~dev). Nothing was built or run.
- All paths are relative to the repository root.
- Each claim is tagged **[code]** (read at the cited line) or **[inferred]** (deduced from code that was read, not observed).
- The four facts listed as already verified in the ticket are cited as given and were not re-derived.

## Answer

1. A function body with no stored state does not always read as bottom. The answer is chosen by the function's recorded analysis status before the store is consulted: `Analyzed NoResults` reads as top, every other status reads as bottom when the store has no entry (`plugins/eva/src/engine/engine.ml:150-165`) **[code]**. Top means reachable for `Results.is_reachable` (`plugins/eva/src/utils/results.ml:268-271`), but `Results.is_empty`, `callstacks` and `by_callstack` return "no callstack" on top exactly as on bottom (`results.ml:142-152,256-266,753-755`) **[code]**.
2. If the body reads as bottom, the first consumer to go wrong is Eva's own `mark_unreachable`: it emits a valid status on every annotation of the body and an invalid status on the reachability of each (`plugins/eva/src/legacy/eval_annots.ml:41-60`) **[code]**. For a body that was reached in the earlier session this is a wrong verdict **[inferred]**.
3. Consumers fall into four groups by what they need:
   - **Reachability only**: `mark_unreachable`, coverage in Summary, Metrics, markdown-report, Nonterm, the `getDeadCode` request. A saved set of reached statements is enough. Nonterm and `getDeadCode` also need "state after the statement is empty", and Nonterm needs it per callstack.
   - **Statuses and alarms only**: Summary alarm counts, Red_statuses report, the `properties` request, RTE. A saved alarm list with statuses is enough.
   - **A derived per-function or per-call summary**: From, Inout, Mthread events, and through them PDG of the callers, Scope and the memexec cache. They do not need the states, but they need their own summary of the body (assigns, inputs and outputs). The verdict listed in the ticket (alarm list, statuses, reached statements) does not contain it.
   - **The states themselves**: `mark_green_and_red`, PDG of the body, Slicing, Sparecode, Impact, Studia, Dive, Occurrence, Constant propagation, WP `MemVal`, Loop analysis, Reduc, Export, and the value, state and taint requests of the server.
4. Alarms, annotations and statuses of an earlier session persist after `-save`/`-load`, and they also survive a new Eva run unless a correctness parameter of the Eva emitter changes. Eva's stored states do not survive a new run: `pre_analysis` clears them.

## How a missing state reads

| Situation | `Before stmt` / `After stmt` reads as | Evidence |
|---|---|---|
| Eva not computed | top | `plugins/eva/src/engine/engine.ml:151,165` **[code]** |
| Status `Unreachable`, `SpecUsed`, `Builtin` | bottom | `engine.ml:162` **[code]** |
| Status `Analyzed NoResults` | top | `engine.ml:163` **[code]** |
| Status `Analyzed Complete` or `Partial`, no entry in the store | bottom | `engine.ml:164`, `plugins/eva/src/domains/domain_store.ml:103-112` **[code]** |
| Domain store not saved (`-eva-results` off, `-eva-no-results-domain`, or unmarshalable domain after load) | top | `domain_store.ml:65-78,89-90,101,113`, `plugins/eva/src/parameters.ml:83-86,383-386` **[code]** |

- The status comes from the analysis target chosen at each call: `Body (def, save_results def)` gives `Analyzed Complete` or `Analyzed NoResults` (`plugins/eva/src/engine/function_calls.ml:106-111,156`) **[code]**.
- `save_results` is computed from the parameters `-eva-results` and `-eva-no-results-function` (`plugins/eva/src/parameters.ml:372-386`), not from the stored status (`function_calls.ml:12-13`, `plugins/eva/src/engine/analysis.ml:164-166`) **[code]**. From, Inout and PDG call it directly, so a body skipped by a new mechanism would still answer "results are saved" to them unless that mechanism changes this function **[inferred]**.
- `Eva.Results.are_available kf` is true only for `Analyzed Complete` or `Partial` (`plugins/eva/src/utils/results.ml:11-15`) **[code]**.
- A request with no callstack selection turns top into an evaluation in the top state of the domains, not into an error (`results.ml:121-125,240-249`) **[code]**. Values, addresses and callees on a top body are therefore whatever the evaluation gives in a top state; what that is for each kind of expression was not traced.
- A request by callstack, `callstacks` and `is_empty` see an empty list on top and on bottom alike (`results.ml:127-138,142-152,256-266,753-755`) **[code]**.
- The consolidated state of a statement is computed on demand as the join of the per-callstack states; with no callstack it is bottom (`engine.ml:48-63`, `domain_store.ml:118-122`) **[code]**.
- The state at the start of the callee is registered at every call before the call is computed, so it exists on a memexec hit as well (`plugins/eva/src/engine/transfer_stmt.ml:285-290`) **[code]**.
- The truth values of conditions are in a separate table; a missing entry reads as `(false, false)`, which means neither branch was taken (`plugins/eva/src/engine/iterator.ml:24-35`) **[code]**.
- Callers and call sites are in a separate table filled at each call, including a memexec hit (`function_calls.ml:26-54`, `plugins/eva/src/engine/compute_functions.ml:191`) **[code]**. Calls made from inside a body that is not iterated are not registered **[inferred]**.

### Precedents already in the code

- **`-eva-no-results-function`**: the body is analysed, no state is stored, statements read as top. Consumers that handle it explicitly: `getDeadCode` returns empty lists (`plugins/eva/src/server_api/ast_requests.ml:130`), Nonterm skips the function (`plugins/nonterm/src/nonterm_run.ml:200`), From returns top assigns (`plugins/from/src/from_compute.ml:549`), Inout returns top (`plugins/inout/src/operational_inputs.ml:730-731`), PDG returns a top PDG (`plugins/pdg/src/build.ml:922-926,996`), the callwise hooks of From and Inout return top (`plugins/from/src/callwise.ml:126-128`, `operational_inputs.ml:647-651`) **[code]**.
- **Memexec hit inside one session**: the body is not iterated, so no state is registered for the reusing callstack; states are registered only by the iterator (`plugins/eva/src/engine/iterator.ml:598-604`), not on the reuse path (`compute_functions.ml:57-74`) **[code]**. The consolidated state stays sound because the same input was analysed under another callstack **[inferred]**. Dive documents the missing callstacks (`plugins/dive/src/build.ml:250-258`) **[code]**.
- **`Eva_results.get_results` / `set_results`**: copies cvalue states by callstack, the callers table, alarms with statuses, and other statuses, then restores them and sets the analysis to `Computed` (`plugins/eva/src/utils/eva_results.ml:78-142,144-183`) **[code]**. Reachability statuses are not copied (`eva_results.ml:137-138`) **[code]**. Its only user in the repository is a test (`plugins/eva/tests/utils/get-set-results.t/test_get_set_results.ml:15,20`) **[code]**.

## Gap 1: redundant-alarm removal in Scope

Entry: `Eva_dynamic.Scope.rm_asserts` (`plugins/eva/src/utils/eva_dynamic.ml:40-41`) calls the function registered at `plugins/scope/src/datascope.ml:629-635` **[code]**.

Reads, in order:

| Step | What is read from Eva | Evidence |
|---|---|---|
| Function filter | `Eva.Results.are_available kf`; other functions are skipped | `datascope.ml:571-574` **[code]** |
| Zone of the assertion | cvalue state before the assertion's statement, through the kernel hook `Logic_deps.compute_term_deps` that Eva installs | `datascope.ml:432`, `src/kernel/services/analysis/logic_deps.ml:17,378-386`, `plugins/eva/src/legacy/logic_inout.ml:28-32` **[code]** |
| Statements that write | for each statement of the function: `is_reachable`; unreachable statements register no write | `datascope.ml:122-126` **[code]** |
| Written zone of an assignment or initialisation | address of the left value, for writing, before the statement | `datascope.ml:71-72,84-89,100-102` **[code]** |
| Written zone of a call | callees evaluated before the statement, then `Inout.get_precise_inout ~stmt kf` and its `over_outputs` | `datascope.ml:79-81,104-110` **[code]** |
| Escaping addresses on a block exit | cvalue state before the source statement of the edge, only when the edge closes a block with referenced locals | `datascope.ml:334-346` **[code]** |
| Dominance and predicate equality | none (kernel `Dominators`, syntactic comparison) | `datascope.ml:467-484,529` **[code]** |

- Write: status `True` on the redundant assertion, with the dominating assertion as hypothesis, under a separate emitter `RedundantAlarms` (`datascope.ml:601-606,618-624`) **[code]**. The annotation is not removed.
- `zones.ml` and `defs.ml` are not on this path; they reference `Datascope` only for its logging module (`plugins/scope/src/zones.ml:11`, `plugins/scope/src/defs.ml:18-21`) **[code]**.
- `Inout.get_precise_inout` is `Operational_inputs.get_internal_aux` (`plugins/inout/src/Inout.ml:18`, `plugins/inout/src/operational_inputs.ml:815`). With `~stmt` it looks up the callwise table for this call site first, then falls back to the functionwise result (`operational_inputs.ml:479-487`) **[code]**.

## Gap 2: From, Inout, other plugins, server requests, callwise hooks

### Callwise hooks and what `` `Reuse `` gives

- Hook types: `plugins/eva/src/utils/cvalue_callbacks_sig.ml:23-27` (`analysis_kind`) and `:45-55` (`call_results`). `` `Body `` carries lazy tables of cvalue states before and after each statement and an integer id; `` `Reuse `` carries only the id of an earlier `` `Body `` **[code]**.
- The id comes from `Mem_exec.new_counter`, issued when the body results are merged (`plugins/eva/src/engine/iterator.ml:610-611`) **[code]**.
- On a memexec hit the hooks are called with `` `Reuse `` at `plugins/eva/src/engine/compute_functions.ml:58,72`; preconditions of the callee are re-evaluated at the call site in between (`compute_functions.ml:59-69`) **[code]**.
- Statement hooks fire only from the iterator (`iterator.ml:380-384`), so they do not fire on reuse. Their two users are internal: dynamic widen hints (`plugins/eva/src/utils/widen.ml:533`) and watchpoints (`plugins/eva/src/domains/cvalue/builtins_watchpoint.ml:121`) **[code]**.

| Hook user | On `` `Body `` | On `` `Reuse i `` | Evidence |
|---|---|---|---|
| From callwise | recompute dependencies from the before-states, store under the id | `MemExec.find i` in its own table | `plugins/from/src/callwise.ml:55-63,87-95,120-145` **[code]** |
| Inout callwise | recompute inputs and outputs from the before-states, store under the id | `MemExec.find i` in its own table | `plugins/inout/src/operational_inputs.ml:563-567,593-601,642-670` **[code]** |
| Mthread | record events from before and after states, store under the id | lookup in `analysis.memexec_cache` | `plugins/eva/src/mthread/mt_analysis_hooks.ml:857-872` **[code]** |
| Summary | recompute the function's statistics | nothing | `plugins/eva/src/utils/summary.ml:215-221` **[code]** |

- From and Inout id tables depend on their own result tables, which depend on `Eva.Analysis.self` (`callwise.ml:12-19,87-95`, `operational_inputs.ml:186-206,593-601`) **[code]**. They are cleared when Eva's state is cleared **[inferred]**. A `` `Reuse i `` whose `` `Body `` was recorded in an earlier analysis would find no entry **[inferred]**.
- The Inout hook result is pushed back into Eva (`operational_inputs.ml:580`, `plugins/eva/src/engine/transfer_stmt.ml:13-25`). Eva uses it for backward propagation on arguments (`transfer_stmt.ml:305-312`) and to build the memexec cache key; with no Inout result nothing is cached (`plugins/eva/src/engine/mem_exec.ml:129-133`) **[code]**.
- The memexec cache is not written to disk (`mem_exec.ml:62-69`, `plugins/eva/src/utils/eva_utils.ml:98-104`) **[inferred from the `Do_Not_Marshal` wrapper over `Datatype.Undefined`]** and is cleared at the end of each analysis (`plugins/eva/src/engine/analysis.ml:117`, `mem_exec.ml:71-72`) **[code]**.

### From (functionwise)

- States come from `Eva.Results.before stmt` (`plugins/from/src/functionwise.ml:24`) **[code]**.
- Per statement: dependencies of expressions and addresses (`plugins/from/src/from_compute.ml:203-217`), callees (`from_compute.ml:309-311`), value of a condition (`from_compute.ml:447-448`), reachability of the statement and of each successor (`from_compute.ml:501-517`) **[code]**.
- Return statement unreachable: result is "Non-terminating function (no dependencies)" with a bottom memory (`from_compute.ml:580-598`) **[code]**.
- `save_results kf` false: top assigns (`from_compute.ml:549`) **[code]**.
- Computed for functions with `is_called` (`functionwise.ml:80-84`); table depends on `Eva.Analysis.self` (`functionwise.ml:11-18`) **[code]**.

### Inout (functionwise)

- States from `Eva.Results` at each statement and at function start (`plugins/inout/src/operational_inputs.ml:706-708`) **[code]**.
- A statement whose state is bottom is skipped (`operational_inputs.ml:443-448`) **[code]**.
- `save_results kf` false: top (`operational_inputs.ml:729-731`) **[code]**.
- Other analyses of the plugin read per statement: `plugins/inout/src/inputs.ml:35-60`, `plugins/inout/src/outputs.ml:38-58,87`, `plugins/inout/src/derefs.ml:28` **[code]**.

### PDG and its clients

- PDG per statement: addresses and dependencies (`plugins/pdg/src/build.ml:461,592-603,618`), callees and dependencies of the function expression (`build.ml:687-688`), callwise From for the call site, else functionwise From of each callee (`build.ml:689-701`), condition dependencies and truth value (`build.ml:736-740`), reachability (`build.ml:758,776,797,801,851`) **[code]**.
- Entry statement unreachable: bottom PDG with a warning (`build.ml:961-973,993-995`). `save_results kf` false: top PDG (`build.ml:922-926,996`) **[code]**.
- Annotations: only at reachable statements, zones through `Logic_deps` (`plugins/pdg/src/annot.ml:94-98`) **[code]**.
- Slicing: `plugins/slicing/src/slicingSelect.ml:96,185`, `slicingCmds.ml:44-46,74-104,180,206,376-377`, `slicingTransform.ml:40,229,461`, `fct_slice.ml:43,133,1445`, `slicingMacros.ml:62,165`, `api.ml:169`, `printSlice.ml:198`, `slicingProject.ml:219` **[code]**.
- Sparecode: `plugins/sparecode/src/transform.ml:76,122,151` **[code]**.
- Impact: `plugins/impact/src/compute_impact.ml:323,445,529` **[code]**.
- Security slicing: `plugins/security_slicing/src/components.ml:361,388,450,492,615` **[code]**.
- Scope, other features: `plugins/scope/src/defs.ml:53,123,158,190,210`, `plugins/scope/src/zones.ml:29,56-60,142-153` **[code]**.

### Other plugins

| Plugin | Read | Evidence |
|---|---|---|
| Studia | addresses before a statement, callees, call sites, cvalue state for logic terms | `plugins/studia/src/writes.ml:56,63,82,133`, `reads.ml:35,49,57`, `studia_request.ml:87-93` **[code]** |
| Dive | values, addresses, callees, callstacks, taint, before and after a statement | `plugins/dive/src/build.ml:82-111,244-264,339,371,466` **[code]** |
| Occurrence | address of each left value before the statement | `plugins/occurrence/src/register.ml:92-95` **[code]** |
| Constant propagation | cvalue of an expression before the statement | `plugins/constant_propagation/src/api.ml:122-123` **[code]** |
| WP | cvalue state before a `kinstr`, used by `MemVal` | `plugins/wp/src/wp_eva.enabled.ml:9-10`, `plugins/wp/src/MemVal.ml:658-671` **[code]** |
| RTE | status of the function only; `Analyzed _` means "Eva covers this function" and generation is skipped | `plugins/rte/src/eva_analysis.enabled.ml:11-15`, `visit.ml:375`, `generator.ml:58-61` **[code]** |
| Nonterm | status, reachability per statement, emptiness of the after-state per callstack, `are_available` | `plugins/nonterm/src/nonterm_run.ml:168-178,185-189,198-208,232-236,275-291` **[code]** |
| Metrics | reachability per statement, `is_called` | `plugins/metrics/src/metrics_coverage.ml:203-205,239,259` **[code]** |
| markdown-report | reachability per statement, callees | `plugins/markdown-report/src/eva-info/eva_info.ml:85,103` **[code]** |
| Loop analysis | interval of a variable before a statement | `plugins/loop_analysis/src/loop_analysis.ml:328-340` **[code]** |
| Reduc | interval of an expression or left value before a statement | `plugins/reduc/src/value2acsl.ml:149,154` **[code]** |
| Callgraph | call sites | `plugins/callgraph/src/cg.ml:196` **[code]** |
| Aorai | evaluation in a state handed to a builtin during the analysis, not a stored state | `plugins/aorai/src/aorai_eva_analysis.enabled.ml:42` **[code]** |

No use of Eva was found in `src/` apart from the `Logic_deps` hook, nor in the plugins `alias`, `region` (their `Analysis` modules are their own), `e-acsl`, `server`, `report`, `instantiate`, `acsl-importer`, `api-generator`, `obfuscator`, `volatile` (search for `Eva.`, `Results.`, `Analysis.` over `*.ml`, test directories excluded) **[code, by search]**.

### Server requests (`plugins/eva/src/server_api`)

| Request | Read | Evidence |
|---|---|---|
| `getCallers`, `getCallees` | call sites table; callees evaluated before the statement | `ast_requests.ml:27,48` **[code]** |
| `getDeadCode` | status, then emptiness of before and after states per statement | `ast_requests.ml:122-141` **[code]** |
| `properties`, `priority` | property statuses, red-status table | `ast_requests.ml:163-182` **[code]** |
| `getStates` | printed states before and after a statement | `analysis_requests.ml:116-133` **[code]** |
| `clear` | clears Eva results and both Eva emitters | `analysis_requests.ml:60-66` **[code]** |
| `getProbeInfo`, `getValues` | reachability, values before and after, by callstack | `value_requests.ml:43-46,126-145,509-512,597-617` **[code]** |
| callstack requests | status, callstacks at function start and before a statement | `callstack_requests.ml:120-124,169-198` **[code]** |
| taint requests | taint state before and after a statement | `taint_requests.ml:55-65,148-165,240,268-295` **[code]** |
| `programStats`, `functionStats` | Summary tables | `stats_requests.ml:197,227` **[code]** |
| Inout requests | enabled on `is_computed` | `plugins/inout/src/inout_requests.ml:25-34` **[code]** |

## Gap 3: remaining users of the results interface

- **Legacy `Db.Value`-style access**: no read of Eva results through `Db` in source directories, and no `db.ml` or `db.mli` file exists in the repository **[code, by search]**. Every match of `Db.Value`, `Db.From` or `!Db.` under `plugins` and `src`:
  - `plugins/studia/src/reads.ml:46`: inside a comment (lines 43-47) **[code]**.
  - `plugins/slicing/src/printSlice.ml:126`, `plugins/slicing/src/slicingCmds.ml:400`, `plugins/aorai/src/Aorai.ml:15`: comments **[code]**.
  - `plugins/slicing/src/slicingTypes.ml:108`: text of a format string **[code]**.
  - `plugins/security_slicing/src/components.ml:773`: live source text `!Db.Pdg.self`, a state dependency, not a result read **[code]**. With no `Db` module in the repository this cannot resolve; the plugin's library is `optional` (`plugins/security_slicing/src/dune:29-31`), and whether it is built was not checked.
  - `plugins/slicing/tests/slicing/libSelect.ml:69-70` (`Db.Value.is_called`, `!Db.From.compute`) and `plugins/slicing/tests/slicing/anim.ml:17`: test sources **[code]**.
- **Dynamic access to Eva by name**: no `Dynamic.get` on plugin `Eva` outside Eva (search for `plugin:"Eva"`, `plugin:"Value"`) **[code, by search]**.
- **Inside Eva, after the analysis**:

| Consumer | Read | Evidence |
|---|---|---|
| `mark_unreachable` | reachability of each annotated statement, of each call statement, of each return statement | `plugins/eva/src/legacy/eval_annots.ml:56,67,107` **[code]** |
| `mark_green_and_red` | reachability, start state of the function, before-state per callstack, states at C labels per callstack | `eval_annots.ml:115-129,133-154,181` **[code]** |
| Summary | reachability per statement, Eva statuses of alarms | `plugins/eva/src/utils/summary.ml:147-181,257-281` **[code]** |
| Red_statuses report | its own table, filled during the analysis with the current callstack, and consolidated statuses | `plugins/eva/src/utils/red_statuses.ml:48-74,104-112,161,191` **[code]** |
| Consolidation of states | joins per-callstack states, only for `Analyzed Complete` functions | `plugins/eva/src/engine/engine.ml:77-100` **[code]** |
| Cvalue final-state display | store read directly for the first and return statements, bypassing the status check | `plugins/eva/src/domains/cvalue/cvalue_domain.ml:394-418` **[code]** |
| Logic `\at(_, Init)` | initial state read directly from the cvalue store | `plugins/eva/src/legacy/eval_terms.ml:202-205` **[code]** |
| Mthread interferences | after-state per callstack, between thread analyses | `plugins/eva/src/engine/concurrency/interferences.ml:222-227` **[code]** |
| Export (`-eva-annot`) | `are_available`, emptiness and values before each statement | `plugins/eva/src/utils/export.ml:217-231,309-319` **[code]** |
| `Eva_results` | whole cvalue store, callers, alarms, statuses | `plugins/eva/src/utils/eva_results.ml:78-142` **[code]** |

- `Cvalue_results` is the cvalue instance of the store (`plugins/eva/src/domains/cvalue/cvalue_results.ml:9-12`) and is re-exported in `Eva.Private` (`plugins/eva/src/utils/private.ml:24`) **[code]**. Reads through it do not go through the status check of `engine.ml:150-165` **[code]**. No use of `Eva.Private` was found outside Eva **[code, by search]**.

## What each consumer writes

| Consumer | Writes | Evidence |
|---|---|---|
| `mark_unreachable`, `mark_green_and_red` | property statuses under the Eva emitter | `plugins/eva/src/legacy/eval_annots.ml:46-51,193-198` **[code]** |
| Scope `rm_asserts` | property statuses under the `RedundantAlarms` emitter; a table of zones modified by block exits | `plugins/scope/src/datascope.ml:372-378,601-606,623-624` **[code]** |
| Summary | per-function statistics table and the exported statistics | `plugins/eva/src/utils/summary.ml:204-224,283-286` **[code]** |
| From | functionwise and callwise tables of assigns | `plugins/from/src/functionwise.ml:11-18,66-69`, `plugins/from/src/callwise.ml:12-19,49-53` **[code]** |
| Inout | per-function and per-call-site tables | `plugins/inout/src/operational_inputs.ml:542-554` **[code]** |
| PDG | a table of PDGs, co-dependent with From | `plugins/pdg/src/register.ml:13-18` **[code]** |
| Export | code annotations under the `Eva_export` emitter | `plugins/eva/src/utils/eva_utils.ml:19`, `plugins/eva/src/utils/export.ml:289,309-319` **[code]** |
| Slicing, Sparecode | a new project; alarms are not carried over | `plugins/slicing/src/slicingTransform.ml:229-231`, `plugins/sparecode/src/transform.ml:75-78` **[code, from the comments]** |
| Metrics | a per-function coverage table | `plugins/metrics/src/metrics_coverage.ml:216,243` **[code]** |
| Server requests | nothing, except `compute`, `abort` and `clear` | `plugins/eva/src/server_api/analysis_requests.ml:44-72` **[code]** |

Not read: what RTE, Constant propagation, Impact, Studia, Occurrence, Dive, Nonterm, Loop analysis and Reduc write. From the code read they produce annotations (RTE, Loop analysis, Reduc), a new project (Constant propagation), or in-memory results and messages (the others) **[inferred]**.

## Gap 4: persistence across `-save` / `-load` and a new run

**What is in a saved project**

- A projectified state is written unless its datatype is unmarshalable (`src/lib/project/state_builder.ml:240,298-304`) **[code]**.
- Eva's stores are projectified hash tables depending on `Self.state` (`plugins/eva/src/domains/domain_store.ml:58-63,80-87`). A domain with an unmarshalable state saves its `Save` flag as false, with a warning (`domain_store.ml:68-78`), so it reads as top after load **[code for the flag, inferred for the effect]**.
- Function status and callers tables (`plugins/eva/src/engine/function_calls.ml:15-24,89`), computation state (`plugins/eva/src/self.ml:42-63`), condition truth values (`plugins/eva/src/engine/iterator.ml:24-31`), red statuses (`plugins/eva/src/utils/red_statuses.ml:48-55`), function statistics (`plugins/eva/src/utils/summary.ml:204-212`) are projectified states **[code]**; that each is actually written was not checked **[inferred]**.
- Alarms, code annotations and property statuses are kernel tables indexed by emitter (`src/kernel/services/ast_data/alarms.ml:312`, `annotations.ml:126`, `property_status.ml:146`, built by `src/kernel/services/plugin_entry_points/emitter.ml:497-610`) **[code]**; they are saved with the project **[inferred]**.
- The memexec cache is not saved (see Gap 2).

**After load**

- If the saved computation state is `Computed` or `Aborted`, `Analysis.compute` does nothing (`plugins/eva/src/engine/analysis.ml:275-283`, `plugins/eva/src/self.ml:67-70`) **[code]**. The stored states are then readable as before **[inferred]**.
- Eva runs again only when `Self.state` has been cleared. It is cleared with the dependents of any of its dependencies: the AST, the alarms table, the code annotations (`self.ml:31-37`), and each registered parameter (`plugins/eva/src/parameters.ml:34-48`); setting a parameter clears its dependents (`src/kernel/services/cmdline_parameters/parameter_state.ml:186-198`) **[code]**.

**What a new run does to the earlier results**

- `pre_analysis` calls `Self.clear_results`, which clears `Self.state` and everything depending on it (`analysis.ml:69`, `self.ml:72-75`) **[code]**. This covers Eva's stores, the function tables, and the tables of From, Inout, Scope, Occurrence, Metrics and the others that declare `Eva.Analysis.self` as dependency (for example `plugins/from/src/functionwise.ml:17`, `plugins/scope/src/datascope.ml:376`) **[inferred]**.
- Alarms, annotations and statuses are not cleared by it. `Self.state` depends on them, not the reverse (`self.ml:31-37`, `src/lib/project/state_builder.mli:481-485`) **[code]**. The code says so in three places: "does reset the state of Eva, but *not* the property statuses set by Eva" (`plugins/eva/src/parameters.ml:1162-1165`); an alarm "emitted ... by a previous run of Eva would be considered as not new" (`plugins/eva/src/alarmset.ml:268-270`); "this is possible for an 'old' alarm" (`plugins/eva/src/legacy/eval_annots.ml:207-209`) **[code]**. The server `clear` request has to call `Emitter.clear` explicitly (`plugins/eva/src/server_api/analysis_requests.ml:60-66`) **[code]**.
- They are removed when a correctness parameter of the emitter changes: the parameter state is made a dependency of the tables of the emitter's kinds (`emitter.ml:315-319`), and the tables' clear function removes the bindings of emitters that have the selected correctness parameter (`emitter.ml:550-601`) **[code]**. Eva's emitter has kinds `Property_status` and `Alarm` (`plugins/eva/src/utils/eva_utils.ml:13-18`) **[code]**.
- A tuning parameter change creates a new version of the usable emitter and removes nothing (`emitter.ml:334-346`) **[code]**. How the consolidation treats statuses of the older version was not checked.

**What Eva does with an earlier alarm when it runs again** (same usable emitter)

| Case | Effect | Evidence |
|---|---|---|
| Raised again | existing annotation is returned; new status is merged with `distinct:true`: a new `Dont_know` replaces an old `True`, a new `True` does not replace an old `Dont_know` | `alarms.ml:338-340,716-735`, `property_status.ml:311-320,493-498` **[code]** |
| Not raised again, statement reached | `mark_green_and_red` re-evaluates every alarm annotation at reachable statements and emits `True` when it evaluates to true; otherwise the old status stays | `eval_annots.ml:177-181,204-210` **[code]** |
| Statement not reached | `mark_unreachable` emits `True` on the property and `False_and_reachable` on its reachability, with `distinct:false`: `True` replaces `Dont_know`; `True` against an earlier false status becomes `False_if_reachable` | `eval_annots.ml:41-60`, `property_status.ml:247-258,493-501` **[code]** |

- A red status on an alarm is never emitted as a property status; it is kept in the red-status table and the status is `Dont_know` (`plugins/eva/src/alarmset.ml:252`, as given in the ticket; lines 253-263 read here) **[code]**.
- `mark_unreachable` skips properties whose status is computed automatically by the kernel (`eval_annots.ml:43`, `property_status.ml:693-696`) **[code]**.

## Gap 5: conclusion of each consumer for a body with no stored state

"Bottom" is the case where the function's status is `Analyzed Complete` or `Partial` (or not `Analyzed`) and the store has no entry. "Top" is the `Analyzed NoResults` case. Conclusions are **[inferred]** from the cited code unless a line shows the case handled explicitly.

| Consumer | Body reads as bottom | Body reads as top | Saved verdict enough? |
|---|---|---|---|
| `mark_unreachable` | every annotation, every call precondition and the normal postconditions of the body get `True`, with reachability false (`eval_annots.ml:41-113`) | nothing emitted | Yes: reached statements |
| `mark_green_and_red` | skipped (`eval_annots.ml:181`) | per-callstack list is empty, result `Unknown`, nothing emitted (`eval_annots.ml:139-153`, `results.ml:127-132,148-152`) | Yes for keeping saved statuses; no for refining them |
| Scope `rm_asserts`, in the body | function is entered; no statement registers a write (`datascope.ml:122-126`). If the zone of an assertion can still be computed on a bottom state (not traced), every assertion identical to a dominating one is marked valid (`datascope.ml:527-536`) | function skipped (`datascope.ml:571-574`) **[code]** | Yes: saved statuses of the `RedundantAlarms` emitter |
| Scope `rm_asserts`, in a caller | written zone of the call comes from Inout of the callee (`datascope.ml:79-81`) | same | No: needs the callee's outputs |
| Summary, Statistics | no per-function entry is created without a `` `Body `` result, so the function counts as not reached and its alarms are not counted (`summary.ml:215-224,296-305`); statuses at its statements are not counted (`summary.ml:262-268`) | statements counted as reached | Yes: per-function coverage and alarm counts |
| Red_statuses report | no entry for the body | same | Yes: saved red-status table |
| Cvalue final-state display | not printed (`cvalue_domain.ml:400-405`) | not printed | Needs one state (at the return statement) |
| From, Inout, Mthread hooks on `` `Reuse `` | lookup by id in their own tables; no entry for an id from an earlier analysis | same | No: needs the saved per-call summary |
| From functionwise | "Non-terminating function (no dependencies)", bottom memory (`from_compute.ml:580-598`); a caller's From then becomes bottom after the call (`from_compute.ml:332-335`) **[code]** | top assigns: `save_results` is false whenever the status is `NoResults` (`from_compute.ml:549`) **[code]** | No: needs saved assigns per function |
| Inout functionwise | every statement skipped, empty inputs and outputs (`operational_inputs.ml:443-448`) | top: `save_results` is false whenever the status is `NoResults` (`operational_inputs.ml:729-731`) **[code]** | No: needs saved inputs and outputs per function |
| PDG of the body | bottom PDG (`build.ml:961-973,993-995`) **[code]** | top PDG (`build.ml:922-926,996`) **[code]** | No: needs states, or a saved PDG |
| PDG of a caller | uses From of the callee at the call (`build.ml:689-701`); a bottom memory makes the PDG state after the call bottom (`build.ml:559-560,652-653`) **[code]** | top dependencies | No: needs saved assigns of the callee |
| Slicing, Sparecode | annotations of the body dropped (`slicingTransform.ml:229`, `transform.ml:76`); condition edges read as not taken (`slicingTransform.ml:461`, `transform.ml:151`, `iterator.ml:33-35`); the rest follows the bottom PDG | not traced | No: needs reached statements, condition truth values and the PDG |
| Impact, Security slicing | no initial node at an unreachable statement (`compute_impact.ml:529`, `components.ml:615`) | not traced | No: needs the PDG |
| Scope defs and zones, Studia, Occurrence, Dive | addresses evaluate to bottom zones (`results.ml:680-684`), so no read or write is found in the body | addresses evaluated in the top state (`results.ml:121-125`); result not traced. Dive sees no callstack (`results.ml:142-144`) | No: needs states |
| Constant propagation | value is bottom (`results.ml:616-620`); the effect on the rewriting was not traced | top value, no replacement expected | No: needs states |
| WP `MemVal` | bottom cvalue state; effect not traced | top state | No: needs states |
| RTE | not affected by states; with `-rte-use-eva-results` it skips generation whenever the status is `Analyzed _` (`plugins/rte/src/options.ml:131-135`, `visit.ml:375`) **[code]** | same | Yes, if the earlier alarms are present as annotations |
| Nonterm | every syntactically reachable statement is reported unreachable, plus the return (`nonterm_run.ml:168-189`) | function skipped (`nonterm_run.ml:200`) | Yes: reached statements with before/after and per callstack |
| Metrics, markdown-report | zero statement coverage for the body | full coverage for the body | Yes: reached statements |
| Loop analysis, Reduc | statement skipped (`loop_analysis.ml:336-340`, `value2acsl.ml:151,157`) | no bound | No: needs states |
| Callgraph, callers and call sites, `callee` of a call inside the body | callees reached only from the body appear not called; `callee` returns `[]` (`results.ml:591-601`) | `callee` evaluates the function expression in the top state (`results.ml:121-125,347-354`); the result for direct and indirect calls was not traced | No: needs the saved callers table and call targets |
| `getDeadCode` | whole body listed unreachable (`ast_requests.ml:131-140`) | empty lists (`ast_requests.ml:130`) | Yes: reached statements with before/after |
| `getValues`, `getStates`, taint, probes | "unreachable" (`value_requests.ml:509-512`) | values evaluated in the top state; no callstack listed | No: needs states |
| Export (`-eva-annot`) | `\false` at every statement (`export.ml:224`) | function refused, "no available results" (`export.ml:313-319`) | No: needs states |

## Not checked

- Nothing was built or run. Every conclusion about behaviour on a bottom or top body is a reading of the code.
- Mthread post-analysis (`Mt_main.post_analysis`, shared-variable and mutex summaries) and `mthread_requests.ml`: only the two call hooks and the interference read were read.
- The `post_analysis` of domains other than cvalue (taint, traces, inout, printer, numerors, multidim).
- `Statistics.export_as_csv`: only that Summary feeds it (`summary.ml:283-286`).
- Whether each projectified state named in Gap 4 is actually written by `-save` (the datatype of each was not inspected), and the load-time order of restoration.
- How property-status consolidation treats statuses emitted by an older version of a usable emitter after a tuning parameter change.
- Whether `Emitter_with_properties` equality distinguishes hypotheses, which decides whether a new status merges with or sits beside an older one from the same emitter.
- What `Logic_deps` and `Eval_terms` return when the state is bottom (Scope zone computation, PDG annotations).
- What Constant propagation, WP `MemVal`, Slicing, Sparecode and Impact do with top states.
- The Ivette TypeScript side; only the OCaml requests were read.
- Test directories and `plugins/*/tests` were excluded from the searches, except where cited.
- Unqualified uses after an `open` of an Eva module: `plugins/dive/src/build.ml:82-111` and `plugins/slicing/src/slicingCmds.ml:44-46` open `Eva.Results` and were read; `plugins/dive/src/dive_graph.ml:107` opens it only for the taint constructors (lines 107-111 read). `plugins/pdg/src/build.ml:549` and `plugins/from/src/from_compute.ml:170` open `Eva.Assigns.DepsOrUnassigned` and `Eva.Deps`, not the results. The rest of each of these files was read only at the lines found by search, and `plugins/from/src/from_memory.ml` was not read.
