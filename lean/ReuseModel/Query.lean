import ReuseModel.Entry
import ReuseModel.Frame

/-!
# State queries on the callstack of a hit

A query names a statement, a callstack and a position, before or after the
statement, and asks for the content of a block there. Inside a body answered
by a hit, the visits of the member are not analysed. The answer is
reconstructed from what the hit log and the entry hold:

* the hit log has one line per hit: its callstack, the entry used, the inner
  part of that entry, and the abstract state at the call with the blocks it
  binds;
* the inner part of an entry holds, for each point below the start of the
  cached statement, the shared inner state, a recorded over-approximation of
  the blocks written before the point, and a list of blocks updated before
  it.

Each line whose callstack ends the callstack of the query answers at the
point below its hit, and the query joins these answers. A line answers by
the first rule that applies: with reconstruction disabled, no state; a block
of the matching key, the shared inner state; a block bound at the call that
the body does not write (a frame block), its value at the call with the
marks of the lexical sweeps; a block bound at the call and absent from the
recorded possible writes at the point, the same; a block listed as updated
at the point, the shared inner state; any other block, top.

`CacheEntry.answer_sound` shows that the answer of one line contains the
content of the block at each visit of a member of that line at that point,
and that the entry reports the statement as reached. `CacheEntry.query_sound`
shows the same for the joined answer, at each visit represented by any line
that applies. The matching witness of the member is a premise. A hit
supplies it: `CacheEntry.matches_of_projected` from a projected match with
`CacheEntry.ReplayCompatible`, `CacheEntry.whole_product_witness` from
equality of the whole product.
-/

namespace ReuseModel

open Memory

/-- The sites of the calls in progress in a continuation, innermost first. -/
def Cont.callstack : Cont → List Label
  | .stop => []
  | .seq _ k | .loop _ _ _ k | .scope _ _ k => k.callstack
  | .call site _ _ _ k => site :: k.callstack

/-- The number of frames of a continuation. -/
def Cont.depth : Cont → Nat
  | .stop => 0
  | .seq _ k | .loop _ _ _ k | .scope _ _ k | .call _ _ _ _ k => k.depth + 1

/-- The position of a query relative to its statement. -/
inductive Pos where
  | before
  | after
  deriving DecidableEq, Repr

/-- The point of a query: the label of a statement, a callstack (call
sites, innermost first) and a position. -/
structure QueryPoint where
  stmt : Label
  callstack : List Label
  pos : Pos
  deriving DecidableEq, Repr

/-- The same point seen from a hit whose callstack `hit` ends the callstack
of the point: the call sites below the hit. -/
def QueryPoint.below (q : QueryPoint) (hit : List Label) : QueryPoint :=
  { q with callstack := q.callstack.take (q.callstack.length - hit.length) }

section
variable {M : Type} [Memory M]

/-- The events and the configuration after `n` steps of the statement of `t`
from `σ`. Every finite prefix is one of them (`steps_iff_run`). -/
def trace (t : Subject) (σ : State M) (n : Nat) : List Event × Config M :=
  run t.prog n (Config.entry t.stmt σ)

/-- The configuration is part of the execution of a statement started with
the continuation `k`: a statement runs on `k` or above it, or a completed
statement or a `return` continues above `k`. -/
def Config.Inside (k : Cont) : Config M → Prop
  | .run _ k' _ _ => k.depth ≤ k'.depth
  | .next k' _ _ => k.depth < k'.depth
  | .ret _ k' _ => k.depth < k'.depth
  | .done .. => False
  | .fault .. => False

instance (k : Cont) (c : Config M) : Decidable (c.Inside k) := by
  cases c <;> unfold Config.Inside <;> infer_instance

/-- After `n` steps, the execution of the statement of `t` from `σ` is at the
point `q`, whose callstack counts the calls made inside that statement.
Before: the statement labelled `q.stmt` is about to execute. After: that
statement, about to execute at an earlier step `n₀` with continuation `k`,
has completed normally at step `n` (`next k`), and every configuration in
between is part of its execution. A statement left by `return` or by a
fault has no visit after it. -/
def AtPoint (t : Subject) (σ : State M) (q : QueryPoint) (n : Nat) : Prop :=
  match q.pos with
  | .before => ∃ st k env m, (trace t σ n).2 = .run st k env m ∧
      st.label = q.stmt ∧ k.callstack = q.callstack
  | .after => ∃ n₀ st k env₀ m₀ env m, n₀ < n ∧
      (trace t σ n₀).2 = .run st k env₀ m₀ ∧ st.label = q.stmt ∧
      k.callstack = q.callstack ∧ (trace t σ n).2 = .next k env m ∧
      ∀ i < n, n₀ < i → (trace t σ i).2.Inside k

