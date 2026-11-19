import Checks.Sweeps

/-! A non-relational hit that overwrites one block, reads another in a
valid assertion, and retains a different caller frame. -/

namespace Checks

open ReuseModel Memory Domain


/-- A value-domain instance. Away from the key, the stored constraints
must fit below the current next identifier, and stored constraints on
write targets must name live current blocks. -/
theorem valueDom_hit {entry : CacheEntry (valueDom FunMem)}
    {cur : (valueDom FunMem).State} (hs : entry.Sound FunMem.allocatorAgreement)
    (hsub : ∀ m, (valueDom FunMem).γ ((valueDom FunMem).filter entry.key cur) m →
      (valueDom FunMem).γ ((valueDom FunMem).filter entry.key entry.input) m)
    (hfit : ∀ m, (valueDom FunMem).γ cur m → ∀ (p : Block × List Value), List.Mem p entry.input → p.1 ∉ entry.key → p.1 < m.next)
    (hlive : ∀ m, (valueDom FunMem).γ cur m → ∀ (p : Block × List Value), List.Mem p entry.input → p.1 ∉ entry.key →
      p.1 ∈ entry.footprint.writes → Live m p.1)
    (hframe : ∀ m, (valueDom FunMem).γ cur m → entry.NoFrameRewrite m) :
    ∀ m, (valueDom FunMem).γ cur m → entry.HitObservations cur m := by
  have hex := (filterExact_of_relateSound FunMem.combinable valueDom_relateSound)
    entry.key entry.input (valueDom_closed _ _) hs.nonempty
  refine CacheEntry.hit hs (valueDom_filterSound _ _) hex hsub ?_
    (fun _ => valueDom_reuseSound _ _ _) hframe
  intro m hm
  rintro ⟨w, hw, hkey⟩
  let importCell (b : Block) : Prop := b ∉ entry.key ∧ b ∈ entry.input.map Prod.fst
  let choice (b : Block) := if b ∉ entry.key ∧ b ∈ entry.input.map Prod.fst
    then w.cells b else m.cells b
  have imported {b : Block} (h : importCell b) :
      ∃ p : Block × List Value, List.Mem p entry.input ∧ p.1 = b :=
    List.mem_map.mp h.2
  let replay : FunMem := ⟨choice, m.next, by
    intro b hb
    by_cases hi : importCell b
    · obtain ⟨p, hp, rfl⟩ := imported hi
      exact False.elim (Nat.not_lt_of_ge hb (hfit m hm p hp hi.1))
    · change (if b ∉ entry.key ∧ b ∈ entry.input.map Prod.fst
        then w.cells b else m.cells b) = none
      rw [if_neg hi, m.fresh b hb]⟩
  have cells (b : Block) : load replay b =
      (if b ∉ entry.key ∧ b ∈ entry.input.map Prod.fst then w.cells b else m.cells b) := rfl
  refine ⟨replay, ?_, ⟨?_, ?_, rfl⟩⟩
  · intro p hp
    obtain ⟨v, hv, hval⟩ := hw p hp
    refine ⟨v, hv, ?_⟩
    rw [cells]
    by_cases hk : p.1 ∈ entry.key
    · rw [if_neg (fun h => h.1 hk)]
      exact (hkey p.1 hk).trans hval
    · rw [if_pos ⟨hk, List.mem_map.mpr ⟨p, hp, rfl⟩⟩]
      exact hval
  · intro b hb
    rw [cells, if_neg (fun h => h.1 hb)]
    rfl
  · intro b hb
    rw [cells]
    split
    · rename_i hi
      obtain ⟨p, hp, rfl⟩ := imported hi
      obtain ⟨v, -, hval⟩ := hw p hp
      exact (congrArg Option.isSome hval).trans (hlive m hm p hp hi.1 hb).symm
    · rfl

def hitStmt : Stmt :=
  .seq 1 (.assert 2 (.var "p")) (.assign 3 (.var "x") (.const 7))

