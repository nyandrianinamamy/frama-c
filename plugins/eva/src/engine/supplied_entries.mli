(**************************************************************************)
(*                                                                        *)
(*  SPDX-License-Identifier LGPL-2.1                                      *)
(*  Copyright (C)                                                         *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*                                                                        *)
(**************************************************************************)

(** Cache entries supplied by a test module to the reuse operation.

    This module is for tests only: entries are supplied by test modules, and
    no part of the analyzer supplies any. The entries hold states of the
    cvalue domain (see {!Cache_entry}).

    The cache of calls of an analysis is chosen when the analysis starts.
    When entries were supplied in the current project, it is the reuse
    operation on the supplied entries, and memexec is not consulted: no call
    of this analysis is answered by memexec, and no result is stored.
    Otherwise memexec is the cache of calls, as before, and entries supplied
    during the analysis are not used by it. Option [-eva-no-memexec]
    disables both. See {!Call_cache} for the dispositions printed at each
    call. *)

open Cil_types

(** A cache entry with states of the cvalue domain. *)
type entry = Cache_entry.Cvalue.t

(** The footprint of an entry: R, W, W_exit and W_sure (see
    {!Cache_entry.footprint}). *)
type footprint = Cache_entry.footprint = {
  read : Base.Hptset.t;
  written : Base.Hptset.t;
  written_exit : Base.Hptset.t;
  written_sure : Base.Hptset.t;
}