end

/-- A set of possible contents of a block. `none` is the content of a block
with no binding. -/
abbrev ValueSet := Option Value → Prop

/-- The answer that contains every content. -/
def ValueSet.top : ValueSet := fun _ => True

/-- The contents of `vs`, each with the marks that any sequence of lexical
sweeps may have put on it. -/
def ValueSet.swept (vs : ValueSet) : ValueSet :=
  fun u => ∃ v targets, vs v ∧ u = applySweeps targets v

/-- The contents of the block `b` in the memories that `S` covers. -/
def Domain.valueOf {M : Type} [Memory M] (d : Domain M) (S : d.State)
    (b : Block) : ValueSet :=
  fun v => ∃ m, d.γ S m ∧ load m b = v

/-- The part of a cache entry that state queries use. Points are taken below
the start of the cached statement. `state` is the shared inner state at each
point; `mayWrite` is a recorded over-approximation of the blocks written
before the point; `updated` is a list of blocks. `InnerPartSound` states
what these must satisfy: in particular, each block listed in `updated` is
updated (written, created, released or swept) on every execution before the
point. A block updated on every execution but not listed is not answered
from the inner state. -/
structure InnerPart {M : Type} (d : Domain M) where
  state : QueryPoint → d.State
  mayWrite : QueryPoint → BlockSet
  updated : QueryPoint → BlockSet

/-- A line of the hit log: the callstack of a call answered by a hit, the
entry used and its inner part, the abstract state at the call, and the blocks
that this state binds. -/
structure HitLine {M : Type} (d : Domain M) where
  callstack : List Label
  entry : CacheEntry d
  inner : InnerPart d
  state : d.State
  blocks : BlockSet

namespace HitLine

variable {M : Type} [Memory M] {d : Domain M}

/-- The answer for the block `b` at the point `q` below the hit of `line`.
`none` reports that no state is recorded. -/
def answer (line : HitLine d) (enabled : Bool) (q : QueryPoint) (b : Block) :
    Option ValueSet :=
  if enabled then
    -- A block of the matching key.
    if b ∈ line.entry.key then
      some (d.valueOf (line.inner.state q) b)
    -- A frame block: bound at the call and not written by the body.
    else if b ∉ line.entry.footprint.writes ∧ b ∈ line.blocks then
      some (d.valueOf line.state b).swept
    -- A block bound at the call and absent from the recorded possible
    -- writes at the point.
    else if b ∉ line.inner.mayWrite q ∧ b ∈ line.blocks then
      some (d.valueOf line.state b).swept
    -- A block listed as updated at the point.
    else if b ∈ line.inner.updated q then
      some (d.valueOf (line.inner.state q) b)
    else some ValueSet.top
  else none

end HitLine

/-- The join of two answers: the union of two sets. Two answers of no state
join to no state; an answer of no state and a set join to top. -/
def joinAnswer : Option ValueSet → Option ValueSet → Option ValueSet
  | none, none => none
  | some x, some y => some fun v => x v ∨ y v
  | _, _ => some ValueSet.top

/-- The join of a list of answers. The empty list joins to no state. -/
def joinAnswers : List (Option ValueSet) → Option ValueSet
  | [] => none
  | [a] => a
  | a :: b :: rest => joinAnswer a (joinAnswers (b :: rest))

/-- A state query at the point `q`, whose callstack is the full callstack,
for the block `b`. Each line of the log whose callstack ends the callstack of
the point applies, and answers at the point below its hit; the query joins
the answers of these lines. With no such line, the query is not on the
callstack of a hit, and no state is reported here. -/
def query {M : Type} [Memory M] {d : Domain M} (enabled : Bool)
    (log : List (HitLine d)) (q : QueryPoint) (b : Block) : Option ValueSet :=
  joinAnswers ((log.filter fun line => line.callstack.isSuffixOf q.callstack).map
    fun line => line.answer enabled (q.below line.callstack) b)