def hitSubject : Subject := ⟨loadProg, hitStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def hitEntry : CacheEntry (valueDom FunMem) where
  subject := hitSubject
  env := noLocals
  input := [(0, [.int 3]), (1, [.int 1]), (2, [.int 4])]
  key := [1]
  footprint := ⟨[1], [0], [0], [0]⟩
  exit := fun o => if o = .completed then [(0, [.int 7]), (2, [.int 4])] else [(0, [])]
  violations := fun _ => False
  reached := (· ∈ [1, 2, 3])

def hitCurrent : (valueDom FunMem).State :=
  [(0, [.int 5]), (1, [.int 1]), (2, [.int 9])]

def hitProducer : FunMem := memOf [.int 3, .int 1, .int 4]
def hitMember : FunMem := memOf [.int 5, .int 1, .int 9]
def hitOutput : FunMem := (run loadProg 5 (Config.entry hitStmt ⟨noLocals, hitMember⟩)).2.mem

private theorem value_fact {S : (valueDom FunMem).State} {m : FunMem} {b : Block} {v : Value}
    (hm : (valueDom FunMem).γ S m) (hp : List.Mem (b, [v]) S) : load m b = some v := by
  obtain ⟨v', hv, hl⟩ := hm (b, [v]) hp
  rw [List.mem_singleton] at hv
  exact hv ▸ hl

private def memberTrace (m : FunMem) (evs : List Event) (c : Config FunMem) : Prop :=
  (∀ e ∈ evs, e = .read 1 ∨ e = .write 0) ∧
  match c with
  | .run (.assert l e) _ env w =>
    l ∈ [1, 2, 3] ∧ assertionHolds loadProg env w e = true
  | .run s _ _ _ => s.label ∈ [1, 2, 3]
  | .done o out => o = .completed ∧ load out 0 = some (.int 7) ∧
      load out 2 = load m 2 ∧ Event.write 0 ∈ evs
  | .fault .. => False
  | _ => True

private theorem member_trace {m : FunMem} {evs : List Event} {c : Config FunMem}
    {v : Value} (hx : load m 0 = some v) (hp : load m 1 = some (.int 1))
    (h : Prefix hitSubject ⟨noLocals, m⟩ evs c) : memberTrace m evs c := by
  obtain ⟨n, hn⟩ := steps_run h
  change run loadProg n (Config.entry hitStmt ⟨noLocals, m⟩) = (evs, c) at hn
  have hs : (store m 0 (.int 7)).isSome = true := by
    rw [store_ok_iff, hx]
    rfl
  cases hstore : store m 0 (.int 7) with
  | none => rw [hstore] at hs; contradiction
  | some out =>
    have h₀ := load_store_same hstore
    have h₂ := load_store_other hstore (by decide : (2 : Block) ≠ 0)
    have assign : execAssign loadProg noLocals m (.var "x") (.const 7) =
        ([.write 0], .ok out) := by
      simp [execAssign, evalExpr, evalLExpr, resolve, noLocals, loadProg, hstore]
    have readTag : evalExpr loadProg noLocals m (.var "p") =
        ([.read 1], .ok (.int 1)) := by
      change ([Event.read 1], loadValue m 1) = _
      simp [loadValue, hp]
    have finished (n : Nat) :
        run loadProg n (.done .completed out) = ([], .done .completed out) := by
      cases n <;> rfl
    rcases n with _ | _ | _ | _ | _ | n
    all_goals
      simp only [run, Config.entry, hitStmt, step, stepStmt, stepNext, assign,
        readTag, finished, List.nil_append, List.append_nil] at hn
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn
      simp [memberTrace, Stmt.label, assertionHolds, readTag, Value.truth, h₀, h₂]

private theorem hit_producer_mem : (valueDom FunMem).γ hitEntry.input hitProducer := by
  intro p hp
  simp only [hitEntry, List.mem_cons, List.not_mem_nil, or_false] at hp
  rcases hp with rfl | rfl | rfl <;> exact ⟨_, List.mem_cons_self, rfl⟩

private theorem hit_member_mem : (valueDom FunMem).γ hitCurrent hitMember := by
  intro p hp
  simp [hitCurrent] at hp
  rcases hp with rfl | rfl | rfl <;> exact ⟨_, List.mem_cons_self, rfl⟩