(** [supply ~safety ~reach kf ~key ~input ~footprint ~exit] supplies an
    entry for the body of [kf], built by {!Cache_entry.Make.make} from
    these arguments, and returns it. [exit] lists the exit states of the body
    with their partition keys: a body that never returns has no exit state,
    and its entry has the empty list. Entries are identified by 1, 2, ... in
    the order in which they are supplied, and the oldest matching entry is
    used at a call. Each exit state records as possible holders of the
    address of a local variable the blocks it binds to a value that may
    contain such an address.

    The entry is used as given: nothing checks that it describes the body of
    [kf], and a false entry gives a false result at a hit. The caller of
    [supply] owes, for every concrete execution of the body that starts in a
    state covered by [input]:
    - R covers every block that the body may read, through a pointer
      included; a block designated by a pointer of the key is not in the key
      unless it is listed in it;
    - W covers every block that the body may write; W_exit covers every
      block that the body may write on a path that reaches an exit, even
      when the write leaves the value of the input;
      W_sure holds only blocks certainly and fully overwritten on every path
      that reaches an exit;
    - the key contains R ∪ (W_exit \ W_sure), and the body neither frees nor
      allocates a block, nor ends the lifetime of a block other than its own
      locals;
    - each execution that returns ends in a memory covered by one of the
      exit states; this includes the effect of leaving the scope of the
      locals of the body on the blocks that may hold their addresses, which
      the end of the call does not sweep again for the locals of inner
      blocks;
    - [safety], empty by default, holds the alarms, statuses and red
      contexts that an analysis of the body from [input] emits (see
      {!Safety_part}): every undefined behaviour of an execution occurs
      where one of its alarms is, and a property given a status holds as
      this status says. A hit delivers them for its own callstack. An
      alarm holds the predicate of its assertion, as the kernel builds it
      ([Alarms.predicate]): a hit registers the alarm with it and builds
      none. The checks of the [requires] clauses of [kf] are not part of
      the body, and a hit evaluates no predicate: the lookup rejects the
      entries of a function whose call checks such a clause
      ([`Preconditions]);
    - [reach] holds the Reach part of an analysis of the body from
      [input] (see {!Reach_part.part}), and a hit requires it: its joins
      hold every guard outcome that an execution takes and, at each
      statement, zones that cover those that an analysis registers there;
      its points, if given, hold every statement that an execution
      reaches, before it and, if the execution goes past it, after it. A
      hit delivers them for its own callstack. The lookup rejects with
      [`Missing_points] an entry without [reach], at every call, and an
      entry whose part has no points, at a call whose function saves its
      states. The joins of a part that a hit delivers hold no call site: no
      hit is admitted on a body with a call (see below), and the call site
      of the call answered by the hit is registered by its caller before
      the lookup, as for an analysis of the body.

    The alarms, statuses and messages of [safety] are those of an analysis
    of the body with the settings in force at each hit on the entry. The
    caller owes that these settings are equal in the analysis that produced
    the entry and in the analysis that uses it, at the call that produced
    the entry and at each hit. The caller also owes that the formatter, the
    history test and the output sinks of the logger, and the printers of
    the AST ([Printer.update_printer], the printing references of [Cil] and
    [Cil_datatype], the printers of [Acsl_extension]) are those of the
    kernel and of the plug-ins of the tree, or replacements that do not act
    on the analysis: they are not registrations, and the lookup does not
    see them. A hit and an analysis of the body print other lines with
    them. The settings are:
    - the options of the kernel and of Eva that decide which alarms and
      statuses are emitted, such as the [-warn-*] options of the kernel
      ([-warn-signed-overflow] for instance) and the [-eva-warn-*] options
      of Eva ([-eva-warn-copy-indeterminate] for instance);
    - the status of every warning category of Eva and of the kernel
      ([-eva-warn-key] and [-kernel-warn-key]), which decides the action of
      its messages, apart from the category [alarm] of Eva, whose messages
      a hit prints;
    - the activation of every message category of Eva and of the kernel
      ([-eva-msg-key] and [-kernel-msg-key]), which decides whether a
      message is printed.

    A violation can hide an alarm or a message, and change the state at the
    end of the call: a hit prints the messages of the statuses and alarms of
    its entry through the logger, but no other message of the body, such as
    the assumption of 2's complement for an overflow, and when the category
    of such a message is set to abort, an analysis of the body stops where
    the hit goes on. Two checks of the lookup cover a part of these
    settings. For an entry produced by an analysis, the lookup compares the
    status of the warning categories of the kernel and of Eva, but [alarm],
    with their status when the analysis of the body started
    ({!Body_access.warn_categories}), and rejects the entry with
    [`Warn_categories] when one differs. Within the analysis that uses the
    entry, a setting changes only through a client of a hook, and the
    lookup rejects every entry with [`Callback] while a client that is not
    audited is registered on a hook that a hit runs. Nothing checks the
    options and the activation of the message categories, and an entry
    given to [supply] carries no status of the warning categories.

    The body of [kf] does not call a function that has a body, directly or
    through a pointer: [supply] raises otherwise, before any lookup. An entry
    whose body contains another call is rejected at lookup
    ([nested-delivery]), except for direct calls of the display directives
    [Frama_C_show_each*] and [Frama_C_domain_show_each*]. A hit on a body
    with such a directive skips its printed line and the call and
    call-result hooks that a fresh evaluation of the directive runs: the
    fixture must tolerate both omissions. A hit thus skips the analysis of
    [kf] alone, which it records among the functions whose statements have
    no state (see {!Safety_delivery.skip_visits}), and whose reached points
    it delivers (see {!Reach_delivery}).

    Raises [Invalid_argument] if the body of [kf] may call a function that
    has a body, directly or through a pointer; if [input] or an exit state
    is [Top] or [Bottom]; if the written sets are not nested
    (W_sure ⊆ W_exit ⊆ W); if [key] does not contain R ∪ (W_exit \ W_sure);
    if [key] is not closed in [input]; if an exit state does not bind a
    block of W_exit that exists at the exit of the body: every block of
    W_exit but the locals of its inner blocks; or if [kf] is not a function
    of the current project. The three written sets include the block of the
    value returned by [kf], if any (see {!return_variable}). *)
val supply :
  ?safety:Safety_part.t -> ?reach:Reach_part.part -> kernel_function ->
  key:Base.Hptset.t -> input:Cvalue.Model.t -> footprint:footprint ->
  exit:(Partition.key * Cvalue.Model.t) list -> entry

(** Supply the key, the states, the Safety part, the Reach part and the
    parts of other modules (see {!Cache_part}) of an entry captured by the
    producer, with the next supplied entry identifier. The lookup checks the
    recorded sweep targets, used functions, widening generation and status
    of the warning categories. The fixture must use the same AST and ensure
    the calls meet the replay premises described on [supply], the settings
    that decide the alarms, statuses and messages included: the options and
    the activation of the message categories are not checked. The parts are
    restored at a hit as given; an entry supplied by {!supply} has no part
    of another module. The producer stores bodies that call other functions,
    and the lookup rejects their entries, whose key matches, with
    [`Missing_part] when a part whose consumer is enabled is missing, which
    is the case of the parts of From and Inout for a call that made a call;
    otherwise with [`Missing_points] when the call needs the points of the
    Reach part and the entry has none; otherwise with [`Nested_delivery],
    the parts of a call whose calls were on paths that it did not take
    included; otherwise with [`Preconditions], which the producer never
    meets on its own entries, since it refuses the body of a function whose
    call checks a [requires] clause. Direct calls to the display directives
    [Frama_C_show_each*] and [Frama_C_domain_show_each*] are not calls
    there. The check of [supply] on the calls of the body does not apply
    here.

    The fixture also owes that the options of Eva that decide which states
    are saved at the statements ([-eva-results],
    [-eva-no-results-function]) and how precisely bodies are analysed (the
    options of precision, of the domains and of the alarms) are equal in the
    analysis that produced the entry and in the analysis that uses it.
    Nothing checks it: a difference can change the parts restored at a hit,
    the states at the end of the call, and, through the reduction of the
    actuals with the Inout part, the state of the caller. Within one
    analysis, these options change only by clearing its results, after
    which every candidate is rejected ([`Analysis_reset]); an entry
    supplied to a later analysis is not checked. Issue #59, which saves the
    options of the producing analysis with its entries, must enforce this
    equality.

    For the parts, the fixture owes two more premises, which nothing
    checks. The analysis that produced the entry and the analysis that
    uses it start from the same initial state: the inputs that Inout
    computes for the label [Init] of an annotation are those of the initial
    state of the producing analysis. And the entry was not produced in the
    rest of an analysis after an analysis started by a callback during it
    ended: the results of the analysis are then available, and a part
    computed from them is not covered for another call. In the rest of
    that analysis, every candidate is rejected ([`Analysis_reset]).

    Raises [Invalid_argument] if the function of the entry is not a function
    of the current project: an entry made in a project is not supplied to a
    copy of it made by [Project.create_by_copy], whose functions are other
    values.
    Supplying entries remains a test-only operation. *)
val supply_produced : Cache_producer.entry -> entry

(** The partition key of a state that no partitioning distinguishes. *)
val empty_key : Partition.key

(** [case_key kf n] is the partition key that the analysis gives to the
    [n]-th state of a disjunction at the return statement of [kf]. Two
    different [n] give two different keys. *)
val case_key : kernel_function -> int -> Partition.key

(** The variable that holds the value returned by [kf] in the exit states,
    if [kf] returns a value. *)
val return_variable : kernel_function -> varinfo option

(** The entries supplied for the body of a function, oldest first. *)
val entries : kernel_function -> entry list

(** Removes all supplied entries of the current project. *)
val clear : unit -> unit

(** {2 Content of an entry} *)

val id : entry -> int
val statement : entry -> Cache_entry.statement
val key : entry -> Base.Hptset.t
val input : entry -> Cvalue.Model.t
val footprint : entry -> footprint
val exit : entry -> (Partition.key * Cvalue.Model.t) list
val safety : entry -> Safety_part.t
val reach : entry -> Reach_part.part option
val parts : entry -> Cache_part.parts
val pretty : Format.formatter -> entry -> unit

(** {2 Lookup} *)

(** Whether the cache of calls of the current analysis is the reuse
    operation on the supplied entries: whether entries were supplied in the
    current project when the analysis started. The choice holds for the
    whole analysis. Within an analysis that uses the supplied entries, each
    lookup reads the entries supplied at that time, so an entry supplied
    during the analysis, by a callback for instance, is a candidate for the
    later calls of that analysis. *)
val active : unit -> bool

(** Why a supplied entry is not used for a call. When the active domains
    are not the cvalue domain alone, every candidate is rejected with
    [`Product], whatever the other reasons; otherwise, when a consumer that
    no entry can serve is enabled, with [`Consumer]; otherwise, when
    [-eva-stop-at-nth-alarm] is set, with [`Stop_at_nth_alarm]; otherwise,
    when a client that is not audited is registered on a hook that a hit
    runs, with [`Callback]; otherwise, when, while an analysis runs, its
    results were cleared or another analysis ended, with [`Analysis_reset].
    Otherwise each candidate is examined by {!Cache_entry.Make.find}, oldest
    first, and the first test that fails gives its reason: [`Key_differs],
    [`Key_unclosed], then [`Missing_part] for a candidate that lacks a part
    whose consumer is enabled; then, in {!Lookup.find}, [`Recursion],
    [`Automatic_cleanup], [`Watchpoint], the dependencies of a produced
    entry ([`Hint_generation], [`Warn_categories], [`Sweep]), then
    [`Missing_points] for a candidate without a Reach part, or whose Reach
    part has no points when the call needs them, then [`Nested_delivery],
    and last [`Preconditions] for the entries of a function whose call
    checks a [requires] clause. A candidate that lacks both a needed part
    and its Reach part is rejected with [`Missing_part]. *)
