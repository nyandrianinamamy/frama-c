import ReuseModel
import Checks.Entries
import Checks.Sweeps

/-!
# State queries on the callstack of a hit

Globals `x`, `g` and `r` are blocks 0, 1 and 2. The cached statement is the
body of `f`:

```
f: L1: { L2: assert x;  L3: h(); }
h: L20: { L21: r = 0;  L22: ; }
```

The key is `{x}`; `r` is written on every path to the exit and is outside
the key; `g` is not touched. `main` calls `f` at site 11 with
`x, g, r = 1, 4, 3`, then sets `g = 9` and `r = 5` and calls `f` at site 16.
The first call produces the entry; the second matches it. The hit log has a
line for each call.

* Two-call example: before `r = 0;`, on the callstacks `[3, 11]` and
  `[3, 16]`, the query on `g` answers 4 and 9. The stored inner state holds
  4 there.
* Overwritten block: before `r = 0;`, the stored inner state holds `{3}`;
  on the callstack `[3, 16]` the query on `r` answers 5. After `r = 0;` the
  query answers 0, and the value 5 at the call is wrong.

Each answer is the conclusion of `CacheEntry.query_sound`, with every
premise proved for every line of the log. A second program calls `f` at
site 11 and then in a loop at site 16; its logs have three lines. Two lines
on one callstack, and two lines whose callstacks end the callstack of the
query with different lengths, are joined. A second entry, for the body of
`h`, has an inner part with states on the key only. Checks on that kind of
inner part for `f` show that its states must cover the producing visits,
and that the rule for updated blocks reads the recorded list. A second
statement, with a lexical local, has the case of a local of the body, which
answers top. Two further checks pin definitions: the marks of the sweeps in
the frame rule, and the end of a statement's execution in the visit after
it.
-/

namespace Checks

open ReuseModel Memory

def queryBody : Stmt := .seq 1 (.assert 2 (.var "x")) (.call 3 none "h" [])

def queryCallee : Stmt := .seq 20 (.assign 21 (.var "r") (.const 0)) (.skip 22)

def queryProg : Program where
  funs := [("f", ⟨[], [], queryBody⟩), ("h", ⟨[], [], queryCallee⟩)]
  globals := fun x => if x = "x" then some 0 else if x = "g" then some 1
    else if x = "r" then some 2 else none

def querySubj : Subject := ⟨queryProg, queryBody,
  ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide,
    Or.inl (by decide)⟩⟩

/-- The memory at a call of `f`: `x = 1`, and `g` and `r` as given. -/
def queryMem (g r : Int) : FunMem := memOf [.int 1, .int g, .int r]

/-- The state at a call of `f`, as a set of memories. -/
def callState (g r : Int) (m : FunMem) : Prop :=
  load m 0 = some (.int 1) ∧ load m 1 = some (.int g) ∧
    load m 2 = some (.int r) ∧ m.next = 3

instance (g r : Int) (m : FunMem) : Decidable (callState g r m) := by
  unfold callState; infer_instance

/-- The names of the example denote the cells of `queryMem`, and `f` runs
with no binding of its own. -/
example (g r : Int) :
    (evalExpr queryProg noLocals (queryMem g r) (.var "x")).2 = .ok (.int 1) ∧
    (evalExpr queryProg noLocals (queryMem g r) (.var "g")).2 = .ok (.int g) ∧
    (evalExpr queryProg noLocals (queryMem g r) (.var "r")).2 = .ok (.int r) ∧
    Env.bind [] [] = noLocals :=
  ⟨rfl, rfl, rfl, rfl⟩