private theorem hit_sound : hitEntry.Sound FunMem.allocatorAgreement := by
  have traced {m : FunMem} (hm : (valueDom FunMem).γ hitEntry.input m) {evs : List Event}
      {c : Config FunMem} (h : Prefix hitSubject ⟨noLocals, m⟩ evs c) :=
    member_trace (value_fact hm (b := 0) (v := .int 3) (List.Mem.head _))
      (value_fact hm (List.Mem.tail _ (List.Mem.head _))) h
  refine hitEntry.sound_of_producer ⟨hitProducer, hit_producer_mem⟩
    ⟨?_, ?_, ?_⟩ ?_ ⟨fun _ h => h, fun _ h hn => (hn h).elim⟩
  · rintro m hm o out ⟨evs, he⟩
    obtain ⟨rfl, h₀, h₂, -⟩ := (traced hm he).2
    intro p hp
    change p ∈ ([(0, [.int 7]), (2, [.int 4])] : List (Block × List Value)) at hp
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl
    · exact ⟨_, List.mem_cons_self, h₀⟩
    · exact ⟨_, List.mem_cons_self, h₂.trans (value_fact hm (List.Mem.tail _ (List.Mem.tail _ (List.Mem.head _))))⟩
  · intro m hm v hv
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, he⟩ := hv
      exact (traced hm he).2
    | assertion l =>
      obtain ⟨evs, e, k, env, out, he, hf⟩ := hv
      change assertionHolds loadProg env out e = false at hf
      rw [(traced hm he).2.2] at hf
      contradiction
  · rintro m hm l ⟨env, out, evs, s, k, he, rfl⟩
    have ht := (traced hm he).2
    cases s <;> first | exact ht | exact ht.1
  · intro m hm
    constructor
    · intro evs c he e hmem
      rcases (traced hm he).1 e hmem with rfl | rfl <;> exact List.mem_cons_self
    · intro evs o out he b hb
      rcases (traced hm he).1 _ hb with ha | ha
      · contradiction
      · cases ha; exact List.mem_cons_self
    · intro evs o out he b hb
      have hb' : b = 0 := List.mem_singleton.mp hb
      subst b
      exact (traced hm he).2.2.2.2

private theorem no_sweep_of_trace {evs : List Event}
    (h : ∀ e ∈ evs, e = .read 1 ∨ e = .write 0) : sweepTargets evs = [] := by
  induction evs with
  | nil => rfl
  | cons e es ih =>
    have he := h e List.mem_cons_self
    have hes := ih (fun e he => h e (List.mem_cons_of_mem _ he))
    rcases he with rfl | rfl <;> exact hes