type rejection = [
  | Cache_entry.rejection
  | `Product
  (** The active domains are not the cvalue domain alone. *)
  | `Consumer
  (** A consumer that no entry can serve is enabled: the analysis of
      threads, which resolves the identifier of a hit against the entries of
      memexec; a reader of the states saved at statements (see
      {!Cache_part.reads_statement_states}): the analyses by function of
      From ([-deps]) and Inout ([-out], [-input], [-deref] and their
      variants), or a loaded plug-in that requests them; or a plug-in that
      concludes from the states saved at the statements of a function,
      which do not cover the calls answered by a hit: Nonterm, Metrics, the
      Markdown report, WP and the constant propagation. *)
  | `Stop_at_nth_alarm
  (** Option [-eva-stop-at-nth-alarm] is set. A fresh evaluation emits all
      its alarms before it tests the threshold; a hit does not deliver its
      alarms by evaluation. *)
  | `Callback
  (** A client that is not audited is registered on a hook that a hit runs
      between its lookup and the end of its delivery, or that an analysis of
      the body runs and a hit does not: such a client can tell a hit from an
      analysis of the body. The hooks are the call, call results and
      statement hooks of Eva ({!Cvalue_callbacks.unaudited_hooks}), the
      hooks of red statuses ({!Red_statuses.has_hooks}), the hooks of the
      kernel on a new property or status
      ({!Property_status.has_add_or_update_hooks}) and on a change of the
      annotations ({!Annotations.has_unaudited_hooks_on_change}), the
      actions registered before and after the clearing of a project
      ([Project.has_unaudited_clear_hooks]), which the emission of a status
      runs when it clears the states that depend on the statuses, these
      states apart from those of the kernel and of Report, whose clearing
      functions run then, and the hooks on the update of any of them
      ([State.has_hooks_on_update]), the function that gives the type of an
      inserted cast ([Cil.has_inserted_cast_hook]) and the hooks on the
      table of logic functions ([Logic_env.has_hooks_on_logic_functions]),
      which an analysis of the body runs when it builds the predicate of an
      alarm and a hit does not, the
      listeners and observers of the history of the logger
      ({!Log.unaudited_clients}), the hooks of the message collector of the
      kernel ({!Messages.has_hooks}), the restoration of the parts whose
      consumer is enabled, with the clients that it runs
      ({!Cache_part.unaudited_clients}), and the subscribers of the
      statistics by function of the summary, which the end of the delivery
      updates ({!Safety_delivery.unaudited_subscribers}). The other
      interfaces are the observers of the clients of the kernel hooks
      ({!Hook.Opaque.has_unaudited_observers}), of the metadata and validity
      of the allocated bases ({!Base.has_unaudited_observers}) and of the
      history of the origins ({!Origin.has_unaudited_observers}), the
      daemons of [Async] ({!Async.has_daemons}), the hooks on a change of
      the current location ({!Current_loc.has_hooks_on_change}) and of the
      statistics by callstack of Eva ({!Eva_perf.has_hooks_on_change}), and
      the observers of the Safety part, of the Reach part and of the results
      of the collector ({!Safety_part.has_unaudited_observers},
      {!Reach_part.has_unaudited_observers},
      {!Body_access.Result.has_unaudited_observers}). A hit can run the
      observers of the clients of the kernel hooks and of the metadata of
      the allocated bases; an analysis of the body runs these interfaces at
      other places or with other values. The collector registers its own
      observers as audited. A client registered since the production of the
      entry counts. The predicates of the parts are evaluated once by each
      lookup, before this test ({!Cache_part.decide}), and the check of the
      parts and the restoration use their answers: a hook that a predicate
      registers is seen by the test, and no predicate runs between the test
      and the end of the delivery. *)
  | `Analysis_reset
  (** While an analysis runs, its computation state is no longer
      [Computing]: its results were cleared, which a change of an option of
      Eva does, or another analysis, started by a callback after this one
      set its state to [Computing], ended. The options of the rest of the
      analysis may differ from those under which the entries were produced.
      A lookup made outside any analysis, by a test, is not concerned. *)
]

(** All reasons, in the order of their documentation. *)
val rejections : rejection list

(** Stable identifier of a reason: those of {!Cache_entry.rejection_id},
    [product] for [`Product], [consumer] for [`Consumer],
    [stop-at-nth-alarm] for [`Stop_at_nth_alarm], [callback] for
    [`Callback] and [analysis-reset] for [`Analysis_reset]. *)