private theorem funMem_ext {m m' : FunMem} (hc : ∀ b, m.cells b = m'.cells b)
    (hn : m.next = m'.next) : m = m' := by
  obtain ⟨c, n, f⟩ := m
  obtain ⟨c', n', f'⟩ := m'
  simp only at hc hn
  subst hn
  have h : c = c' := funext hc
  subst h
  rfl

/-- The state at a call determines the memory. -/
theorem callState_eq {g r : Int} {m : FunMem} (h : callState g r m) : m = queryMem g r := by
  obtain ⟨h₀, h₁, h₂, hn⟩ := h
  refine funMem_ext ?_ hn
  intro b
  by_cases hb : b < 3
  · match b, hb with
    | 0, _ => exact h₀
    | 1, _ => exact h₁
    | 2, _ => exact h₂
  · have h3 : 3 ≤ b := Nat.le_of_not_lt hb
    rw [m.fresh b (by rw [hn]; exact h3), (queryMem g r).fresh b h3]

theorem callState_queryMem (g r : Int) : callState g r (queryMem g r) :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- The program that makes the two calls, outside the functions. -/
def queryMain : Stmt :=
  .seq 10 (.call 11 none "f" [])
    (.seq 12 (.assign 13 (.var "g") (.const 9))
      (.seq 14 (.assign 15 (.var "r") (.const 5)) (.call 16 none "f" [])))

/-- The call sites of a configuration about to execute a statement. -/
def callstackOf? {M : Type} : Config M → Option (List Label)
  | .run _ k _ _ => some k.callstack
  | _ => none

/-- `main` enters the body of `f` at site 11 in the state `callState 4 3`
and at site 16 in the state `callState 9 5`. -/
theorem two_call_sites :
    let r := fun n => run queryProg n (Config.entry queryMain ⟨noLocals, queryMem 4 3⟩)
    labelOf? (r 2).2 = some 1 ∧ callstackOf? (r 2).2 = some [11] ∧
      callState 4 3 (r 2).2.mem ∧
    labelOf? (r 22).2 = some 1 ∧ callstackOf? (r 22).2 = some [16] ∧
      callState 9 5 (r 22).2.mem := by
  decide

/-- The entry stored by the call at site 11. -/
def queryEntry : CacheEntry predicates where
  subject := querySubj
  env := noLocals
  input := callState 4 3
  key := [0]
  footprint := ⟨[0], [2], [2], [2]⟩
  exit := fun o m => o = .completed ∧ load m 2 = some (.int 0)
  violations := fun _ => False
  reached := (· ∈ [1, 2, 3, 20, 21, 22])

/-- Before `r = 0;` in `h`, called at site 3 of `f`. -/
def beforeWrite : QueryPoint := ⟨21, [3], .before⟩

/-- After `r = 0;`. -/
def afterWrite : QueryPoint := ⟨21, [3], .after⟩

/-- The stored inner state before the write. -/
def innerBefore (m : FunMem) : Prop :=
  load m 0 = some (.int 1) ∧ load m 1 = some (.int 4) ∧ load m 2 = some (.int 3)

/-- The stored inner state after the write. -/
def innerAfter (m : FunMem) : Prop :=
  load m 0 = some (.int 1) ∧ load m 1 = some (.int 4) ∧ load m 2 = some (.int 0)

instance (m : FunMem) : Decidable (innerBefore m) := by
  unfold innerBefore; infer_instance

instance (m : FunMem) : Decidable (innerAfter m) := by
  unfold innerAfter; infer_instance

/-- The inner part stored by the producing call: the states before and after
the write, no write before it, `r` updated after it. Elsewhere the state is
top and `r` may have been written. -/
def queryInner : InnerPart predicates where
  state q := if q = beforeWrite then innerBefore
    else if q = afterWrite then innerAfter else fun _ => True
  mayWrite q := if q = beforeWrite then [] else [2]
  updated q := if q = afterWrite then [2] else []

/-- The line of the hit log for a call at `site`. -/
def queryLine (site : Label) (g r : Int) : HitLine predicates :=
  ⟨[site], queryEntry, queryInner, callState g r, [0, 1, 2]⟩

def queryLog : List (HitLine predicates) := [queryLine 11 4 3, queryLine 16 9 5]

/-! ## The producing execution -/

private def producerRun (n : Nat) : List Event × Config FunMem :=
  trace querySubj ⟨noLocals, queryMem 4 3⟩ n

private theorem producer_bound (n : Nat) : ∃ i : Fin 12, producerRun n = producerRun i := by
  have hs (extra : Nat) : producerRun (extra + 11) = producerRun 11 := by
    cases extra <;> rfl
  by_cases hlt : n < 12
  · exact ⟨⟨n, hlt⟩, rfl⟩
  · have he : n = (n - 11) + 11 := by omega
    exact ⟨11, by rw [he, hs]; rfl⟩

private def ProducerTrace (evs : List Event) (c : Config FunMem) : Prop :=
  (∀ e ∈ evs, e = .read 0 ∨ e = .write 2) ∧
  match c with
  | .run (.assert l e) _ env m => l = 2 ∧ assertionHolds queryProg env m e = true
  | .run s _ _ m => s.label ∈ [1, 3, 20, 21, 22] ∧
      (s.label = 21 → Event.write 2 ∉ evs ∧ innerBefore m)
  | .next _ _ m => Event.write 2 ∈ evs → innerAfter m
  | .done o m => o = .completed ∧ load m 2 = some (.int 0) ∧ Event.write 2 ∈ evs
  | .fault .. => False
  | .ret .. => True

private instance (evs : List Event) (c : Config FunMem) :
    Decidable (ProducerTrace evs c) := by
  unfold ProducerTrace
  refine @instDecidableAnd _ _ inferInstance ?_
  split <;> infer_instance

private theorem producer_trace :
    ∀ n : Fin 12, ProducerTrace (producerRun n).1 (producerRun n).2 := by
  decide

/-- The write precedes every configuration after the visit to `r = 0;`. -/
private theorem producer_after_write :
    ∀ n₀ n : Fin 12, n₀ < n → labelOf? (producerRun n₀).2 = some 21 →
      Event.write 2 ∈ (producerRun n).1 := by
  decide

private theorem producer_at (n : Nat) :
    ProducerTrace (producerRun n).1 (producerRun n).2 := by
  obtain ⟨i, hi⟩ := producer_bound n
  rw [hi]
  exact producer_trace i

private theorem producer_eq {w : FunMem} (hw : queryEntry.input w) :
    (⟨queryEntry.env, w⟩ : State FunMem) = ⟨noLocals, queryMem 4 3⟩ := by
  rw [callState_eq hw]
  rfl

private theorem producer_prefix {w : FunMem} (hw : queryEntry.input w)
    {evs : List Event} {c : Config FunMem}
    (h : Prefix querySubj ⟨queryEntry.env, w⟩ evs c) : ProducerTrace evs c := by
  rw [producer_eq hw] at h
  obtain ⟨n, hn⟩ := steps_run h
  have ht := producer_at n
  change producerRun n = (evs, c) at hn
  rw [hn] at ht
  exact ht

theorem query_entry_premises :
    queryEntry.ProducerSound ∧ queryEntry.Coverage ∧ queryEntry.KeyCovers := by
  refine ⟨⟨?_, ?_, ?_⟩, ?_, ?_⟩
  · rintro m hm o out ⟨evs, he⟩
    obtain ⟨-, ho, hval, -⟩ := producer_prefix hm he
    exact ⟨ho, hval⟩
  · intro m hm v hv
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, he⟩ := hv
      exact (producer_prefix hm he).2
    | assertion l =>
      obtain ⟨evs, e, k, env, out, he, hf⟩ := hv
      have ht := (producer_prefix hm he).2
      change l = 2 ∧ assertionHolds queryProg env out e = true at ht
      change assertionHolds queryProg env out e = false at hf
      rw [ht.2] at hf
      contradiction
  · rintro m hm l ⟨env, out, evs, s, k, he, rfl⟩
    have ht := (producer_prefix hm he).2
    change s.label ∈ [1, 2, 3, 20, 21, 22]
    cases s
    case assert l e =>
      change l ∈ [1, 2, 3, 20, 21, 22]
      rw [ht.1]
      decide
    all_goals
      have h := ht.1
      simp only [Stmt.label, List.mem_cons, List.not_mem_nil, or_false] at h ⊢
      rcases h with h | h | h | h | h <;> simp [h]
  · intro m hm
    constructor
    · intro evs c he e hmem
      rcases (producer_prefix hm he).1 e hmem with rfl | rfl <;> exact List.mem_cons_self
    · intro evs o out he b hb
      rcases (producer_prefix hm he).1 (.write b) hb with h | h
      · contradiction
      · cases h; exact List.mem_cons_self
    · intro evs o out he b hb
      simp only [queryEntry, List.mem_singleton] at hb
      subst b
      exact (producer_prefix hm he).2.2.2
  · exact ⟨fun _ h => h, fun _ hb h => (h hb).elim⟩

/-- A visit before the write is a visit to `r = 0;`; a visit after it follows
one. -/
private theorem producer_point {w : FunMem} (hw : queryEntry.input w) {q : QueryPoint}
    {n : Nat} (hv : AtPoint queryEntry.subject ⟨queryEntry.env, w⟩ q n) :
    (q = beforeWrite → ∃ s k env m, producerRun n = ((producerRun n).1, .run s k env m) ∧
        s.label = 21) ∧
      (q = afterWrite → ∃ n₀ k env m, n₀ < n ∧ labelOf? (producerRun n₀).2 = some 21 ∧
        producerRun n = ((producerRun n).1, .next k env m)) := by
  rw [producer_eq hw] at hv
  constructor
  · rintro rfl
    obtain ⟨s, k, env, m, hc, hl, -⟩ := hv
    exact ⟨s, k, env, m, by rw [← hc]; rfl, hl⟩
  · rintro rfl
    obtain ⟨n₀, s, k, env₀, m₀, env, m, hlt, h₀, hl, -, hn, -⟩ := hv
    refine ⟨n₀, k, env, m, hlt, ?_, by rw [← hn]; rfl⟩
    change labelOf? (trace queryEntry.subject ⟨noLocals, queryMem 4 3⟩ n₀).2 = some 21
    rw [h₀]
    exact congrArg some hl

private theorem fin12 (n₀ n : Nat) (hlt : n₀ < n) (hn : n < 12) :
    ∃ i j : Fin 12, i.val = n₀ ∧ j.val = n ∧ i < j :=
  ⟨⟨n₀, by omega⟩, ⟨n, hn⟩, rfl, rfl, hlt⟩

theorem query_inner_sound : queryEntry.InnerPartSound queryInner := by
  -- A configuration after a visit to `r = 0;` comes after the write.
  have written {w : FunMem} (hw : queryEntry.input w) {n₀ n : Nat}
      {k : Cont} {env : Env} {m : FunMem} (hlt : n₀ < n)
      (h₀ : labelOf? (producerRun n₀).2 = some 21)
      (hn : producerRun n = ((producerRun n).1, .next k env m)) :
      Event.write 2 ∈ (producerRun n).1 ∧ innerAfter m := by
    have hnext : ∀ j, 11 ≤ j → (producerRun j).2 = (producerRun 11).2 := by
      intro j hj
      obtain ⟨i, hi⟩ := producer_bound j
      have hs (extra : Nat) : producerRun (extra + 11) = producerRun 11 := by
        cases extra <;> rfl
      have he : j = (j - 11) + 11 := by omega
      rw [he, hs]
    have hlt12 : n < 12 := by
      refine Nat.lt_of_not_le fun hge => ?_
      have h := hnext n (by omega)
      rw [hn] at h
      change Config.next k env m = (producerRun 11).2 at h
      have h11 : (producerRun 11).2 = .done .completed (producerRun 11).2.mem := rfl
      rw [h11] at h
      cases h
    obtain ⟨i, j, rfl, rfl, hij⟩ := fin12 n₀ n hlt hlt12
    have hw2 := producer_after_write i j hij h₀
    refine ⟨hw2, ?_⟩
    have ht := (producer_at j).2
    rw [hn] at ht
    exact ht hw2
  refine ⟨?_, ?_, ?_⟩
  · intro w hw q n hv
    obtain ⟨hb, ha⟩ := producer_point hw hv
    rw [producer_eq hw]
    change ∃ r, queryInner.state q r ∧ AgreeOn _ r (producerRun n).2.mem
    by_cases hq₁ : q = beforeWrite
    · obtain ⟨s, k, env, m, hc, hl⟩ := hb hq₁
      have ht := (producer_at n).2
      rw [hc] at ht ⊢
      refine ⟨m, ?_, fun _ _ => rfl⟩
      subst hq₁
      change innerBefore m
      cases s
      all_goals first
        | exact (ht.2 hl).2
        | (simp only [Stmt.label] at hl; subst hl; exact absurd ht.1 (by decide))
    · by_cases hq₂ : q = afterWrite
      · obtain ⟨n₀, k, env, m, hlt, h₀, hn⟩ := ha hq₂
        rw [hn]
        refine ⟨m, ?_, fun _ _ => rfl⟩
        subst hq₂
        exact (written hw hlt h₀ hn).2
      · refine ⟨(producerRun n).2.mem, ?_, fun _ _ => rfl⟩
        simp only [queryInner, hq₁, hq₂, if_false]
  · intro w hw q n hv b hb
    obtain ⟨hbw, -⟩ := producer_point hw hv
    rw [producer_eq hw] at hb
    change Event.write b ∈ (producerRun n).1 at hb
    have hev := (producer_at n).1 _ hb
    have hb2 : b = 2 := by
      rcases hev with h | h <;> cases h; rfl
    subst hb2
    by_cases hq₁ : q = beforeWrite
    · obtain ⟨s, k, env, m, hc, hl⟩ := hbw hq₁
      have ht := (producer_at n).2
      rw [hc] at ht hb
      cases s
      all_goals first
        | exact absurd hb (ht.2 hl).1
        | (simp only [Stmt.label] at hl; subst hl; exact absurd ht.1 (by decide))
    · simp only [queryInner, hq₁, if_false]
      exact List.mem_cons_self
  · intro w hw q n hv b hb
    obtain ⟨-, ha⟩ := producer_point hw hv
    by_cases hq₂ : q = afterWrite
    · simp only [queryInner, hq₂, if_true, List.mem_singleton] at hb
      subst hb
      obtain ⟨n₀, k, env, m, hlt, h₀, hn⟩ := ha hq₂
      rw [producer_eq hw]
      exact List.mem_filterMap.mpr ⟨.write 2, (written hw hlt h₀ hn).1, rfl⟩
    · simp only [queryInner, hq₂, if_false] at hb
      exact absurd hb List.not_mem_nil

/-! ## The members and the theorem at each line -/

/-- Every call state matches the entry: the stored witness is the producing
memory, and the key holds `x = 1` in both. -/
theorem query_member_matches (g r : Int) :
    queryEntry.Matches FunMem.allocatorAgreement (queryMem g r) :=
  ⟨queryMem 4 3, callState_queryMem 4 3, ⟨fun b hb => by
      simp only [queryEntry, List.mem_singleton] at hb; subst hb; rfl,
    fun b hb => by simp only [queryEntry, List.mem_singleton] at hb; subst hb; rfl, rfl⟩⟩

/-- The visits of a member before and after `r = 0;`, and the contents there. -/
theorem query_member_visits (g r : Int) :
    AtPoint querySubj ⟨noLocals, queryMem g r⟩ beforeWrite 5 ∧
    AtPoint querySubj ⟨noLocals, queryMem g r⟩ afterWrite 6 ∧
    load (trace querySubj ⟨noLocals, queryMem g r⟩ 5).2.mem 1 = some (.int g) ∧
    load (trace querySubj ⟨noLocals, queryMem g r⟩ 5).2.mem 2 = some (.int r) ∧
    load (trace querySubj ⟨noLocals, queryMem g r⟩ 6).2.mem 2 = some (.int 0) := by
  refine ⟨⟨_, _, _, _, rfl, rfl, rfl⟩,
    ⟨5, _, _, _, _, _, _, by decide, rfl, rfl, rfl, rfl, by intro i hi hi'; omega⟩,
    rfl, rfl, rfl⟩

/-- Every block that a line binds is issued in each memory of the call
state. -/
private theorem callState_issued (g r : Int) :
    ∀ m, callState g r m → ∀ b ∈ ([0, 1, 2] : BlockSet), Issued m b := by
  intro m hm b hb
  have hn : m.next = 3 := hm.2.2.2
  change b < m.next
  rw [hn]
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hb
  rcases hb with h | h | h <;> subst h <;> decide

/-- The premises of `CacheEntry.query_sound` on one line of a log: the
premises on its entry and its inner part, and the issuance of the blocks it
binds. -/
def LinePremises (line : HitLine predicates) : Prop :=
  line.entry.ProducerSound ∧ line.entry.Coverage ∧ line.entry.KeyCovers ∧
    line.entry.InnerPartSound line.inner ∧
    ∀ m, predicates.γ line.state m → ∀ b ∈ line.blocks, Issued m b

/-- Each line of a call of `f` meets the premises. -/
theorem queryLine_premises (site : Label) (g r : Int) : LinePremises (queryLine site g r) :=
  ⟨query_entry_premises.1, query_entry_premises.2.1, query_entry_premises.2.2,
    query_inner_sound, callState_issued g r⟩

/-- `CacheEntry.query_sound` for a log whose lines all meet the premises. -/
private theorem log_sound {log : List (HitLine predicates)}
    (hlog : ∀ line ∈ log, LinePremises line) {q : QueryPoint} {line : HitLine predicates}
    (hl : line ∈ log) (hs : line.callstack.isSuffixOf q.callstack)
    {m : FunMem} (hm : predicates.γ line.state m)
    (hmatch : line.entry.Matches FunMem.allocatorAgreement m) {n : Nat}
    (hv : AtPoint line.entry.subject ⟨line.entry.env, m⟩ (q.below line.callstack) n) :
    line.entry.reached q.stmt ∧ ∀ enabled b vs, query enabled log q b = some vs →
      vs (load (trace line.entry.subject ⟨line.entry.env, m⟩ n).2.mem b) :=
  CacheEntry.query_sound (fun l hl _ => (hlog l hl).1) (fun l hl _ => (hlog l hl).2.1)
    (fun l hl _ => (hlog l hl).2.2.1) (fun l hl _ => (hlog l hl).2.2.2.1)
    (fun l hl _ => (hlog l hl).2.2.2.2) hl hs hm hmatch hv

/-- `CacheEntry.query_sound` at the line of the call of `f` at `site`, for a
query on the callstack `[3, site]` before or after `r = 0;`, in a log whose
lines all meet the premises. -/
theorem query_at_line {log : List (HitLine predicates)}
    (hlog : ∀ line ∈ log, LinePremises line) (site : Label) (g r : Int) (pos : Pos)
    (hl : queryLine site g r ∈ log) :
    queryEntry.reached 21 ∧ ∀ enabled b vs,
      query enabled log ⟨21, [3, site], pos⟩ b = some vs →
        vs (load (trace querySubj ⟨noLocals, queryMem g r⟩
          (if pos = .before then 5 else 6)).2.mem b) := by
  have hs : [site].isSuffixOf [3, site] = true := by
    simp [List.isSuffixOf, List.isPrefixOf]
  have hv := query_member_visits g r
  cases pos with
  | before =>
    exact log_sound (q := ⟨21, [3, site], .before⟩) hlog hl hs (callState_queryMem g r)
      (query_member_matches g r) hv.1
  | after =>
    exact log_sound (q := ⟨21, [3, site], .after⟩) hlog hl hs (callState_queryMem g r)
      (query_member_matches g r) hv.2.1

/-- Both lines of `queryLog` meet the premises. -/
private theorem queryLog_premises : ∀ line ∈ queryLog, LinePremises line := by
  intro line hl
  simp only [queryLog, List.mem_cons, List.not_mem_nil, or_false] at hl
  rcases hl with rfl | rfl <;> exact queryLine_premises _ _ _

/-! ## The answers -/

private theorem applySweeps_int (targets : List Block) (z : Int) :
    applySweeps targets (some (.int z)) = some (.int z) :=
  (applySweeps_eq_iff _ _).2 fun _ _ h => by cases h

private theorem swept_int {vs : ValueSet} {z : Int} (h : ∀ v, vs v ↔ v = some (.int z)) :
    ∀ u, vs.swept u ↔ u = some (.int z) := by
  intro u
  constructor
  · rintro ⟨v, targets, hv, rfl⟩
    rw [(h v).1 hv, applySweeps_int]
  · rintro rfl
    exact ⟨_, [], (h _).2 rfl, rfl⟩

private theorem valueOf_call (g r : Int) :
    (∀ v, predicates.valueOf (callState g r) 1 v ↔ v = some (.int g)) ∧
    (∀ v, predicates.valueOf (callState g r) 2 v ↔ v = some (.int r)) := by
  constructor
  · intro v
    constructor
    · rintro ⟨m, hm, rfl⟩; exact hm.2.1
    · rintro rfl; exact ⟨queryMem g r, callState_queryMem g r, rfl⟩
  · intro v
    constructor
    · rintro ⟨m, hm, rfl⟩; exact hm.2.2.1
    · rintro rfl; exact ⟨queryMem g r, callState_queryMem g r, rfl⟩

private theorem valueOf_inner :
    (∀ v, predicates.valueOf (queryInner.state beforeWrite) 0 v ↔ v = some (.int 1)) ∧
    (∀ v, predicates.valueOf (queryInner.state beforeWrite) 1 v ↔ v = some (.int 4)) ∧
    (∀ v, predicates.valueOf (queryInner.state beforeWrite) 2 v ↔ v = some (.int 3)) ∧
    (∀ v, predicates.valueOf (queryInner.state afterWrite) 2 v ↔ v = some (.int 0)) := by
  have hb : queryInner.state beforeWrite = innerBefore := rfl
  have ha : queryInner.state afterWrite = innerAfter := rfl
  have wb : innerBefore (queryMem 4 3) := ⟨rfl, rfl, rfl⟩
  have wa : innerAfter (queryMem 4 0) := ⟨rfl, rfl, rfl⟩
  rw [hb, ha]
  refine ⟨fun v => ⟨?_, ?_⟩, fun v => ⟨?_, ?_⟩, fun v => ⟨?_, ?_⟩, fun v => ⟨?_, ?_⟩⟩
  all_goals first
    | (rintro ⟨m, hm, rfl⟩; first | exact hm.1 | exact hm.2.1 | exact hm.2.2)
    | (rintro rfl; first | exact ⟨_, wb, rfl⟩ | exact ⟨_, wa, rfl⟩)

/-- The two-call example. Before `r = 0;`, the query on `g` answers exactly 4
on the callstack `[3, 11]` and exactly 9 on `[3, 16]`, and each answer
contains the content of `g` at the visit of that call. The stored inner
state holds 4 for `g` there, which misses the 9 of the second call. -/
theorem two_call_query :
    (query true queryLog ⟨21, [3, 11], .before⟩ 1 =
        some (predicates.valueOf (callState 4 3) 1).swept ∧
      (∀ u, (predicates.valueOf (callState 4 3) 1).swept u ↔ u = some (.int 4)) ∧
      load (trace querySubj ⟨noLocals, queryMem 4 3⟩ 5).2.mem 1 = some (.int 4) ∧
      (predicates.valueOf (callState 4 3) 1).swept
        (load (trace querySubj ⟨noLocals, queryMem 4 3⟩ 5).2.mem 1)) ∧
    (query true queryLog ⟨21, [3, 16], .before⟩ 1 =
        some (predicates.valueOf (callState 9 5) 1).swept ∧
      (∀ u, (predicates.valueOf (callState 9 5) 1).swept u ↔ u = some (.int 9)) ∧
      load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1 = some (.int 9) ∧
      (predicates.valueOf (callState 9 5) 1).swept
        (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1)) ∧
    (∀ v, predicates.valueOf (queryInner.state beforeWrite) 1 v ↔ v = some (.int 4)) ∧
    ¬ predicates.valueOf (queryInner.state beforeWrite) 1
      (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1) := by
  have h₁ := (query_at_line queryLog_premises 11 4 3 .before List.mem_cons_self).2 true 1 _ rfl
  have h₂ := (query_at_line queryLog_premises 16 9 5 .before (List.mem_cons_of_mem _ List.mem_cons_self)).2 true 1 _ rfl
  refine ⟨⟨rfl, swept_int (valueOf_call 4 3).1, rfl, h₁⟩,
    ⟨rfl, swept_int (valueOf_call 9 5).1, rfl, h₂⟩, valueOf_inner.2.1, ?_⟩
  rw [(query_member_visits 9 5).2.2.1, valueOf_inner.2.1]
  decide

/-- The overwritten block. The stored inner state holds `{3}` for `r` before
`r = 0;`; the second call enters with `r = 5`. On the callstack `[3, 16]`,
the query on `r` answers exactly 5 before the write and exactly 0 after it,
and each answer contains the content at the visit. The stored value misses
the 5 before the write, and the value 5 at the call misses the 0 after
it. -/
theorem overwritten_query :
    (∀ v, predicates.valueOf (queryInner.state beforeWrite) 2 v ↔ v = some (.int 3)) ∧
    (query true queryLog ⟨21, [3, 16], .before⟩ 2 =
        some (predicates.valueOf (callState 9 5) 2).swept ∧
      (∀ u, (predicates.valueOf (callState 9 5) 2).swept u ↔ u = some (.int 5)) ∧
      load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 2 = some (.int 5) ∧
      (predicates.valueOf (callState 9 5) 2).swept
        (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 2)) ∧
    (query true queryLog ⟨21, [3, 16], .after⟩ 2 =
        some (predicates.valueOf (queryInner.state afterWrite) 2) ∧
      (∀ u, predicates.valueOf (queryInner.state afterWrite) 2 u ↔ u = some (.int 0)) ∧
      load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 6).2.mem 2 = some (.int 0) ∧
      predicates.valueOf (queryInner.state afterWrite) 2
        (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 6).2.mem 2)) ∧
    ¬ predicates.valueOf (queryInner.state beforeWrite) 2
      (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 2) ∧
    ¬ (predicates.valueOf (callState 9 5) 2).swept
      (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 6).2.mem 2) := by
  have hb := (query_at_line queryLog_premises 16 9 5 .before (List.mem_cons_of_mem _ List.mem_cons_self)).2 true 2 _ rfl
  have ha := (query_at_line queryLog_premises 16 9 5 .after (List.mem_cons_of_mem _ List.mem_cons_self)).2 true 2 _ rfl
  refine ⟨valueOf_inner.2.2.1, ⟨rfl, swept_int (valueOf_call 9 5).2, rfl, hb⟩,
    ⟨rfl, valueOf_inner.2.2.2, rfl, ha⟩, ?_, ?_⟩
  · rw [(query_member_visits 9 5).2.2.2.1, valueOf_inner.2.2.1]
    decide
  · rw [(query_member_visits 9 5).2.2.2.2, swept_int (valueOf_call 9 5).2]
    decide