private theorem hit_fixture_observations :
    ∀ m, (valueDom FunMem).γ hitCurrent m → hitEntry.HitObservations hitCurrent m := by
  refine valueDom_hit hit_sound (fun _ h => h) ?_ ?_ ?_
  · intro m hm p hp _
    have hm₂ : Live m 2 := by
      unfold Live
      rw [value_fact hm (b := 2) (v := .int 9) (List.Mem.tail _ (List.Mem.tail _ (List.Mem.head _)))]
      rfl
    have hi : 2 < m.next := hm₂.issued
    change p ∈ ([(0, [.int 3]), (1, [.int 1]), (2, [.int 4])] :
      List (Block × List Value)) at hp
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl | rfl <;>
      exact Nat.lt_of_le_of_lt (by decide) hi
  · intro m hm p _ _ hw
    have hb : p.1 = 0 := List.mem_singleton.mp hw
    unfold Live
    rw [hb, value_fact hm (b := 0) (v := .int 5) (List.Mem.head _)]
    rfl
  · intro m hm evs o out he b _ target ht
    have ht' := no_sweep_of_trace (member_trace
      (value_fact hm (b := 0) (v := .int 5) (List.Mem.head _))
      (value_fact hm (List.Mem.tail _ (List.Mem.head _))) he).1
    rw [ht'] at ht
    exact False.elim (List.not_mem_nil ht)

/-- The member differs from every stored input, has a normal exit, and
observes a valid assertion. Its output preserves the distinct frame, and
the unmodified stored output state excludes the member's output. -/
theorem value_hit_distinct_member :
    (valueDom FunMem).γ hitCurrent hitMember ∧
    ¬ (valueDom FunMem).γ hitEntry.input hitMember ∧
    hitEntry.HitObservations hitCurrent hitMember ∧
    Exit hitSubject ⟨noLocals, hitMember⟩ .completed hitOutput ∧
    (valueDom FunMem).γ ((valueDom FunMem).reuse [0] hitCurrent (hitEntry.exit .completed)) hitOutput ∧
    ¬ (valueDom FunMem).γ (hitEntry.exit .completed) hitOutput ∧
    load hitOutput 0 = some (.int 7) ∧ load hitOutput 2 = some (.int 9) ∧
    hitEntry.reached 2 ∧ assertionHolds loadProg noLocals hitMember (.var "p") = true := by
  have ho := hit_fixture_observations hitMember hit_member_mem
  have he : Exit hitSubject ⟨noLocals, hitMember⟩ .completed hitOutput :=
    ⟨[.read 1, .write 0], steps_iff_run.mpr ⟨5, rfl⟩⟩
  have hv : Prefix hitSubject ⟨noLocals, hitMember⟩ []
      (.run (.assert 2 (.var "p")) (.seq (.assign 3 (.var "x") (.const 7)) .stop)
        noLocals hitMember) := steps_iff_run.mpr ⟨1, rfl⟩
  have hr : Reach hitSubject ⟨noLocals, hitMember⟩ 2 :=
    ⟨noLocals, hitMember, [], _, _, hv, rfl⟩
  refine ⟨hit_member_mem, ?_, ho, he, (ho.exit _ _ he).1, ?_, rfl, rfl,
    ho.reach 2 hr, ho.valid 2 _ _ _ _ _ id hv⟩
  · intro hm
    have hf := value_fact hm (b := 2) (v := .int 4) (List.Mem.tail _ (List.Mem.tail _ (List.Mem.head _)))
    contradiction
  · intro hm
    have hf := value_fact hm (b := 2) (v := .int 4) (List.Mem.tail _ (List.Mem.head _))
    contradiction


/-- The larger key excludes this member, although its concrete hit
observations still satisfy the contract. -/
theorem hit_observations_do_not_imply_match :
    let larger := { hitEntry with key := [1, 2] }
    larger.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).γ hitCurrent hitMember ∧
    ¬ larger.Matches FunMem.allocatorAgreement hitMember ∧
    larger.HitObservations hitCurrent hitMember := by
  dsimp only
  have observations := value_hit_distinct_member.2.2.1
  refine ⟨⟨hit_sound.nonempty, ?_⟩, hit_member_mem, ?_,
    ⟨observations.exit, observations.reach, observations.safety, observations.valid⟩⟩
  · rintro m ⟨w, hw, hr⟩
    have contents : AgreeOn hitEntry.key w m := by
      intro b hb
      have hb' : b = 1 := List.mem_singleton.mp hb
      subst b
      exact hr.contents 1 (by decide)
    obtain ⟨c, o⟩ := hit_sound.matched m ⟨w, hw, ⟨contents, hr.live, hr.allocator⟩⟩
    exact ⟨⟨c.accesses, c.exitWrites, c.sure⟩, ⟨o.exit, o.safety, o.reach⟩⟩
  · rintro ⟨w, hw, hr⟩
    have stored := value_fact hw (b := 2) (v := .int 4)
      (List.Mem.tail _ (List.Mem.tail _ (List.Mem.head _)))
    have agrees := hr.contents 2 (by decide)
    rw [stored] at agrees
    contradiction

