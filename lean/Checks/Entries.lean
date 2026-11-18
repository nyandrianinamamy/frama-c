import ReuseModel.Entry
import Checks.Examples

/-!
# Entries with an overwrite and with a read before it

Blocks 0, 1 and 2 are the destination, the pointer and its target. A broken
footprint for a return leaves out block 2, even though the producer's
observations are sound for its own input.
-/

namespace Checks

open ReuseModel Memory

def loadProg : Program where
  funs := []
  globals := fun x => if x = "x" then some 0 else if x = "p" then some 1 else none

private def loadP : Expr := .deref (.var "p")
private def assignLoad : Stmt := .assign 1 (.var "x") loadP

def assignSubject : Subject :=
  ⟨loadProg, assignLoad, ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def noLocals : Env := fun _ => none

def loadInput (x : Int) (live : Bool) : FunMem :=
  let m := memOf [.int x, .ptr 2, .int 7]
  if live then m else release m 2

def loadOut (x : Int) : FunMem :=
  (store (loadInput x true) 0 (.int 7)).getD FunMem.empty

/-- An abstract state in the fixtures names a set of memories directly. -/
def predicates : Domain FunMem where
  State := FunMem → Prop
  γ s := s
  filter _ _ := fun _ => True
  relate _ _ := some []
  reuse _ _ _ := fun _ => True

def loadReads : List Event := [.read 1, .read 2]
private def loadWrites : List Event := loadReads ++ [.write 0]

private theorem assign_prefixes {live : Bool} {evs : List Event}
    {c : Config FunMem} (h : Prefix assignSubject ⟨noLocals, loadInput 0 live⟩ evs c) :
    (evs = [] ∧ c = .run assignLoad .stop noLocals (loadInput 0 live)) ∨
    (live = false ∧ evs = loadReads ∧ c = .fault 1 .invalidAccess (loadInput 0 false)) ∨
    (live = true ∧ evs = loadWrites ∧ (c = .next .stop noLocals (loadOut 0) ∨ c = .done .completed (loadOut 0))) := by
  obtain ⟨n, hn⟩ := steps_run h
  change run loadProg n (.run assignLoad .stop noLocals (loadInput 0 live)) = _ at hn
  cases n with
  | zero =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn
    exact Or.inl ⟨rfl, rfl⟩
  | succ n =>
    cases live with
    | false =>
      have hs : step loadProg (.run assignLoad .stop noLocals (loadInput 0 false)) =
          some (loadReads, .fault 1 .invalidAccess (loadInput 0 false)) := rfl
      rw [run, hs] at hn
      cases n <;> obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn <;>
        exact Or.inr (Or.inl ⟨rfl, rfl, rfl⟩)
    | true =>
      have hs : step loadProg (.run assignLoad .stop noLocals (loadInput 0 true)) =
          some (loadWrites, .next .stop noLocals (loadOut 0)) := rfl
      rw [run, hs] at hn
      cases n with
      | zero =>
        obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn
        exact Or.inr (Or.inr ⟨rfl, rfl, Or.inl rfl⟩)
      | succ n =>
        cases n <;> obtain ⟨rfl, rfl⟩ := Prod.mk.inj hn <;>
          exact Or.inr (Or.inr ⟨rfl, rfl, Or.inr rfl⟩)

def assignEntry : CacheEntry predicates where
  subject := assignSubject
  env := noLocals
  input := fun m => ∃ live, m = loadInput 0 live
  key := [1, 2]
  footprint := ⟨[1, 2], [0], [0], [0]⟩
  exit := fun o m => o = .completed ∧ load m 0 = some (.int 7)
  violations := (· = .alarm 1 .invalidAccess)
  reached := (· = 1)