/-- The key block `x` takes the shared inner state; with reconstruction
disabled the query reports no state, and the entry still reports the
statement as reached. -/
theorem key_and_disabled_query :
    query true queryLog ⟨21, [3, 16], .before⟩ 0 =
        some (predicates.valueOf (queryInner.state beforeWrite) 0) ∧
      (∀ u, predicates.valueOf (queryInner.state beforeWrite) 0 u ↔ u = some (.int 1)) ∧
    (∀ b, query false queryLog ⟨21, [3, 16], .before⟩ b = none) ∧
    queryEntry.reached 21 :=
  ⟨rfl, valueOf_inner.1, fun _ => rfl, (query_at_line queryLog_premises 16 9 5 .before (List.mem_cons_of_mem _ List.mem_cons_self)).1⟩

/-- A point whose callstack is not that of a call of `h` has no visit, before
or after `r = 0;`. -/
theorem query_point_callstack :
    ¬ AtPoint querySubj ⟨noLocals, queryMem 9 5⟩ ⟨21, [], .before⟩ 5 ∧
    ¬ AtPoint querySubj ⟨noLocals, queryMem 9 5⟩ ⟨21, [], .after⟩ 6 := by
  have h : (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.cont.callstack = [3] := rfl
  constructor
  · rintro ⟨s, k, env, m, hc, -, hcs⟩
    rw [hc] at h
    change k.callstack = [3] at h
    rw [hcs] at h
    exact absurd h (by decide)
  · rintro ⟨n₀, s, k, env₀, m₀, env, m, hlt, h₀, hl, hcs, -, -⟩
    have hlab : labelOf? (trace querySubj ⟨noLocals, queryMem 9 5⟩ n₀).2 = some 21 := by
      rw [h₀]; exact congrArg some hl
    have hn₀ : n₀ = 5 := by
      have hall : ∀ j : Fin 6,
          labelOf? (trace querySubj ⟨noLocals, queryMem 9 5⟩ j).2 = some 21 → j.val = 5 := by
        decide
      exact hall ⟨n₀, hlt⟩ hlab
    subst hn₀
    rw [h₀] at h
    change k.callstack = [3] at h
    rw [hcs] at h
    exact absurd h (by decide)

/-! ## Several lines on the callstack of a query

`loopMain` calls `f` at site 11, then calls it in a loop at site 16 and sets
`g = 9` and `r = 5` after each call. The first call at site 16 enters with
`g = 4` and `r = 0`, the second with `g = 9` and `r = 5`. When every call
after the first is a hit, the log has three lines, two of them on the
callstack `[16]`. When the first call at site 16 is analysed and its call of
`h` hits an entry stored for `h`, the log has a line on `[3, 16]` for that
call of `h` and a line on `[16]` for the second call of `f`: both end the
callstack `[3, 16]` of a query in `h`. -/

/-- `f()` at site 11, then `while (x) { f() at 16; g = 9; r = 5; }`. -/
def loopMain : Stmt :=
  .seq 10 (.call 11 none "f" [])
    (.loop 12 (.var "x")
      (.seq 13 (.call 16 none "f" [])
        (.seq 14 (.assign 15 (.var "g") (.const 9)) (.assign 17 (.var "r") (.const 5)))))

/-- The run of `loopMain` from `x, g, r = 1, 4, 3`. Its first three visits
before `r = 0;` are at steps 7, 23 and 44, on the callstacks `[3, 11]`,
`[3, 16]` and `[3, 16]`, with `g = 4`, 4 and 9. It enters `f` at steps 2,
18 and 39, and `h` at steps 6, 22 and 43, in the states `callState 4 3`,
`callState 4 0` and `callState 9 5`. -/
theorem loop_visits :
    let r := fun n => run queryProg n (Config.entry loopMain ⟨noLocals, queryMem 4 3⟩)
    (∀ n : Fin 45, labelOf? (r n).2 = some 21 → n.val = 7 ∨ n.val = 23 ∨ n.val = 44) ∧
    (labelOf? (r 7).2 = some 21 ∧ callstackOf? (r 7).2 = some [3, 11] ∧
      load (r 7).2.mem 1 = some (.int 4)) ∧
    (labelOf? (r 23).2 = some 21 ∧ callstackOf? (r 23).2 = some [3, 16] ∧
      load (r 23).2.mem 1 = some (.int 4)) ∧
    (labelOf? (r 44).2 = some 21 ∧ callstackOf? (r 44).2 = some [3, 16] ∧
      load (r 44).2.mem 1 = some (.int 9)) ∧
    (labelOf? (r 2).2 = some 1 ∧ callstackOf? (r 2).2 = some [11] ∧
      callState 4 3 (r 2).2.mem) ∧
    (labelOf? (r 18).2 = some 1 ∧ callstackOf? (r 18).2 = some [16] ∧
      callState 4 0 (r 18).2.mem) ∧
    (labelOf? (r 39).2 = some 1 ∧ callstackOf? (r 39).2 = some [16] ∧
      callState 9 5 (r 39).2.mem) ∧
    (labelOf? (r 6).2 = some 20 ∧ callstackOf? (r 6).2 = some [3, 11] ∧
      callState 4 3 (r 6).2.mem) ∧
    (labelOf? (r 22).2 = some 20 ∧ callstackOf? (r 22).2 = some [3, 16] ∧
      callState 4 0 (r 22).2.mem) ∧
    (labelOf? (r 43).2 = some 20 ∧ callstackOf? (r 43).2 = some [3, 16] ∧
      callState 9 5 (r 43).2.mem) := by
  decide

/-- The log of `loopMain` when both calls at site 16 hit the entry. -/
def loopLog : List (HitLine predicates) :=
  [queryLine 11 4 3, queryLine 16 4 0, queryLine 16 9 5]

/-- The lines of `loopLog` meet the premises. -/
private theorem loopLog_premises : ∀ line ∈ loopLog, LinePremises line := by
  intro line hl
  simp only [loopLog, List.mem_cons, List.not_mem_nil, or_false] at hl
  rcases hl with rfl | rfl | rfl <;> exact queryLine_premises _ _ _

/-- Two hits on one callstack, as in the loop. The log has three lines. The
query on `g` before `r = 0;` on `[3, 16]` joins the answers of the two lines
on `[16]` and answers exactly 4 and 9: it contains the content of `g` at the
visit of each member, 4 and 9. On `[3, 11]` the query answers exactly 4. -/
theorem same_callstack_join :
    (∃ vs, query true loopLog ⟨21, [3, 16], .before⟩ 1 = some vs ∧
      (∀ u, vs u ↔ u = some (.int 4) ∨ u = some (.int 9)) ∧
      load (trace querySubj ⟨noLocals, queryMem 4 0⟩ 5).2.mem 1 = some (.int 4) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 4 0⟩ 5).2.mem 1) ∧
      load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1 = some (.int 9) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1)) ∧
    (∃ vs, query true loopLog ⟨21, [3, 11], .before⟩ 1 = some vs ∧
      (∀ u, vs u ↔ u = some (.int 4)) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 4 3⟩ 5).2.mem 1)) := by
  have hl₁ : queryLine 11 4 3 ∈ loopLog := List.mem_cons_self
  have hl₂ : queryLine 16 4 0 ∈ loopLog := List.mem_cons_of_mem _ List.mem_cons_self
  have hl₃ : queryLine 16 9 5 ∈ loopLog :=
    List.mem_cons_of_mem _ (List.mem_cons_of_mem _ List.mem_cons_self)
  constructor
  · obtain ⟨vs, hq, -⟩ := query_some (enabled := true) (q := ⟨21, [3, 16], .before⟩)
      (b := 1) hl₂ rfl rfl
    have hvs : some vs = some fun v => (predicates.valueOf (callState 4 0) 1).swept v ∨
        (predicates.valueOf (callState 9 5) 1).swept v := hq.symm.trans rfl
    cases hvs
    refine ⟨_, hq, fun u => ?_, rfl,
      (query_at_line loopLog_premises 16 4 0 .before hl₂).2 true 1 _ hq, rfl,
      (query_at_line loopLog_premises 16 9 5 .before hl₃).2 true 1 _ hq⟩
    rw [swept_int (valueOf_call 4 0).1, swept_int (valueOf_call 9 5).1]
  · obtain ⟨vs, hq, -⟩ := query_some (enabled := true) (q := ⟨21, [3, 11], .before⟩)
      (b := 1) hl₁ rfl rfl
    have hvs : some vs = some (predicates.valueOf (callState 4 3) 1).swept :=
      hq.symm.trans rfl
    cases hvs
    exact ⟨_, hq, swept_int (valueOf_call 4 3).1,
      (query_at_line loopLog_premises 11 4 3 .before hl₁).2 true 1 _ hq⟩