/-- A list of answers that joins to no state holds no set. -/
theorem joinAnswers_eq_none :
    ∀ {answers : List (Option ValueSet)}, joinAnswers answers = none →
      ∀ a ∈ answers, a = none
  | [], _, _, ha => absurd ha List.not_mem_nil
  | [a], h, a', ha => by
    rw [List.mem_singleton] at ha
    subst ha
    exact h
  | a :: b :: rest, h, a', ha => by
    have ih := joinAnswers_eq_none (answers := b :: rest)
    simp only [joinAnswers] at h
    cases a <;> cases hj : joinAnswers (b :: rest) <;> simp only [hj, joinAnswer] at h
    · rcases List.mem_cons.mp ha with rfl | ha
      · rfl
      · exact ih hj _ ha
    all_goals cases h

/-- The members of a joined answer: a content is in the join exactly when
it is in one of the answers, an answer of no state counting as top. -/
theorem mem_joinAnswers :
    ∀ {answers : List (Option ValueSet)} {vs : ValueSet}, joinAnswers answers = some vs →
      ∀ v, vs v ↔ ∃ a ∈ answers, (a.getD ValueSet.top) v
  | [], _, h, _ => by cases h
  | [a], vs, h, v => by
    change a = some vs at h
    subst h
    simp
  | a :: b :: rest, vs, h, v => by
    have hnone := joinAnswers_eq_none (answers := b :: rest)
    change joinAnswer a (joinAnswers (b :: rest)) = some vs at h
    cases a with
    | none =>
      cases hj : joinAnswers (b :: rest) with
      | none => rw [hj] at h; cases h
      | some y =>
        rw [hj] at h
        change some ValueSet.top = some vs at h
        cases h
        exact ⟨fun _ => ⟨none, List.mem_cons_self, trivial⟩, fun _ => trivial⟩
    | some x =>
      cases hj : joinAnswers (b :: rest) with
      | none =>
        rw [hj] at h
        change some ValueSet.top = some vs at h
        cases h
        exact ⟨fun _ => ⟨b, List.mem_cons_of_mem _ List.mem_cons_self,
          by rw [hnone hj b List.mem_cons_self]; trivial⟩, fun _ => trivial⟩
      | some y =>
        rw [hj] at h
        change some (fun v => x v ∨ y v) = some vs at h
        cases h
        show x v ∨ y v ↔ _
        rw [mem_joinAnswers hj v]
        constructor
        · rintro (h | ⟨a, ha, h⟩)
          · exact ⟨some x, List.mem_cons_self, h⟩
          · exact ⟨a, List.mem_cons_of_mem _ ha, h⟩
        · rintro ⟨a, ha, h⟩
          rcases List.mem_cons.mp ha with rfl | ha
          · exact Or.inl h
          · exact Or.inr ⟨a, ha, h⟩

/-- A list of answers that holds a set joins to a set. -/
theorem joinAnswers_isSome :
    ∀ {answers : List (Option ValueSet)} {x : ValueSet}, some x ∈ answers →
      ∃ vs, joinAnswers answers = some vs
  | [], _, h => absurd h List.not_mem_nil
  | [a], x, h => by
    rw [List.mem_singleton] at h
    exact ⟨x, h.symm⟩
  | a :: b :: rest, x, h => by
    simp only [joinAnswers]
    cases a with
    | none =>
      rcases List.mem_cons.mp h with h | h
      · cases h
      · obtain ⟨y, hy⟩ := joinAnswers_isSome h
        exact ⟨_, by rw [hy]; rfl⟩
    | some x' =>
      cases joinAnswers (b :: rest) <;> exact ⟨_, rfl⟩

section
variable {M : Type} [Memory M] {d : Domain M}