private theorem assign_coverage : assignEntry.Coverage := by
  intro m hm
  change ∃ live, m = loadInput 0 live at hm
  obtain ⟨live, rfl⟩ := hm
  constructor
  · intro evs c hp
    rcases assign_prefixes hp with ⟨rfl, -⟩ | ⟨-, rfl, -⟩ | ⟨-, rfl, -⟩ <;>
      simp [assignEntry, loadReads, loadWrites, AccessesCovered]
  · intro evs o out hp
    rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, rfl, (h | h)⟩
    all_goals first | contradiction | simp [loadReads, loadWrites, assignEntry]
  · intro evs o out hp
    rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, rfl, (h | h)⟩
    all_goals first | contradiction | simp [loadReads, loadWrites, assignEntry]

private theorem assign_producer : assignEntry.ProducerSound := by
  constructor
  · intro m hm o out h
    change ∃ live, m = loadInput 0 live at hm
    obtain ⟨live, rfl⟩ := hm
    obtain ⟨evs, hp⟩ := h
    rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, -, (h | h)⟩
    · contradiction
    · contradiction
    · contradiction
    · cases h
      exact ⟨rfl, rfl⟩
  · intro m hm v h
    change ∃ live, m = loadInput 0 live at hm
    obtain ⟨live, rfl⟩ := hm
    cases v with
    | alarm l a =>
      obtain ⟨evs, out, hp⟩ := h
      rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, -, (h | h)⟩
      · contradiction
      · cases h; rfl
      · contradiction
      · contradiction
    | assertion l =>
      obtain ⟨evs, e, k, env, out, hp, -⟩ := h
      rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, -, (h | h)⟩ <;>
        first | contradiction | simp [assignLoad] at h
  · intro m hm l ⟨env, out, evs, s, k, hp, hl⟩
    change ∃ live, m = loadInput 0 live at hm
    obtain ⟨live, rfl⟩ := hm
    rcases assign_prefixes hp with ⟨-, h⟩ | ⟨-, -, h⟩ | ⟨-, -, (h | h)⟩
    · cases h; exact hl.symm
    · contradiction
    · contradiction
    · contradiction

private theorem assign_matches (live : Bool) :
    assignEntry.Matches FunMem.allocatorAgreement (loadInput 9 live) := by
  refine ⟨loadInput 0 live, ⟨live, rfl⟩, ⟨?_, ?_, ?_⟩⟩
  · intro b hb
    simp [assignEntry] at hb
    rcases hb with rfl | rfl <;> cases live <;> rfl
  · intro b hb
    have he : b = 0 := by simpa [assignEntry] using hb
    subst b
    cases live <;> rfl
  · cases live <;> rfl

/-- With key {p, *p}, a different old x gives the same load fault, or
a normal exit with x equal to 7. The construction supplies both claims. -/
theorem load_overwrite_entry :
    assignEntry.key = [1, 2] ∧ 0 ∉ assignEntry.key ∧
      Prefix assignSubject ⟨noLocals, loadInput 9 false⟩ loadReads
        (.fault 1 .invalidAccess (loadInput 9 false)) ∧
      assignEntry.violations (.alarm 1 .invalidAccess) ∧
      assignEntry.reached 1 ∧
      ∃ w, predicates.γ (assignEntry.exit .completed) w ∧
        AgreeOn [0] w (loadOut 9) := by
  have hs := assignEntry.sound_of_producer (a := FunMem.allocatorAgreement)
    ⟨loadInput 0 false, false, rfl⟩ assign_producer assign_coverage (by
      constructor
      · exact fun _ h => h
      · exact fun _ h hn => False.elim (hn h))
  have hfault : Prefix assignSubject ⟨noLocals, loadInput 9 false⟩ loadReads
      (.fault 1 .invalidAccess (loadInput 9 false)) :=
    steps_iff_run.mpr ⟨1, rfl⟩
  have hreach : Reach assignSubject ⟨noLocals, loadInput 9 false⟩ 1 :=
    ⟨noLocals, _, [], assignLoad, .stop, .refl _, rfl⟩
  have obs := (hs.matched _ (assign_matches false)).2
  have hout : Exit assignSubject ⟨noLocals, loadInput 9 true⟩ .completed (loadOut 9) :=
    ⟨loadWrites, steps_iff_run.mpr ⟨2, rfl⟩⟩
  exact ⟨rfl, by decide, hfault, obs.safety _ ⟨_, _, hfault⟩, obs.reach _ hreach,
    (hs.matched _ (assign_matches true)).2.exit _ _ hout⟩