/-! ### An entry for the body of `h`

The call of `h` at site 3 of the call of `f` at site 11 stores an entry for
the body of `h`. It reads nothing, so its key is empty; it writes `r`. Its
inner part has the states on the key only: top at every point, the writes of
the footprint as possible writes, and no updated block. -/

/-- The body of `h` as the cached statement. -/
def calleeSubj : Subject := ⟨queryProg, queryCallee,
  ⟨by decide, ⟨fun f => if f = "f" then 1 else 0, by decide⟩, by decide,
    Or.inl (by decide)⟩⟩

/-- The entry stored by the call of `h` with `x, g, r = 1, 4, 3`. -/
def calleeEntry : CacheEntry predicates where
  subject := calleeSubj
  env := noLocals
  input := callState 4 3
  key := []
  footprint := ⟨[], [2], [2], [2]⟩
  exit := fun o m => o = .completed ∧ load m 2 = some (.int 0)
  violations := fun _ => False
  reached := (· ∈ [20, 21, 22])

/-- The inner part of `calleeEntry`, with the states on the (empty) key
only. -/
def calleeInner : InnerPart predicates :=
  ⟨fun _ _ => True, fun _ => calleeEntry.footprint.writes, fun _ => []⟩

/-- The line of a hit of `h` on the callstack `cs`, with `x = 1` and `g`, `r`
as given at the call. -/
def calleeLine (cs : List Label) (g r : Int) : HitLine predicates :=
  ⟨cs, calleeEntry, calleeInner, callState g r, [0, 1, 2]⟩