val rejection_id : rejection -> string

(** Result of a lookup. *)
type 'state lookup = {
  rejected : (int * rejection) list;
  (** The identifiers of the candidates rejected, oldest first, with their
      reasons. *)
  hit : (entry * (Partition.key * 'state) list) option;
  (** The winning entry, if any, and the states reconstructed from it. The
      engine delivers the Safety part ({!safety}) and the Reach part
      ({!reach}) of the entry at the call. *)
  restoration : Cache_part.restoration;
  (** The parts of the winning entry that the hit restores, selected with
      the answers of the predicates of the parts taken once by the lookup,
      before its test of the clients ({!Cache_part.decide}); none without a
      hit. The engine restores them after the delivery of the Safety part
      and of the Reach part. *)
}

module Lookup (Domain : sig
    type t
    val structure : t Abstract.Domain.structure
  end) : sig

  (** [find stack state] applies the reuse operation ({!Cache_entry.Make.find})
      to the entries supplied for the top function of [stack], at a call
      whose input is [state].
      When the active domains are not the cvalue domain alone, when a
      component listed under [`Consumer] is enabled, when
      [-eva-stop-at-nth-alarm] is set, when a client listed under
      [`Callback] is registered, or when, while an analysis runs, its
      results were cleared or another analysis ended, every entry is
      rejected for this reason. A matching entry without a Reach part, or
      whose Reach part has no points when [save_results] holds for the top
      function of [stack] ({!Function_calls.save_results}), is rejected with
      [`Missing_points] if it passes the other admission checks; the lookup
      then examines the next candidate. This check comes before the
      following ones: with either constructor, a matching body with a call
      other than a direct show directive is rejected with
      [`Nested_delivery] if it passes the other admission checks, and
      otherwise a matching entry of a function whose call checks a
      [requires] clause ({!Cache_producer.has_preconditions}) is rejected
      with [`Preconditions]. *)
  val find : Callstack.t -> Domain.t -> Domain.t lookup
end