/-- A live stored overwrite destination may be absent from the current
memory even when the filtered states agree and the allocator is unchanged.
Skipping the liveness check would miss the fault at the store. -/
theorem hit_needs_write_liveness :
    let dead := release hitMember 0
    let cur : (valueDom FunMem).State := [(1, [.int 1]), (2, [.int 9])]
    hitEntry.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).filter hitEntry.key cur =
      (valueDom FunMem).filter hitEntry.key hitEntry.input ∧
    (valueDom FunMem).γ cur dead ∧
    AgreeOn hitEntry.key dead hitProducer ∧
    FunMem.allocatorAgreement.rel hitProducer dead ∧
    ¬ hitEntry.ReplayCompatible FunMem.allocatorAgreement cur ∧
    (∀ m, (valueDom FunMem).γ cur m → hitEntry.NoFrameRewrite m) ∧
    AlarmRaised hitSubject ⟨noLocals, dead⟩ 3 .invalidAccess ∧
    ¬ hitEntry.HitObservations cur dead := by
  dsimp only
  let dead : FunMem := release hitMember 0
  have hcur : (valueDom FunMem).γ [(1, [.int 1]), (2, [.int 9])] dead := by
    intro p hp
    simp at hp
    rcases hp with rfl | rfl <;> exact ⟨_, List.mem_cons_self, rfl⟩
  have hkey : AgreeOn hitEntry.key dead hitProducer := by
    intro b hb
    have he : b = 1 := List.mem_singleton.mp hb
    subst b
    rfl
  have hfault : AlarmRaised hitSubject ⟨noLocals, dead⟩ 3 .invalidAccess :=
    ⟨[.read 1, .write 0], dead, steps_iff_run.mpr ⟨4, rfl⟩⟩
  refine ⟨hit_sound, rfl, hcur, hkey, rfl, ?_, ?_, hfault, ?_⟩
  · intro ha
    obtain ⟨w, hw, hrel⟩ := ha dead hcur ⟨hitProducer, hit_producer_mem, hkey⟩
    have hl := hrel.live 0 (show 0 ∈ [0] from List.mem_cons_self)
    rw [value_fact hw (v := .int 3) (List.Mem.head _)] at hl
    contradiction
  · intro m hm evs o out hp b _ target ht
    cases hx : load m 0 with
    | some v =>
      have htag := value_fact hm (b := 1) (v := .int 1) (List.Mem.head _)
      rw [no_sweep_of_trace (member_trace hx htag hp).1] at ht
      exact False.elim (List.not_mem_nil ht)
    | none =>
      obtain ⟨n, hn⟩ := steps_run hp
      change run loadProg n (Config.entry hitStmt ⟨noLocals, m⟩) =
        (evs, .done o out) at hn
      have hs : store m 0 (.int 7) = none := by
        have hnone := store_ok_iff (m := m) (b := 0) (v := .int 7)
        rw [hx] at hnone
        cases hv : store m 0 (.int 7) <;> simp_all
      have assign : execAssign loadProg noLocals m (.var "x") (.const 7) =
          ([.write 0], .error .invalidAccess) := by
        simp [execAssign, evalExpr, evalLExpr, resolve, noLocals, loadProg, hs]
      have failed (n : Nat) :
          run loadProg n (.fault 3 .invalidAccess m) = ([], .fault 3 .invalidAccess m) := by
        cases n <;> rfl
      rcases n with _ | _ | _ | _ | n <;>
        simp only [run, Config.entry, hitStmt, step, stepStmt, stepNext, assign, failed] at hn <;>
        cases congrArg Prod.snd hn
  · intro ho
    exact ho.safety (.alarm 3 .invalidAccess) hfault