private def calleeRun (n : Nat) : List Event × Config FunMem :=
  trace calleeSubj ⟨noLocals, queryMem 4 3⟩ n

private def CalleeTrace (evs : List Event) (c : Config FunMem) : Prop :=
  (∀ e ∈ evs, e = .write 2) ∧
  match c with
  | .run s _ _ _ => s = queryCallee ∨ s = .assign 21 (.var "r") (.const 0) ∨ s = .skip 22
  | .done o m => o = .completed ∧ load m 2 = some (.int 0) ∧ Event.write 2 ∈ evs
  | .fault .. => False
  | _ => True

private instance (evs : List Event) (c : Config FunMem) :
    Decidable (CalleeTrace evs c) := by
  unfold CalleeTrace
  refine @instDecidableAnd _ _ inferInstance ?_
  split <;> infer_instance

private theorem callee_trace : ∀ n : Fin 6, CalleeTrace (calleeRun n).1 (calleeRun n).2 := by
  decide

private theorem callee_at (n : Nat) : CalleeTrace (calleeRun n).1 (calleeRun n).2 := by
  have hs (extra : Nat) : calleeRun (extra + 5) = calleeRun 5 := by
    cases extra <;> rfl
  by_cases hlt : n < 6
  · exact callee_trace ⟨n, hlt⟩
  · have he : n = (n - 5) + 5 := by omega
    rw [he, hs]
    exact callee_trace 5