def testFirst : Stmt :=
  .seq 3 (.assert 2 (.binop .eq (.var "x") (.const 0))) assignLoad

def assertSubject : Subject :=
  ⟨loadProg, testFirst, ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def assertEntry : CacheEntry predicates :=
  { assignEntry with
    subject := assertSubject
    footprint := ⟨[0, 1, 2], [0], [0], [0]⟩
    key := [0, 1, 2] }

def assertEntryWithoutX : CacheEntry predicates := { assertEntry with key := [1, 2] }

/-- Testing the old destination before a full overwrite requires keeping
its value in the key. Agreement on the load alone can miss a failure. -/
theorem assert_before_overwrite :
    assertEntry.KeyCovers ∧ 0 ∈ assertEntry.key ∧
      ¬ assertEntryWithoutX.KeyCovers ∧
      AgreeOn [1, 2] (loadInput 0 true) (loadInput 9 true) ∧
      assertionOf? loadProg (run loadProg 1
        (Config.entry testFirst ⟨noLocals, loadInput 0 true⟩)).2 = some (2, true) ∧
      AssertionFails assertSubject ⟨noLocals, loadInput 9 true⟩ 2 ∧
      Exit assertSubject ⟨noLocals, loadInput 9 true⟩ .completed (loadOut 9) := by
  refine ⟨⟨fun _ h => h, fun _ h hn => False.elim (hn h)⟩, by decide, ?_, ?_,
    by decide, assertionFails_of_run (n := 1) (by decide), ?_⟩
  · intro h
    have h0 : 0 ∈ [1, 2] := h.1 (show 0 ∈ assertEntry.footprint.reads by decide)
    exact (by decide : 0 ∉ [1, 2]) h0
  · intro b hb
    simp at hb
    rcases hb with rfl | rfl <;> rfl
  · exact ⟨.read 0 :: loadWrites, steps_iff_run.mpr ⟨5, rfl⟩⟩

private def returnLoad : Stmt := .ret 4 (some loadP)

def returnSubject : Subject :=
  ⟨loadProg, returnLoad, ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def returnIn : FunMem := loadInput 0 true
def returnOutcome : Outcome := .returned (some (.int 7))

def missingPointee : CacheEntry predicates where
  subject := returnSubject
  env := noLocals
  input := (· = returnIn)
  key := [1]
  footprint := ⟨[1], [], [], []⟩
  exit := fun o m => o = returnOutcome ∧ m = returnIn
  violations := Unsafe returnSubject ⟨noLocals, returnIn⟩
  reached := Reach returnSubject ⟨noLocals, returnIn⟩

/-- Returning 7 is sound on the producing input. Leaving out the pointed
block fails coverage even though the return value is correct. -/
theorem missing_pointee_rejected :
    missingPointee.ProducerSound ∧
      Exit returnSubject ⟨noLocals, returnIn⟩ returnOutcome returnIn ∧
      ¬ missingPointee.Coverage := by
  refine ⟨⟨?_, ?_, ?_⟩, ⟨loadReads, steps_iff_run.mpr ⟨2, rfl⟩⟩, ?_⟩
  · intro m hm o out he
    change m = returnIn at hm
    subst m
    obtain ⟨evs, hp⟩ := he
    obtain ⟨n, hn⟩ := steps_run hp
    change run loadProg n (.run returnLoad .stop noLocals returnIn) = _ at hn
    rcases n with _ | _ | n
    · cases (Prod.mk.inj hn).2
    · cases (Prod.mk.inj hn).2
    · cases n <;> cases (Prod.mk.inj hn).2 <;> exact ⟨rfl, rfl⟩
  · intro m hm v hv
    change m = returnIn at hm
    simpa only [hm] using hv
  · intro m hm l hl
    change m = returnIn at hm
    simpa only [hm] using hl
  · intro h
    have hp : Prefix returnSubject ⟨noLocals, returnIn⟩ loadReads
        (.ret (some (.int 7)) .stop returnIn) := steps_iff_run.mpr ⟨1, rfl⟩
    have hc := (h returnIn rfl).accesses _ _ hp (.read 2) (by decide)
    exact (by decide : 2 ∉ [1]) hc