/-- With live write targets and equal filtered input, a stored constraint
can still require an identifier the current allocator has not issued. -/
theorem hit_needs_allocator_agreement :
    let short := memOf [.int 5, .int 1]
    let cur : (valueDom FunMem).State := [(0, [.int 5]), (1, [.int 1])]
    hitEntry.Sound FunMem.allocatorAgreement ∧
    (valueDom FunMem).filter hitEntry.key cur =
      (valueDom FunMem).filter hitEntry.key hitEntry.input ∧
    (valueDom FunMem).γ cur short ∧
    AgreeOn hitEntry.key short hitProducer ∧
    (∀ b ∈ hitEntry.footprint.writes, (load hitProducer b).isSome = (load short b).isSome) ∧
    hitEntry.NoFrameRewrite short ∧ ¬ hitEntry.ReplayCompatible FunMem.allocatorAgreement cur := by
  dsimp only
  let short := memOf [.int 5, .int 1]
  have hcur : (valueDom FunMem).γ [(0, [.int 5]), (1, [.int 1])] short := by
    intro p hp
    simp at hp
    rcases hp with rfl | rfl <;> exact ⟨_, List.mem_cons_self, rfl⟩
  have hkey : AgreeOn hitEntry.key short hitProducer := by
    intro b hb
    have he : b = 1 := List.mem_singleton.mp hb
    subst b
    rfl
  refine ⟨hit_sound, rfl, hcur, hkey, ?_, ?_, ?_⟩
  · intro b hb
    have he : b = 0 := List.mem_singleton.mp hb
    subst b
    rfl
  · intro evs o out he b _ target ht
    have hs := no_sweep_of_trace (member_trace
      (m := short) (v := .int 5) rfl rfl he).1
    rw [hs] at ht
    exact False.elim (List.not_mem_nil ht)
  · intro ha
    obtain ⟨w, hw, hr⟩ := ha short hcur ⟨hitProducer, hit_producer_mem, hkey⟩
    have hn : w.next = 2 := hr.allocator
    have hl := value_fact hw (b := 2) (v := .int 4)
      (List.Mem.tail _ (List.Mem.tail _ (List.Mem.head _)))
    have he := w.fresh 2 (Nat.le_of_eq hn)
    change w.cells 2 = some (.int 4) at hl
    rw [he] at hl
    contradiction

-- Predicates with exact projection and exact overlay, for counterexamples
-- where the outcome or the exact frame matters.
def projectedPredicates : Domain FunMem where
  State := FunMem → Prop
  γ s := s
  filter K s m := ∃ w, s w ∧ AgreeOn K m w
  relate _ _ := none
  reuse W cur out m := ∃ w c, cur c ∧ out w ∧ AgreeOn W m w ∧ AgreeOff W m c

private theorem projectedPredicates_reuse : projectedPredicates.ReuseSound :=
  fun _ _ _ c w _ hc hw hon hoff => ⟨w, c, hc, hw, hon, hoff⟩

private def allocatorStmt : Stmt :=
  .scope 1 [("local", 9)] (.ret 2 (some (.addr "local")))

private def allocatorSubject : Subject := ⟨loadProg, allocatorStmt,
  ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def allocatorEntry : CacheEntry projectedPredicates where
  subject := allocatorSubject
  env := noLocals
  input := (· = hitProducer)
  key := []
  footprint := ⟨[], [], [], []⟩
  exit := fun o _ => o = .returned (some (.escaped 3))
  violations := fun _ => False
  reached := (· ∈ [1, 2])

def shortState : State FunMem := ⟨noLocals, memOf [.int 5, .int 1]⟩
def allocCur : projectedPredicates.State := (· = shortState.mem)

private def AllocatorTrace (evs : List Event) (c : Config FunMem) : Prop :=
  (∀ e ∈ evs, e = .scopeEnter 3 ∨ e = .sweep 3) ∧
  match c with
  | .run (.assert ..) _ _ _ | .fault .. => False
  | .run s _ _ _ => s.label ∈ [1, 2]
  | .done o _ => o = .returned (some (.escaped 3))
  | _ => True

private instance {evs : List Event} {c : Config FunMem} :
    Decidable (AllocatorTrace evs c) := by
  unfold AllocatorTrace
  refine @instDecidableAnd _ _ inferInstance ?_
  split <;> infer_instance

private theorem allocator_trace {evs : List Event} {c : Config FunMem}
    (h : Prefix allocatorSubject ⟨noLocals, hitProducer⟩ evs c) :
    AllocatorTrace evs c := by
  let atFuel (n : Nat) :=
    run loadProg n (Config.entry allocatorStmt ⟨noLocals, hitProducer⟩)
  obtain ⟨n, hn⟩ := steps_run h
  change atFuel n = (evs, c) at hn
  have small : ∀ i : Fin 5, AllocatorTrace (atFuel i).1 (atFuel i).2 := by decide
  have stable (k : Nat) : atFuel (k + 4) = atFuel 4 := by cases k <;> rfl
  have picked : ∃ i : Fin 5, atFuel i = (evs, c) := by
    by_cases hb : n < 5
    · exact ⟨⟨n, hb⟩, hn⟩
    · have he : n = (n - 4) + 4 := by omega
      rw [he, stable] at hn
      exact ⟨4, hn⟩
  obtain ⟨i, hi⟩ := picked
  simpa only [hi] using small i