private theorem callee_prefix {w : FunMem} (hw : calleeEntry.input w)
    {evs : List Event} {c : Config FunMem}
    (h : Prefix calleeSubj ⟨calleeEntry.env, w⟩ evs c) : CalleeTrace evs c := by
  rw [show (⟨calleeEntry.env, w⟩ : State FunMem) = ⟨noLocals, queryMem 4 3⟩ by
    rw [callState_eq hw]; rfl] at h
  obtain ⟨n, hn⟩ := steps_run h
  have ht := callee_at n
  change calleeRun n = (evs, c) at hn
  rw [hn] at ht
  exact ht

/-- The premises of `CacheEntry.query_sound` on the entry of `h`, proved on
its producing execution. The inner part is sound by
`CacheEntry.innerPartSound_of_key`. -/
theorem callee_entry_premises :
    calleeEntry.ProducerSound ∧ calleeEntry.Coverage ∧ calleeEntry.KeyCovers ∧
      calleeEntry.InnerPartSound calleeInner := by
  have hc : calleeEntry.Coverage := by
    intro m hm
    constructor
    · intro evs c he e hmem
      rw [(callee_prefix hm he).1 e hmem]
      exact List.mem_cons_self
    · intro evs o out he b hb
      cases (callee_prefix hm he).1 _ hb
      exact List.mem_cons_self
    · intro evs o out he b hb
      simp only [calleeEntry, List.mem_singleton] at hb
      subst b
      exact (callee_prefix hm he).2.2.2
  refine ⟨⟨?_, ?_, ?_⟩, hc, ⟨fun _ h => h, fun _ hb h => absurd hb h⟩, ?_⟩
  · rintro m hm o out ⟨evs, he⟩
    obtain ⟨-, ho, hval, -⟩ := callee_prefix hm he
    exact ⟨ho, hval⟩
  · intro m hm v hv
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, he⟩ := hv
      exact (callee_prefix hm he).2
    | assertion l =>
      obtain ⟨evs, e, k, env, out, he, -⟩ := hv
      have ht := (callee_prefix hm he).2
      simp only [queryCallee] at ht
      rcases ht with h | h | h <;> cases h
  · rintro m hm l ⟨env, out, evs, s, k, he, rfl⟩
    have ht := (callee_prefix hm he).2
    change s = queryCallee ∨ s = .assign 21 (.var "r") (.const 0) ∨ s = .skip 22 at ht
    change s.label ∈ [20, 21, 22]
    rcases ht with rfl | rfl | rfl <;> decide
  · exact CacheEntry.innerPartSound_of_key _ hc fun w _ q n _ =>
      ⟨(trace calleeEntry.subject ⟨calleeEntry.env, w⟩ n).2.mem, trivial, fun _ _ => rfl⟩

/-- Each line of a call of `h` meets the premises. -/
theorem calleeLine_premises (cs : List Label) (g r : Int) : LinePremises (calleeLine cs g r) :=
  ⟨callee_entry_premises.1, callee_entry_premises.2.1, callee_entry_premises.2.2.1,
    callee_entry_premises.2.2.2, callState_issued g r⟩

/-- Every call state matches the entry of `h`: its key is empty. A member of
the line is before `r = 0;` at step 1 of the body of `h`, with `g` at its
call value. -/
theorem callee_member (g r : Int) :
    calleeEntry.Matches FunMem.allocatorAgreement (queryMem g r) ∧
    AtPoint calleeSubj ⟨noLocals, queryMem g r⟩ ⟨21, [], .before⟩ 1 ∧
    load (trace calleeSubj ⟨noLocals, queryMem g r⟩ 1).2.mem 1 = some (.int g) :=
  ⟨⟨queryMem 4 3, callState_queryMem 4 3, ⟨fun _ hb => absurd hb List.not_mem_nil,
      fun b hb => by simp only [calleeEntry, List.mem_singleton] at hb; subst hb; rfl, rfl⟩⟩,
    ⟨_, _, _, _, rfl, rfl, rfl⟩, rfl⟩

/-- The log of `loopMain` when the first call at site 16 is analysed and its
call of `h` hits the entry of `h`, and the second call at site 16 hits the
entry of `f`. -/
def nestedLog : List (HitLine predicates) :=
  [queryLine 11 4 3, calleeLine [3, 16] 4 0, queryLine 16 9 5]

/-- The lines of `nestedLog` meet the premises. -/
private theorem nestedLog_premises : ∀ line ∈ nestedLog, LinePremises line := by
  intro line hl
  simp only [nestedLog, List.mem_cons, List.not_mem_nil, or_false] at hl
  rcases hl with rfl | rfl | rfl
  · exact queryLine_premises _ _ _
  · exact calleeLine_premises _ _ _
  · exact queryLine_premises _ _ _

/-- Two lines whose callstacks, `[3, 16]` and `[16]`, end the callstack of the
query with different lengths. The line of `h` answers at the point below its
hit, with the empty callstack, and gives 4; the line of `f` answers at the
point with the callstack `[3]` and gives 9. The query on `g` before `r = 0;`
on `[3, 16]` answers exactly 4 and 9, and contains the content of `g` at
the visit of each member. -/
theorem nested_suffix_join :
    (calleeLine [3, 16] 4 0).answer true ⟨21, [], .before⟩ 1 =
      some (predicates.valueOf (callState 4 0) 1).swept ∧
    (queryLine 16 9 5).answer true ⟨21, [3], .before⟩ 1 =
      some (predicates.valueOf (callState 9 5) 1).swept ∧
    ∃ vs, query true nestedLog ⟨21, [3, 16], .before⟩ 1 = some vs ∧
      (∀ u, vs u ↔ u = some (.int 4) ∨ u = some (.int 9)) ∧
      load (trace calleeSubj ⟨noLocals, queryMem 4 0⟩ 1).2.mem 1 = some (.int 4) ∧
      vs (load (trace calleeSubj ⟨noLocals, queryMem 4 0⟩ 1).2.mem 1) ∧
      load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1 = some (.int 9) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1) := by
  have hl₂ : calleeLine [3, 16] 4 0 ∈ nestedLog := List.mem_cons_of_mem _ List.mem_cons_self
  have hl₃ : queryLine 16 9 5 ∈ nestedLog :=
    List.mem_cons_of_mem _ (List.mem_cons_of_mem _ List.mem_cons_self)
  obtain ⟨vs, hq, -⟩ := query_some (enabled := true) (q := ⟨21, [3, 16], .before⟩)
    (b := 1) hl₂ rfl rfl
  have hvs : some vs = some fun v => (predicates.valueOf (callState 4 0) 1).swept v ∨
      (predicates.valueOf (callState 9 5) 1).swept v := hq.symm.trans rfl
  cases hvs
  refine ⟨rfl, rfl, _, hq, fun u => ?_, rfl, ?_, rfl,
    (query_at_line nestedLog_premises 16 9 5 .before hl₃).2 true 1 _ hq⟩
  · rw [swept_int (valueOf_call 4 0).1, swept_int (valueOf_call 9 5).1]
  · obtain ⟨hmatch, hv, -⟩ := callee_member 4 0
    exact (log_sound (q := ⟨21, [3, 16], .before⟩) nestedLog_premises hl₂ rfl
      (callState_queryMem 4 0) hmatch hv).2 true 1 _ hq

/-- A log of three lines that all apply to a query on `[3, 16]`: a hit of
`f` with `g = 9`, a hit of `h` with `g = 4`, and a hit of `f` with `g = 7`.
Each gives a value that the two others do not. -/
def threeLog : List (HitLine predicates) :=
  [queryLine 16 9 5, calleeLine [3, 16] 4 0, queryLine 16 7 5]

/-- The lines of `threeLog` meet the premises. -/
private theorem threeLog_premises : ∀ line ∈ threeLog, LinePremises line := by
  intro line hl
  simp only [threeLog, List.mem_cons, List.not_mem_nil, or_false] at hl
  rcases hl with rfl | rfl | rfl
  · exact queryLine_premises _ _ _
  · exact calleeLine_premises _ _ _
  · exact queryLine_premises _ _ _