/-- The members of the answer of a query: a content is in the answer exactly
when it is in the answer of a line that applies, an answer of no state
counting as top. -/
theorem mem_query {enabled : Bool} {log : List (HitLine d)} {q : QueryPoint} {b : Block}
    {vs : ValueSet} (h : query enabled log q b = some vs) (v : Option Value) :
    vs v ↔ ∃ line ∈ log, line.callstack.isSuffixOf q.callstack ∧
      ((line.answer enabled (q.below line.callstack) b).getD ValueSet.top) v := by
  rw [mem_joinAnswers h v]
  simp only [List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨_, ⟨line, ⟨hl, hs⟩, rfl⟩, hv⟩
    exact ⟨line, hl, hs, hv⟩
  · rintro ⟨line, hl, hs, hv⟩
    exact ⟨_, ⟨line, ⟨hl, hs⟩, rfl⟩, hv⟩

/-- A query on a point where a line of the log applies and answers with a
set returns a set, which contains that answer. With reconstruction
enabled, every line answers with a set (`HitLine.answer_isSome`). -/
theorem query_some {enabled : Bool} {log : List (HitLine d)} {q : QueryPoint} {b : Block}
    {line : HitLine d} (hl : line ∈ log) (hs : line.callstack.isSuffixOf q.callstack)
    {x : ValueSet} (ha : line.answer enabled (q.below line.callstack) b = some x) :
    ∃ vs, query enabled log q b = some vs ∧ ∀ v, x v → vs v := by
  have hmem : some x ∈ (log.filter fun line => line.callstack.isSuffixOf q.callstack).map
      fun line => line.answer enabled (q.below line.callstack) b :=
    List.mem_map.mpr ⟨line, List.mem_filter.mpr ⟨hl, hs⟩, ha⟩
  obtain ⟨vs, hvs⟩ := joinAnswers_isSome hmem
  refine ⟨vs, hvs, fun v hv => (mem_query hvs v).2 ⟨line, hl, hs, ?_⟩⟩
  rw [ha]
  exact hv

/-- With reconstruction enabled, a line answers with a set. -/
theorem HitLine.answer_isSome (line : HitLine d) (q : QueryPoint) (b : Block) :
    ∃ x, line.answer true q b = some x := by
  simp only [HitLine.answer, ↓reduceIte]
  repeat' split
  all_goals exact ⟨_, rfl⟩

end

namespace CacheEntry

variable {M : Type} [Memory M] {d : Domain M}

/-- The inner part is sound for the producing input. At each visit of a
producing execution at a point: the state at the point covers the visit on
the key and on the blocks listed as updated; each block written so far is
in `mayWrite`; and each block listed as updated has been updated so far. -/
structure InnerPartSound (entry : CacheEntry d) (inner : InnerPart d) : Prop where
  state : ∀ w, d.γ entry.input w → ∀ q n,
    AtPoint entry.subject ⟨entry.env, w⟩ q n →
    ∃ r, d.γ (inner.state q) r ∧
      AgreeOn (inner.updated q ++ entry.key) r (trace entry.subject ⟨entry.env, w⟩ n).2.mem
  mayWrite : ∀ w, d.γ entry.input w → ∀ q n,
    AtPoint entry.subject ⟨entry.env, w⟩ q n →
    ∀ b, Event.write b ∈ (trace entry.subject ⟨entry.env, w⟩ n).1 → b ∈ inner.mayWrite q
  updated : ∀ w, d.γ entry.input w → ∀ q n,
    AtPoint entry.subject ⟨entry.env, w⟩ q n →
    ∀ b ∈ inner.updated q, b ∈ updatedBlocks (trace entry.subject ⟨entry.env, w⟩ n).1

/-- The inner part whose possible writes are the writes of the footprint at
every point, with no updated block, is sound under two premises: its states
cover the producing visits on the key (`hs`), and the footprint covers the
writes of the producing executions (`hc`, for the possible writes). With it,
every block outside the key and the frame answers top. -/
theorem innerPartSound_of_key {entry : CacheEntry d} (state : QueryPoint → d.State)
    (hc : entry.Coverage)
    (hs : ∀ w, d.γ entry.input w → ∀ q n, AtPoint entry.subject ⟨entry.env, w⟩ q n →
      ∃ r, d.γ (state q) r ∧ AgreeOn entry.key r (trace entry.subject ⟨entry.env, w⟩ n).2.mem) :
    entry.InnerPartSound ⟨state, fun _ => entry.footprint.writes, fun _ => []⟩ := by
  refine ⟨fun w hw q n hv => hs w hw q n hv, fun w hw q n _ b hb => ?_, fun _ _ _ _ _ b hb => ?_⟩
  · exact (hc w hw).accesses _ _
      (run_steps entry.subject.prog n (Config.entry entry.subject.stmt ⟨entry.env, w⟩)) _ hb
  · exact absurd hb List.not_mem_nil

omit [Memory M] in
private theorem Config.mem_withMem (c : Config M) (m : M) : (c.withMem m).mem = m := by
  cases c <;> rfl

omit [Memory M] in
private theorem Config.inside_withMem (k : Cont) (c : Config M) (m : M) :
    (c.withMem m).Inside k ↔ c.Inside k := by
  cases c <;> rfl

omit [Memory M] in
private theorem Config.withMem_eq_run {c : Config M} {m m₀ : M} {st : Stmt} {k : Cont}
    {env : Env} (h : c.withMem m = .run st k env m₀) : ∃ w, c = .run st k env w := by
  cases c <;> simp_all [Config.withMem]

omit [Memory M] in
private theorem Config.withMem_eq_next {c : Config M} {m m₀ : M} {k : Cont}
    {env : Env} (h : c.withMem m = .next k env m₀) : ∃ w, c = .next k env w := by
  cases c <;> simp_all [Config.withMem]

/-- Replay at each step count. A matching memory and its stored witness have
the same events after `n` steps and the same configuration up to memory, and
their memories agree on the key and on every block updated so far. -/
theorem replay_trace {entry : CacheEntry d} {a : AllocatorAgreement M} {w m : M}
    (ha : ReplayAgreement a entry.key entry.footprint.writes w m)
    (hc : entry.Covers w) (hk : entry.KeyCovers) (n : Nat) :
    ∃ m', trace entry.subject ⟨entry.env, m⟩ n =
        ((trace entry.subject ⟨entry.env, w⟩ n).1,
          (trace entry.subject ⟨entry.env, w⟩ n).2.withMem m') ∧
      AgreeOn (updatedBlocks (trace entry.subject ⟨entry.env, w⟩ n).1 ++ entry.key)
        (trace entry.subject ⟨entry.env, w⟩ n).2.mem m' := by
  have hkey : ∀ evs c, Steps entry.subject.prog
      (Config.entry entry.subject.stmt ⟨entry.env, w⟩) evs c →
      AccessesCovered entry.key entry.footprint.writes evs := by
    intro evs c hs e he
    have h := hc.accesses evs c hs e he
    cases e with
    | read b => exact hk.1 h
    | _ => exact h
  have hr := run_agree (c := Config.entry entry.subject.stmt ⟨entry.env, w⟩) (m := m) ha hkey n
  obtain ⟨m', h₁, h₂⟩ := hr
  exact ⟨m', h₁, h₂.contents⟩

/-- A visit at a point carries over to every execution with the same events
and the same configurations up to memory. -/
private theorem atPoint_transfer {t : Subject} {σ σ' : State M}
    (h : ∀ i, ∃ m', (trace t σ' i).2 = (trace t σ i).2.withMem m')
    {q : QueryPoint} {n : Nat} (hv : AtPoint t σ' q n) : AtPoint t σ q n := by
  unfold AtPoint at hv ⊢
  cases hq : q.pos <;> rw [hq] at hv
  · obtain ⟨st, k, env, m, hc, hl, hcs⟩ := hv
    obtain ⟨m', he⟩ := h n
    obtain ⟨w, hw⟩ := Config.withMem_eq_run (he ▸ hc)
    exact ⟨st, k, env, w, hw, hl, hcs⟩
  · obtain ⟨n₀, st, k, env₀, m₀, env, m, hlt, h₀, hl, hcs, hn, hin⟩ := hv
    obtain ⟨m₁, he₀⟩ := h n₀
    obtain ⟨w₀, hw₀⟩ := Config.withMem_eq_run (he₀ ▸ h₀)
    obtain ⟨m₂, he⟩ := h n
    obtain ⟨w, hw⟩ := Config.withMem_eq_next (he ▸ hn)
    refine ⟨n₀, st, k, env₀, w₀, env, w, hlt, hw₀, hl, hcs, hw, ?_⟩
    intro i hi hi₀
    obtain ⟨m', hei⟩ := h i
    have := hin i hi hi₀
    rw [hei, Config.inside_withMem] at this
    exact this

/-- A visit at a point is preceded by a visit to its statement. -/
private theorem reach_of_atPoint {t : Subject} {σ : State M} {q : QueryPoint} {n : Nat}
    (hv : AtPoint t σ q n) : Reach t σ q.stmt := by
  have visit {i : Nat} {st : Stmt} {k : Cont} {env : Env} {m : M}
      (h : (trace t σ i).2 = .run st k env m) (hl : st.label = q.stmt) :
      Reach t σ q.stmt := by
    have hs := run_steps t.prog i (Config.entry t.stmt σ)
    change Steps t.prog _ (trace t σ i).1 (trace t σ i).2 at hs
    rw [h] at hs
    exact ⟨env, m, _, st, k, hs, hl⟩
  unfold AtPoint at hv
  cases hq : q.pos <;> rw [hq] at hv
  · obtain ⟨st, k, env, m, hc, hl, -⟩ := hv
    exact visit hc hl
  · obtain ⟨n₀, st, k, env₀, m₀, -, -, -, h₀, hl, -⟩ := hv
    exact visit h₀ hl

/-- On a prefix with no write to an issued block, the block holds its value
at entry with the marks of the sweeps: its content is in the swept value of
any state that covers the entry memory. -/
private theorem frame_answer {t : Subject} {σ : State M} {S : d.State} {b : Block}
    (hS : d.γ S σ.mem) (hb : Issued σ.mem b) {n : Nat}
    (hw : ∀ e ∈ (trace t σ n).1, ¬ e.Writes b) :
    (d.valueOf S b).swept (load (trace t σ n).2.mem b) := by
  have hs := run_steps t.prog n (Config.entry t.stmt σ)
  refine ⟨load σ.mem b, sweepTargets (trace t σ n).1, ⟨σ.mem, hS, rfl⟩, ?_⟩
  exact frame_of_not_written hb hs hw

/-- The answer of one line of the hit log contains the content of the block
at each visit of a member of the line at the point `p`, below the hit, and
the entry reports the statement as reached. `n` counts the steps of the
member's execution of the cached statement up to the visit. -/
theorem answer_sound {line : HitLine d} {p : QueryPoint} {a : AllocatorAgreement M}
    (hp : line.entry.ProducerSound) (hc : line.entry.Coverage)
    (hk : line.entry.KeyCovers) (hi : line.entry.InnerPartSound line.inner)
    (hb : ∀ m, d.γ line.state m → ∀ b ∈ line.blocks, Issued m b)
    {m : M} (hm : d.γ line.state m) (hmatch : line.entry.Matches a m)
    {n : Nat} (hv : AtPoint line.entry.subject ⟨line.entry.env, m⟩ p n) :
    line.entry.reached p.stmt ∧
      ∀ enabled b vs, line.answer enabled p b = some vs →
        vs (load (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem b) := by
  obtain ⟨w, hw, ha⟩ := hmatch
  have replay := replay_trace ha (hc w hw) hk
  have hcontrol (i : Nat) : ∃ m', (trace line.entry.subject ⟨line.entry.env, m⟩ i).2 =
      (trace line.entry.subject ⟨line.entry.env, w⟩ i).2.withMem m' := by
    obtain ⟨m', he, -⟩ := replay i
    exact ⟨m', by rw [he]⟩
  have hvw := atPoint_transfer hcontrol hv
  refine ⟨hp.reach w hw p.stmt (reach_of_atPoint hvw), ?_⟩
  obtain ⟨mn, heq, hagree⟩ := replay n
  have hmem : (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem = mn := by
    rw [heq]; exact Config.mem_withMem _ _
  have hevs : (trace line.entry.subject ⟨line.entry.env, m⟩ n).1 =
      (trace line.entry.subject ⟨line.entry.env, w⟩ n).1 := by rw [heq]
  -- The shared inner state covers the content of the block when the producer
  -- and the member agree on it at the visit.
  have fromInner {b : Block}
      (hin : b ∈ updatedBlocks (trace line.entry.subject ⟨line.entry.env, w⟩ n).1 ++ line.entry.key)
      (hr : b ∈ line.inner.updated p ++ line.entry.key) :
      d.valueOf (line.inner.state p) b
        (load (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem b) := by
    obtain ⟨r, hγ, hr'⟩ := hi.state w hw _ n hvw
    exact ⟨r, hγ, by rw [hmem, hr' b hr, hagree b hin]⟩
  -- A block bound at the call and not written so far keeps its call value.
  have fromCall {b : Block} (hbl : b ∈ line.blocks)
      (hnw : ∀ e ∈ (trace line.entry.subject ⟨line.entry.env, w⟩ n).1, ¬ e.Writes b) :
      (d.valueOf line.state b).swept
        (load (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem b) :=
    frame_answer (σ := ⟨line.entry.env, m⟩) hm (hb m hm b hbl) (hevs ▸ hnw)
  intro enabled b vs hq
  simp only [HitLine.answer] at hq
  split at hq
  · split at hq
    · -- A block of the matching key.
      rename_i hkey
      cases hq
      exact fromInner (List.mem_append_right _ hkey) (List.mem_append_right _ hkey)
    · split at hq
      · -- A frame block.
        rename_i _ hframe
        cases hq
        refine fromCall hframe.2 fun e he hwr => hframe.1 ?_
        have hcov := (hc w hw).accesses _ _
          (run_steps line.entry.subject.prog n
            (Config.entry line.entry.subject.stmt ⟨line.entry.env, w⟩)) e he
        cases e <;> simp only [Event.Writes] at hwr
        subst hwr
        exact hcov
      · split at hq
        · -- Absent from the recorded possible writes at the point.
          rename_i _ _ hnone
          cases hq
          refine fromCall hnone.2 fun e he hwr => hnone.1 ?_
          cases e <;> simp only [Event.Writes] at hwr
          subst hwr
          exact hi.mayWrite w hw _ n hvw _ he
        · split at hq
          · -- Listed as updated at the point.
            rename_i _ _ _ hup
            cases hq
            exact fromInner (List.mem_append_left _ (hi.updated w hw _ n hvw _ hup))
              (List.mem_append_left _ hup)
          · -- Top.
            cases hq
            trivial
  · cases hq

/-- The answer of a query on the callstack of a hit contains the content of
the block at each visit represented by a line that applies, and the entry of
that line reports the statement as reached. The query names the statement
`q.stmt`, the full callstack `q.callstack` and the position `q.pos`. Every
line of the log whose callstack ends `q.callstack` meets the premises on its
entry, its inner part and its bound blocks. `line` is one of these lines,
`m` a member of its call state that matches its entry, and `n` counts the
steps of the member's execution of the cached statement up to a visit at the
point below the hit. -/
theorem query_sound {log : List (HitLine d)} {q : QueryPoint} {a : AllocatorAgreement M}
    (hp : ∀ line ∈ log, line.callstack.isSuffixOf q.callstack → line.entry.ProducerSound)
    (hc : ∀ line ∈ log, line.callstack.isSuffixOf q.callstack → line.entry.Coverage)
    (hk : ∀ line ∈ log, line.callstack.isSuffixOf q.callstack → line.entry.KeyCovers)
    (hi : ∀ line ∈ log, line.callstack.isSuffixOf q.callstack →
      line.entry.InnerPartSound line.inner)
    (hb : ∀ line ∈ log, line.callstack.isSuffixOf q.callstack →
      ∀ m, d.γ line.state m → ∀ b ∈ line.blocks, Issued m b)
    {line : HitLine d} (hl : line ∈ log) (hs : line.callstack.isSuffixOf q.callstack)
    {m : M} (hm : d.γ line.state m) (hmatch : line.entry.Matches a m)
    {n : Nat} (hv : AtPoint line.entry.subject ⟨line.entry.env, m⟩ (q.below line.callstack) n) :
    line.entry.reached q.stmt ∧
      ∀ enabled b vs, query enabled log q b = some vs →
        vs (load (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem b) := by
  have h := answer_sound (hp line hl hs) (hc line hl hs) (hk line hl hs) (hi line hl hs)
    (hb line hl hs) hm hmatch hv
  refine ⟨h.1, fun enabled b vs hq => (mem_query hq _).2 ⟨line, hl, hs, ?_⟩⟩
  cases ha : line.answer enabled (q.below line.callstack) b with
  | none => trivial
  | some x => exact h.2 enabled b x ha

end CacheEntry

end ReuseModel