private theorem allocator_entry_sound : allocatorEntry.Sound FunMem.allocatorAgreement := by
  refine allocatorEntry.sound_of_producer ⟨hitProducer, rfl⟩
    ⟨?_, ?_, ?_⟩ ?_ ⟨fun _ h => h, fun _ h _ => h⟩
  · rintro m (rfl : m = hitProducer) o out ⟨evs, h⟩
    exact (allocator_trace h).2
  · rintro m (rfl : m = hitProducer) v hv
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, he⟩ := hv
      exact (allocator_trace he).2
    | assertion l =>
      obtain ⟨evs, e, k, env, out, he, _⟩ := hv
      exact (allocator_trace he).2
  · rintro m (rfl : m = hitProducer) l ⟨env, out, evs, s, k, he, rfl⟩
    have ht := (allocator_trace he).2
    cases s <;> first | exact ht | contradiction
  · rintro m (rfl : m = hitProducer)
    constructor
    · intro evs c hp e he
      rcases (allocator_trace hp).1 e he with rfl | rfl <;> trivial
    · intro evs o out hp b hb
      rcases (allocator_trace hp).1 _ hb with h | h <;> contradiction
    · intro evs o out hp b hb
      contradiction

/-- Without allocator agreement, a scope can return a different escaped
identifier. All projected-hit hypotheses other than replay compatibility
hold, but the stored exit for the actual outcome is empty. -/
theorem allocator_mismatch_loses_exit :
    allocatorEntry.Sound FunMem.allocatorAgreement ∧
    projectedPredicates.FilterSound ∧ projectedPredicates.ExactOn allocatorEntry.key allocatorEntry.input ∧
    (∀ m, projectedPredicates.γ (projectedPredicates.filter allocatorEntry.key allocCur) m →
      projectedPredicates.γ (projectedPredicates.filter allocatorEntry.key allocatorEntry.input) m) ∧
    projectedPredicates.ReuseSound ∧
    (∀ m, projectedPredicates.γ allocCur m → allocatorEntry.NoFrameRewrite m) ∧
    ¬ allocatorEntry.ReplayCompatible FunMem.allocatorAgreement allocCur ∧
    ¬ allocatorEntry.HitObservations allocCur shortState.mem := by
  have hkey (m w : FunMem) : AgreeOn allocatorEntry.key m w := by
    intro b hb
    contradiction
  refine ⟨allocator_entry_sound, fun _ _ m hm => ⟨m, hm, fun _ _ => rfl⟩,
    fun _ h => h, fun m _ => ⟨hitProducer, rfl, hkey m hitProducer⟩,
    projectedPredicates_reuse, ?_, ?_, ?_⟩
  · rintro m (rfl : m = shortState.mem) _ _ _ _ b _ target _ he
    rcases b with _ | _ | b
    · change some (Value.int 5) = some (Value.ptr target) at he
      cases Option.some.inj he
    · change some (Value.int 1) = some (Value.ptr target) at he
      cases Option.some.inj he
    · have hf : load shortState.mem (b + 2) = none :=
        shortState.mem.fresh _ (by change 2 ≤ b + 2; omega)
      rw [hf] at he
      contradiction
  · intro ha
    obtain ⟨_, (rfl : _ = hitProducer), hag⟩ :=
      ha shortState.mem rfl ⟨hitProducer, rfl, hkey _ _⟩
    exact (by decide : ¬ 3 = 2) hag.allocator
  · intro ho
    let out := (run loadProg 4 (Config.entry allocatorStmt shortState)).2.mem
    have he : Exit allocatorSubject shortState (.returned (some (.escaped 2))) out :=
      ⟨[.scopeEnter 2, .sweep 2], steps_iff_run.mpr ⟨4, rfl⟩⟩
    obtain ⟨w, c, -, hn, -, -⟩ := (ho.exit _ _ he).1
    change Outcome.returned (some (.escaped 2)) = .returned (some (.escaped 3)) at hn
    contradiction