/-- The query on `g` before `r = 0;` on `[3, 16]` joins three answers: it
answers exactly 9, 4 and 7, and contains the content of `g` at the visit of
each member. -/
theorem three_lines_join :
    ∃ vs, query true threeLog ⟨21, [3, 16], .before⟩ 1 = some vs ∧
      (∀ u, vs u ↔ u = some (.int 9) ∨ u = some (.int 4) ∨ u = some (.int 7)) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 9 5⟩ 5).2.mem 1) ∧
      vs (load (trace calleeSubj ⟨noLocals, queryMem 4 0⟩ 1).2.mem 1) ∧
      vs (load (trace querySubj ⟨noLocals, queryMem 7 5⟩ 5).2.mem 1) := by
  have hl₁ : queryLine 16 9 5 ∈ threeLog := List.mem_cons_self
  have hl₂ : calleeLine [3, 16] 4 0 ∈ threeLog := List.mem_cons_of_mem _ List.mem_cons_self
  have hl₃ : queryLine 16 7 5 ∈ threeLog :=
    List.mem_cons_of_mem _ (List.mem_cons_of_mem _ List.mem_cons_self)
  obtain ⟨vs, hq, -⟩ := query_some (enabled := true) (q := ⟨21, [3, 16], .before⟩)
    (b := 1) hl₃ rfl rfl
  have hvs : some vs = some fun v => (predicates.valueOf (callState 9 5) 1).swept v ∨
      (predicates.valueOf (callState 4 0) 1).swept v ∨
      (predicates.valueOf (callState 7 5) 1).swept v := hq.symm.trans rfl
  cases hvs
  obtain ⟨hmatch, hv, -⟩ := callee_member 4 0
  refine ⟨_, hq, fun u => ?_,
    (query_at_line threeLog_premises 16 9 5 .before hl₁).2 true 1 _ hq,
    (log_sound (q := ⟨21, [3, 16], .before⟩) threeLog_premises hl₂ rfl
      (callState_queryMem 4 0) hmatch hv).2 true 1 _ hq,
    (query_at_line threeLog_premises 16 7 5 .before hl₃).2 true 1 _ hq⟩
  rw [swept_int (valueOf_call 9 5).1, swept_int (valueOf_call 4 0).1,
    swept_int (valueOf_call 7 5).1]

/-! ## Inner parts with states on the key only

`CacheEntry.innerPartSound_of_key` has two premises: the states cover the
producing visits on the key, and the footprint covers the writes. Coverage
alone is not enough. The rule for updated blocks reads the recorded list:
a block updated on every execution but not listed answers top. -/

/-- The inner part with the state `state` at every point, the writes of the
footprint of `queryEntry` as possible writes and no updated block. -/
def keyOnlyInner (state : QueryPoint → predicates.State) : InnerPart predicates :=
  ⟨state, fun _ => queryEntry.footprint.writes, fun _ => []⟩

/-- Coverage without states that cover the producing visits: with a state
recording only `x = 2` at every point, `queryEntry` meets `Coverage` and the
key-only inner part does not meet `InnerPartSound`, since the producer
visits `r = 0;` with `x = 1`. -/
theorem key_only_needs_states :
    queryEntry.Coverage ∧
      ¬ queryEntry.InnerPartSound (keyOnlyInner fun _ m => load m 0 = some (.int 2)) := by
  refine ⟨query_entry_premises.2.1, fun h => ?_⟩
  obtain ⟨r, hr, hag⟩ := h.state (queryMem 4 3) (callState_queryMem 4 3) beforeWrite 5
    (query_member_visits 4 3).1
  have h0 := hag 0 (List.mem_append_right _ List.mem_cons_self)
  change load r 0 = some (.int 2) at hr
  rw [hr] at h0
  exact absurd h0 (by decide)

/-- The projection of `queryInner` on the key: at each point, the memories
that agree on the key with a memory of the stored state. -/
def keyInner : InnerPart predicates :=
  keyOnlyInner fun q m => ∃ r, queryInner.state q r ∧ AgreeOn queryEntry.key r m

/-- `CacheEntry.innerPartSound_of_key` with both premises: the states of
`keyInner` cover the producing visits on the key, by `query_inner_sound`,
and the footprint covers the writes. -/
theorem key_inner_sound : queryEntry.InnerPartSound keyInner :=
  CacheEntry.innerPartSound_of_key _ query_entry_premises.2.1 fun w hw q n hv => by
    obtain ⟨r, hr, hag⟩ := query_inner_sound.state w hw q n hv
    exact ⟨r, ⟨r, hr, fun _ _ => rfl⟩, fun b hb => hag b (List.mem_append_right _ hb)⟩

/-- The line of a hit of `f` at `site` with the inner part `keyInner`. -/
def keyLine (site : Label) (g r : Int) : HitLine predicates :=
  ⟨[site], queryEntry, keyInner, callState g r, [0, 1, 2]⟩

/-- The rule for updated blocks reads the list. At every producing visit
after `r = 0;`, `r` has been updated, and `keyInner` does not list it: the
query on `r` with the line `keyLine 16 9 5` answers top there, and also
before the write, where the line of `queryInner` answers 5. The line meets
the premises, and the key block `x` answers exactly 1. -/
theorem key_only_answers :
    (∀ w, queryEntry.input w → ∀ n,
      AtPoint queryEntry.subject ⟨queryEntry.env, w⟩ afterWrite n →
        2 ∈ updatedBlocks (trace queryEntry.subject ⟨queryEntry.env, w⟩ n).1) ∧
    keyInner.updated afterWrite = [] ∧
    LinePremises (keyLine 16 9 5) ∧
    query true [keyLine 16 9 5] ⟨21, [3, 16], .after⟩ 2 = some ValueSet.top ∧
    query true [keyLine 16 9 5] ⟨21, [3, 16], .before⟩ 2 = some ValueSet.top ∧
    ∃ vs, query true [keyLine 16 9 5] ⟨21, [3, 16], .before⟩ 0 = some vs ∧
      ∀ u, vs u ↔ u = some (.int 1) := by
  refine ⟨fun w hw n hv => query_inner_sound.updated w hw afterWrite n hv 2 List.mem_cons_self,
    rfl, ⟨query_entry_premises.1, query_entry_premises.2.1, query_entry_premises.2.2,
      key_inner_sound, callState_issued 9 5⟩, rfl, rfl, ?_⟩
  obtain ⟨vs, hq, -⟩ := query_some (enabled := true) (q := ⟨21, [3, 16], .before⟩)
    (b := 0) (line := keyLine 16 9 5) List.mem_cons_self rfl rfl
  refine ⟨vs, hq, fun u => ?_⟩
  have hvs : some vs = some (predicates.valueOf (keyInner.state beforeWrite) 0) :=
    hq.symm.trans rfl
  cases hvs
  constructor
  · rintro ⟨m, ⟨r, hr, hag⟩, rfl⟩
    rw [← hag 0 List.mem_cons_self]
    exact (valueOf_inner.1 _).1 ⟨r, hr, rfl⟩
  · rintro rfl
    exact ⟨queryMem 4 3, ⟨queryMem 4 3, ⟨rfl, rfl, rfl⟩, fun _ _ => rfl⟩, rfl⟩

/-! ## A local of the body

The cached statement is `L40: { int t = 7;  L41: ; }`, with a global `y` in
block 0 that it does not access; `t` is created in block 1. The entry has an
empty key and footprint. The producing call has `y = 1`; the member has
`y = 2` and the same next fresh block, so it matches. The line of the hit log
binds block 0 only. Before `L41`, the query on `t` answers top; the value of
block 1 at the call is no value, which misses the 7 of the visit. -/

def localProg : Program := ⟨[], fun x => if x = "y" then some 0 else none⟩

def localStmt : Stmt := .scope 40 [("t", 7)] (.skip 41)

def localSubj : Subject := ⟨localProg, localStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

/-- The entry stored by a call with `y = 1`. -/
def localEntry : CacheEntry predicates where
  subject := localSubj
  env := noLocals
  input := (· = memOf [.int 1])
  key := []
  footprint := ⟨[], [], [], []⟩
  exit := fun _ _ => True
  violations := fun _ => True
  reached := fun _ => True

/-- The inner part: top at every point, no write, nothing updated. -/
def localInner : InnerPart predicates := ⟨fun _ _ => True, fun _ => [], fun _ => []⟩

/-- The line of a hit at site 7, with `y = 2` at the call. -/
def localLine : HitLine predicates := ⟨[7], localEntry, localInner, (· = memOf [.int 2]), [0]⟩

/-- The names of the example denote its cells: `y` holds 1 for the producer
and 2 for the member, and before `L41` the member's `t` is block 1 and
holds 7. -/
example :
    (evalExpr localProg noLocals (memOf [.int 1]) (.var "y")).2 = .ok (.int 1) ∧
    (evalExpr localProg noLocals (memOf [.int 2]) (.var "y")).2 = .ok (.int 2) ∧
    ∃ k env m, (trace localSubj ⟨noLocals, memOf [.int 2]⟩ 1).2 = .run (.skip 41) k env m ∧
      env "t" = some 1 ∧ (evalExpr localProg env m (.var "t")).2 = .ok (.int 7) :=
  ⟨rfl, rfl, _, _, _, rfl, rfl, rfl⟩