def laterLeakState : State FunMem :=
  ⟨leakState.env, release (create leakState.mem (.int 0)).2 2⟩

/-- Equal key contents do not imply the same identifier for a callee local.
The pointer written by the two runs names block 2 and block 3 respectively. -/
theorem allocator_needed :
    AgreeOn [0, 1] leakState.mem laterLeakState.mem ∧
      ¬ FunMem.allocatorAgreement.rel leakState.mem laterLeakState.mem ∧
      load (run leakProg 7 (Config.entry leakStmt leakState)).2.mem 0 = some (.ptr 2) ∧
      load (run leakProg 7 (Config.entry leakStmt laterLeakState)).2.mem 0 = some (.ptr 3) := by
  refine ⟨?_, by change (2 : Nat) ≠ 3; decide, by decide, by decide⟩
  intro b hb
  simp at hb
  rcases hb with rfl | rfl <;> rfl

def faultOnlyWrite : Stmt := .ite 1 (.var "p")
  (.seq 2 (.assign 3 (.var "x") (.const 7)) (.ret 4 (some (.deref (.const 0)))))
  (.skip 5)

def faultOnlySubject : Subject :=
  ⟨loadProg, faultOnlyWrite, ⟨by decide, ⟨fun _ => 0, by decide⟩, by decide, by decide⟩⟩

def faultOnlyInput (x p : Int) : State FunMem := topState [.int x, .int p]

/-- A write before a fault belongs to the prefix footprint. On the normal
branch the block is untouched, so replay cannot take its value from the
producer's precise exit state. -/
theorem prefix_writes_can_exceed_exit_writes :
    (.write 0 : Event) ∈
      (run loadProg 6 (Config.entry faultOnlyWrite (faultOnlyInput 3 1))).1 ∧
      AgreeOn [1] (faultOnlyInput 3 0).mem (faultOnlyInput 9 0).mem ∧
      Exit faultOnlySubject (faultOnlyInput 3 0) .completed (faultOnlyInput 3 0).mem ∧
      Exit faultOnlySubject (faultOnlyInput 9 0) .completed (faultOnlyInput 9 0).mem ∧
      (∀ o out, Exit faultOnlySubject (faultOnlyInput 3 1) o out → False) ∧
      (∀ o out, Exit faultOnlySubject (faultOnlyInput 3 0) o out →
        ¬ AgreeOn [0] out (faultOnlyInput 9 0).mem) := by
  refine ⟨by decide, ?_, ⟨[.read 1], steps_iff_run.mpr ⟨3, rfl⟩⟩,
    ⟨[.read 1], steps_iff_run.mpr ⟨3, rfl⟩⟩, ?_, ?_⟩
  · intro b hb
    have he : b = 1 := by simpa using hb
    subst b
    rfl
  · rintro o out ⟨evs, hp⟩
    obtain ⟨n, hn⟩ := steps_run hp
    change run loadProg n (Config.entry faultOnlyWrite (faultOnlyInput 3 1)) = _ at hn
    rcases n with _ | _ | _ | _ | _ | _ | n <;> cases (Prod.mk.inj hn).2
  · rintro o out ⟨evs, hp⟩
    obtain ⟨n, hn⟩ := steps_run hp
    change run loadProg n (Config.entry faultOnlyWrite (faultOnlyInput 3 0)) = _ at hn
    rcases n with _ | _ | _ | _ | n <;> cases (Prod.mk.inj hn).2 <;>
      exact fun h => (by decide : some (.int 3 : Value) ≠ some (.int 9)) (h 0 (by decide))

end Checks