def projectedSweep : CacheEntry projectedPredicates where
  subject := sweepEntry.subject
  env := sweepEntry.env
  input := sweepEntry.input
  key := sweepEntry.key
  footprint := sweepEntry.footprint
  exit := sweepEntry.exit
  violations := sweepEntry.violations
  reached := sweepEntry.reached

def sweepCur : projectedPredicates.State := (· = futurePointerInput.mem)

/-- A frame holder can change on a matching exit. All projected-hit
hypotheses other than no-rewrite hold. Even the reuse state with an exact
overlay excludes this output, which requires a rewritten frame. -/
theorem hit_needs_no_frame_rewrite :
    projectedSweep.Sound FunMem.allocatorAgreement ∧ projectedPredicates.FilterSound ∧
    projectedPredicates.ExactOn projectedSweep.key projectedSweep.input ∧
    (∀ m, projectedPredicates.γ (projectedPredicates.filter projectedSweep.key sweepCur) m →
      projectedPredicates.γ (projectedPredicates.filter projectedSweep.key projectedSweep.input) m) ∧
    projectedSweep.ReplayCompatible FunMem.allocatorAgreement sweepCur ∧
    projectedPredicates.ReuseSound ∧ ¬ projectedSweep.NoFrameRewrite futurePointerInput.mem ∧
    ¬ projectedSweep.HitObservations sweepCur futurePointerInput.mem := by
  obtain ⟨hs, hm, -, hW, -, -, he, -, hin, hout⟩ := matching_frame_holder_rewritten
  have hb : 1 ∉ projectedSweep.footprint.exitWrites := by
    change 1 ∉ sweepEntry.footprint.exitWrites
    rw [hW]
    decide
  have sound : projectedSweep.Sound FunMem.allocatorAgreement := by
    refine ⟨hs.nonempty, fun m h => ?_⟩
    obtain ⟨c, o⟩ := hs.matched m h
    exact ⟨⟨c.accesses, c.exitWrites, c.sure⟩, ⟨o.exit, o.safety, o.reach⟩⟩
  refine ⟨sound, fun _ _ m h => ⟨m, h, fun _ _ => rfl⟩, fun _ h => h,
    ?_, ?_, projectedPredicates_reuse, ?_, ?_⟩
  · intro m h
    obtain ⟨_, (rfl : _ = futurePointerInput.mem), hag⟩ := h
    obtain ⟨w, hw, hrel⟩ := hm
    exact ⟨w, hw, hag.trans hrel.contents.symm⟩
  · rintro m (rfl : m = futurePointerInput.mem) _
    exact hm
  · intro hf
    have hp : Prefix sweepSubj futurePointerInput (sweepRun futurePointerInput 7).1
        (.done .completed (sweepRun futurePointerInput 7).2.mem) := run_steps _ 7 _
    exact hf _ _ _ hp 1 hb 2 (by decide) hin
  · intro hh
    obtain ⟨w, _, (rfl : _ = futurePointerInput.mem), _, _, hoff⟩ := (hh.exit _ _ he).1
    have h := hoff 1 hb
    rw [hin, hout] at h
    contradiction

/-- A previously released binding stays absent. The initially unissued
block is live in the scope and absent again after the sweep. -/
theorem hit_frame_absent_bindings :
    let σ : State FunMem := ⟨noLocals, release sweepInput.mem 1⟩
    load σ.mem 1 = none ∧ load σ.mem 2 = none ∧
    load (sweepRun σ 2).2.mem 2 = some (.int 9) ∧
    load (sweepRun σ 7).2.mem 1 = none ∧ load (sweepRun σ 7).2.mem 2 = none := by
  dsimp only
  let σ : State FunMem := ⟨noLocals, release sweepInput.mem 1⟩
  have hp : Prefix sweepSubj σ (sweepRun σ 7).1
      (.done .completed (sweepRun σ 7).2.mem) := run_steps _ 7 _
  exact ⟨rfl, rfl, rfl, exit_preserves_absence rfl hp, exit_preserves_absence rfl hp⟩

end Checks