private def localRun (n : Nat) : List Event × Config FunMem :=
  trace localSubj ⟨noLocals, memOf [.int 1]⟩ n

private theorem local_no_access :
    ∀ n : Fin 5, ∀ e ∈ (localRun n).1, e = .scopeEnter 1 ∨ e = .sweep 1 := by
  decide

private theorem local_events (n : Nat) :
    ∀ e ∈ (localRun n).1, e = .scopeEnter 1 ∨ e = .sweep 1 := by
  have hs (extra : Nat) : localRun (extra + 4) = localRun 4 := by
    cases extra <;> rfl
  by_cases hlt : n < 5
  · exact local_no_access ⟨n, hlt⟩
  · have he : n = (n - 4) + 4 := by omega
    rw [he, hs]
    exact local_no_access 4

private theorem local_prefix {w : FunMem} (hw : localEntry.input w)
    {evs : List Event} {c : Config FunMem}
    (h : Prefix localSubj ⟨localEntry.env, w⟩ evs c) :
    ∀ e ∈ evs, e = .scopeEnter 1 ∨ e = .sweep 1 := by
  change w = memOf [.int 1] at hw
  subst hw
  obtain ⟨n, hn⟩ := steps_run h
  change localRun n = (evs, c) at hn
  have h := local_events n
  rw [hn] at h
  exact h

theorem local_premises :
    localEntry.ProducerSound ∧ localEntry.Coverage ∧ localEntry.KeyCovers ∧
      localEntry.InnerPartSound localInner := by
  refine ⟨⟨fun _ _ _ _ _ => trivial, fun _ _ _ _ => trivial, fun _ _ _ _ => trivial⟩,
    fun m hm => ⟨?_, ?_, ?_⟩, ⟨fun _ h => h, fun _ hb _ => absurd hb List.not_mem_nil⟩,
    ⟨?_, ?_, ?_⟩⟩
  · intro evs c he e hmem
    rcases local_prefix hm he e hmem with rfl | rfl <;> trivial
  · intro evs o out he b hb
    rcases local_prefix hm he _ hb with h | h <;> cases h
  · intro _ _ _ _ b hb
    exact absurd hb List.not_mem_nil
  · intro w _ q n _
    exact ⟨(trace localEntry.subject ⟨localEntry.env, w⟩ n).2.mem, trivial, fun _ _ => rfl⟩
  · intro w hw q n _ b hb
    have hs := run_steps localSubj.prog n (Config.entry localSubj.stmt ⟨localEntry.env, w⟩)
    rcases local_prefix hw hs _ hb with h | h <;> cases h
  · intro _ _ _ _ _ b hb
    exact absurd hb List.not_mem_nil

/-- `CacheEntry.query_sound` for the member with `y = 2`, before `L41`. -/
theorem local_at_line :
    localEntry.reached 41 ∧ ∀ enabled b vs,
      query enabled [localLine] ⟨41, [7], .before⟩ b = some vs →
        vs (load (trace localSubj ⟨noLocals, memOf [.int 2]⟩ 1).2.mem b) := by
  obtain ⟨hp, hc, hk, hi⟩ := local_premises
  have one {P : HitLine predicates → Prop} (h : P localLine) :
      ∀ l ∈ [localLine], l.callstack.isSuffixOf [7] → P l := by
    intro l hl _
    rw [List.mem_singleton] at hl
    subst hl
    exact h
  refine CacheEntry.query_sound (log := [localLine]) (line := localLine)
    (q := ⟨41, [7], .before⟩) (a := FunMem.allocatorAgreement) (one hp) (one hc) (one hk)
    (one hi) (one ?_) List.mem_cons_self rfl rfl
    ⟨memOf [.int 1], rfl, fun _ hb => absurd hb List.not_mem_nil,
      fun _ hb => absurd hb List.not_mem_nil, rfl⟩
    ⟨_, _, _, _, rfl, rfl, rfl⟩
  intro m hm b hb
  change m = memOf [.int 2] at hm
  subst hm
  change b ∈ [0] at hb
  rw [List.mem_singleton] at hb
  subst hb
  change 0 < 1
  decide

private theorem applySweeps_none (targets : List Block) : applySweeps targets none = none :=
  (applySweeps_eq_iff _ _).2 fun _ _ h => by cases h

/-- The local `t` answers top before `L41`. Its content at the visit is 7;
the value of its block at the call, with the marks of the sweeps, is no value
and misses it. -/
theorem local_query :
    query true [localLine] ⟨41, [7], .before⟩ 1 = some ValueSet.top ∧
    load (trace localSubj ⟨noLocals, memOf [.int 2]⟩ 1).2.mem 1 = some (.int 7) ∧
    (∀ u, (predicates.valueOf localLine.state 1).swept u ↔ u = none) ∧
    ¬ (predicates.valueOf localLine.state 1).swept
      (load (trace localSubj ⟨noLocals, memOf [.int 2]⟩ 1).2.mem 1) := by
  have hcall : ∀ u, (predicates.valueOf localLine.state 1).swept u ↔ u = none := by
    intro u
    constructor
    · rintro ⟨v, targets, ⟨m, hm, rfl⟩, rfl⟩
      change m = memOf [.int 2] at hm
      subst hm
      exact applySweeps_none targets
    · rintro rfl
      exact ⟨none, [], ⟨memOf [.int 2], rfl, rfl⟩, rfl⟩
  refine ⟨rfl, rfl, hcall, ?_⟩
  rw [hcall]
  exact fun h => nomatch h

/-! ## The marks of the sweeps in the frame rule

A block that no prefix accesses can still change: a sweep marks a pointer it
holds to the swept local. The value at the call misses the visit; the same
value with the marks of the sweeps contains it. -/

theorem frame_needs_sweeps :
    AtPoint sweepSubj futurePointerInput ⟨4, [], .before⟩ 5 ∧
    InFrame sweepSubj futurePointerInput 1 ∧
    load futurePointerInput.mem 1 = some (.ptr 2) ∧
    load (trace sweepSubj futurePointerInput 5).2.mem 1 = some (.escaped 2) ∧
    ValueSet.swept (· = some (.ptr 2)) (load (trace sweepSubj futurePointerInput 5).2.mem 1) := by
  obtain ⟨hframe, -, -, -, hentry, hvisit⟩ := future_pointer_needs_rewrite
  refine ⟨⟨_, _, _, _, rfl, rfl, rfl⟩, hframe, hentry, hvisit, ?_⟩
  exact ⟨some (.ptr 2), [2], rfl, hvisit⟩

/-! ## The end of a statement's execution

In `while (i < 2) { if (i == 0) A: i = 1; else B: i = 2; }`, A and B run on
the same continuation. The completion of B is not a visit after A: the
completion of A ends the execution of A. -/

def branchProg : Program := ⟨[], fun x => if x = "i" then some 0 else none⟩

def branchStmt : Stmt :=
  .loop 30 (.binop .lt (.var "i") (.const 2))
    (.ite 31 (.binop .eq (.var "i") (.const 0))
      (.assign 32 (.var "i") (.const 1)) (.assign 33 (.var "i") (.const 2)))

def branchSubj : Subject := ⟨branchProg, branchStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def branchInput : State FunMem := topState [.int 0]

theorem after_ends_at_completion :
    AtPoint branchSubj branchInput ⟨32, [], .after⟩ 3 ∧
    AtPoint branchSubj branchInput ⟨33, [], .after⟩ 7 ∧
    ¬ AtPoint branchSubj branchInput ⟨32, [], .after⟩ 7 := by
  refine ⟨⟨2, _, _, _, _, _, _, by decide, rfl, rfl, rfl, rfl, by intro i hi hi'; omega⟩,
    ⟨6, _, _, _, _, _, _, by decide, rfl, rfl, rfl, rfl, by intro i hi hi'; omega⟩, ?_⟩
  rintro ⟨n₀, s, k, env₀, m₀, env, m, hlt, h₀, hl, -, -, hin⟩
  have hlab : labelOf? (trace branchSubj branchInput n₀).2 = some 32 := by
    rw [h₀]; exact congrArg some hl
  have hn₀ : n₀ = 2 := by
    have hall : ∀ j : Fin 7, labelOf? (trace branchSubj branchInput j).2 = some 32 →
        j.val = 2 := by decide
    exact hall ⟨n₀, hlt⟩ hlab
  subst hn₀
  have hk : k = (trace branchSubj branchInput 2).2.cont := by rw [h₀]; rfl
  have hout : ¬ (trace branchSubj branchInput 3).2.Inside
      (trace branchSubj branchInput 2).2.cont := by decide
  exact hout (hk ▸ hin 3 (by decide) (by decide))

end Checks
