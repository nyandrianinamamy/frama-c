import ReuseModel.Replay

/-!
# Cache entry construction

Ordinary producer soundness covers the executions from its own input. The
footprint and key extend the claims to a matching memory. Safety and Reach
use every finite prefix, and Exit uses only normal exits. The Exit part
supplies a producing output on the blocks possibly written at a normal
exit. The hit theorem in `ReuseModel.Hit` accounts for the caller's frame.
-/

namespace ReuseModel

/-- Coverage of reads and writes uses all prefixes. The two other sets
describe writes at normal exits. -/
structure Footprint where
  reads : BlockSet
  writes : BlockSet
  exitWrites : BlockSet
  sureWrites : BlockSet

/-- The mandatory parts of a model entry. The environment fixes the
bindings at entry, including those of a function body. -/
structure CacheEntry {M : Type} (d : Domain M) where
  subject : Subject
  env : Env
  input : d.State
  key : BlockSet
  footprint : Footprint
  exit : Outcome → d.State
  violations : Violation → Prop
  reached : Label → Prop

namespace CacheEntry

variable {M : Type} {d : Domain M}

/-- The matching key contains the reads and the possible exit writes
that are not certain full overwrites. Closure may add other blocks. -/
def KeyCovers (entry : CacheEntry d) : Prop :=
  entry.footprint.reads ⊆ entry.key ∧
  ∀ b ∈ entry.footprint.exitWrites, b ∉ entry.footprint.sureWrites → b ∈ entry.key

variable [Memory M]

/-- Coverage of one starting memory. The sure set is a lower bound: each
of these blocks is written on each normal exit. Every write recorded on
a normal exit succeeded, and every store in the model is a full overwrite. -/
structure Covers (entry : CacheEntry d) (m : M) : Prop where
  accesses : ∀ evs c, Prefix entry.subject ⟨entry.env, m⟩ evs c →
    AccessesCovered entry.footprint.reads entry.footprint.writes evs
  exitWrites : ∀ evs o out, Prefix entry.subject ⟨entry.env, m⟩ evs (.done o out) →
    ∀ b, Event.write b ∈ evs → b ∈ entry.footprint.exitWrites
  sure : ∀ evs o out, Prefix entry.subject ⟨entry.env, m⟩ evs (.done o out) →
    ∀ b ∈ entry.footprint.sureWrites, Event.write b ∈ evs

/-- The stored footprint covers executions from every producing memory. -/
def Coverage (entry : CacheEntry d) : Prop :=
  ∀ m, d.γ entry.input m → entry.Covers m

/-- Ordinary producer soundness on the stored input. The unsafe part records
possible run-time alarms and assertions for which validity is not claimed. -/
structure ProducerSound (entry : CacheEntry d) : Prop where
  exit : ∀ m, d.γ entry.input m → ∀ o out,
    Exit entry.subject ⟨entry.env, m⟩ o out → d.γ (entry.exit o) out
  safety : ∀ m, d.γ entry.input m → ∀ v,
    Unsafe entry.subject ⟨entry.env, m⟩ v → entry.violations v
  reach : ∀ m, d.γ entry.input m → ∀ l,
    Reach entry.subject ⟨entry.env, m⟩ l → entry.reached l

/-- A matching concrete memory has a single producing witness. In addition
to agreeing on the key, it agrees on write-target liveness and allocation.
The current execution uses the same entry bindings. -/
def Matches (entry : CacheEntry d) (a : AllocatorAgreement M) (m : M) : Prop :=
  ∃ w, d.γ entry.input w ∧ ReplayAgreement a entry.key entry.footprint.writes w m

/-- Each producing memory is a match witnessed by itself. -/
theorem matches_of_input {entry : CacheEntry d} {a : AllocatorAgreement M}
    {m : M} (hm : d.γ entry.input m) : entry.Matches a m :=
  ⟨m, hm, ReplayAgreement.refl a _ _ m⟩

/-- The claims supplied to a matching execution. Exit gives a witness
covered by the stored output and in agreement on possible exit writes. -/
structure Observations (entry : CacheEntry d) (m : M) : Prop where
  exit : ∀ o out, Exit entry.subject ⟨entry.env, m⟩ o out →
    ∃ w, d.γ (entry.exit o) w ∧ AgreeOn entry.footprint.exitWrites w out
  safety : ∀ v, Unsafe entry.subject ⟨entry.env, m⟩ v → entry.violations v
  reach : ∀ l, Reach entry.subject ⟨entry.env, m⟩ l → entry.reached l

/-- A sound entry has a producing memory and covers the observations and the
footprint of every matching memory. -/
structure Sound (entry : CacheEntry d) (a : AllocatorAgreement M) : Prop where
  nonempty : ∃ w, d.γ entry.input w
  matched : ∀ m, entry.Matches a m → entry.Covers m ∧ entry.Observations m

omit [Memory M] in
private theorem KeyCovers.onKey {entry : CacheEntry d} (hk : entry.KeyCovers)
    {evs : List Event}
    (hc : AccessesCovered entry.footprint.reads entry.footprint.writes evs) :
    AccessesCovered entry.key entry.footprint.writes evs := by
  intro e he
  have h := hc e he
  cases e with
  | read b => exact hk.1 h
  | _ => exact h

private theorem replay_prefix {entry : CacheEntry d} {a : AllocatorAgreement M}
    {m w : M} (ha : ReplayAgreement a entry.key entry.footprint.writes w m)
    (hc : entry.Covers w) (hk : entry.KeyCovers)
    {evs : List Event} {c : Config M}
    (hp : Prefix entry.subject ⟨entry.env, m⟩ evs c) :
    ∃ c', Prefix entry.subject ⟨entry.env, w⟩ evs c' ∧
      c'.withMem c.mem = c ∧
      ReplayAgreement a (updatedBlocks evs ++ entry.key) entry.footprint.writes
        c'.mem c.mem := by
  obtain ⟨fuel, hrun⟩ := steps_run hp
  have hkey (es : List Event) (c' : Config M)
      (hpre : Prefix entry.subject ⟨entry.env, w⟩ es c') :
      AccessesCovered entry.key entry.footprint.writes es :=
    hk.onKey (hc.accesses es c' hpre)
  let start := Config.entry entry.subject.stmt ⟨entry.env, w⟩
  let r := run entry.subject.prog fuel start
  have hr := run_agree (c := start) ha hkey fuel
  change ∃ m', run entry.subject.prog fuel (start.withMem m) =
    (r.1, r.2.withMem m') ∧
    ReplayAgreement a (updatedBlocks r.1 ++ entry.key) entry.footprint.writes r.2.mem m'
    at hr
  obtain ⟨m', hm', hagree⟩ := hr
  change run entry.subject.prog fuel (start.withMem m) = (evs, c) at hrun
  rw [hrun, Prod.mk.injEq] at hm'
  obtain ⟨he, hcfg⟩ := hm'
  have hmem : c.mem = m' := by rw [hcfg]; cases r.2 <;> rfl
  refine ⟨r.2, ?_, ?_, ?_⟩
  · rw [he]
    exact run_steps _ _ _
  · rw [hmem]
    exact hcfg.symm
  · rw [he, hmem]
    exact hagree

/-- Soundness of a saved before-state for the producing input, projected
onto the matching key. Different visits may use different witnesses in the
same saved state. -/
def InnerSound (entry : CacheEntry d) (inner : Label → d.State) : Prop :=
  ∀ w, d.γ entry.input w → ∀ l env atVisit,
    Visit entry.subject ⟨entry.env, w⟩ l env atVisit →
    ∃ represented, d.γ (inner l) represented ∧ AgreeOn entry.key represented atVisit

/-- Each matching member's visit is covered by the shared state on the
key blocks issued in that member's entry memory. Replay aligns the control
point and preserves key agreement after writes and lexical sweeps. -/
theorem shared_inner {entry : CacheEntry d} {a : AllocatorAgreement M}
    {inner : Label → d.State}
    (hi : entry.InnerSound inner) (hc : entry.Coverage) (hk : entry.KeyCovers)
    {m : M} (hm : entry.Matches a m) {l : Label} {env : Env} {atVisit : M}
    (hv : Visit entry.subject ⟨entry.env, m⟩ l env atVisit) :
    ∃ represented, d.γ (inner l) represented ∧
      ∀ b ∈ entry.key, Memory.Issued m b → Memory.load represented b = Memory.load atVisit b := by
  obtain ⟨w, hw, ha⟩ := hm
  obtain ⟨evs, st, k, hpre, hl⟩ := hv
  obtain ⟨c, hpre', hs, hr⟩ := replay_prefix ha (hc w hw) hk hpre
  cases c <;> cases hs
  obtain ⟨represented, hγ, hkey⟩ := hi w hw l env _ ⟨evs, st, k, hpre', hl⟩
  exact ⟨represented, hγ, fun b hb _ =>
    (hkey b hb).trans (hr.contents b (List.mem_append_right _ hb))⟩

private theorem Steps.snoc {p : Program} {c c' c'' : Config M}
    {evs es : List Event} (hp : Steps p c evs c')
    (hs : step p c' = some (es, c'')) : Steps p c (evs ++ es) c'' := by
  induction hp with
  | refl => simpa using Steps.head hs (.refl _)
  | head hs' _ ih =>
    rw [List.append_assoc]
    exact .head hs' (ih hs)

private theorem updated_of_write {b : Block} {evs : List Event}
    (hb : Event.write b ∈ evs) : b ∈ updatedBlocks evs :=
  List.mem_filterMap.mpr ⟨.write b, hb, rfl⟩

/-- Producer soundness and coverage justify an entry on its matching key. -/
theorem sound_of_producer {entry : CacheEntry d} {a : AllocatorAgreement M}
    (hne : ∃ w, d.γ entry.input w) (hp : entry.ProducerSound)
    (hc : entry.Coverage) (hk : entry.KeyCovers) : entry.Sound a := by
  refine ⟨hne, ?_⟩
  rintro m ⟨w, hw, ha⟩
  have cov := hc w hw
  have paired {evs : List Event} {c : Config M}
      (h : Prefix entry.subject ⟨entry.env, m⟩ evs c) :=
    replay_prefix ha cov hk h
  have pairedExit {evs : List Event} {o : Outcome} {out : M}
      (h : Prefix entry.subject ⟨entry.env, m⟩ evs (.done o out)) :
      ∃ out', Prefix entry.subject ⟨entry.env, w⟩ evs (.done o out') ∧
        AgreeOn (updatedBlocks evs ++ entry.key) out' out := by
    obtain ⟨c, hpre, hs, hmem⟩ := paired h
    cases c <;> cases hs
    exact ⟨_, hpre, hmem.contents⟩
  constructor
  · constructor
    · intro evs c h
      obtain ⟨_, hpre, -, -⟩ := paired h
      exact cov.accesses _ _ hpre
    · intro evs o out h
      obtain ⟨_, hpre, -⟩ := pairedExit h
      exact cov.exitWrites _ _ _ hpre
    · intro evs o out h
      obtain ⟨_, hpre, -⟩ := pairedExit h
      exact cov.sure _ _ _ hpre
  · constructor
    · rintro o out ⟨evs, h⟩
      obtain ⟨out', hpre, hmem⟩ := pairedExit h
      refine ⟨out', hp.exit w hw o out' ⟨evs, hpre⟩, ?_⟩
      intro b hb
      apply hmem b
      by_cases hs : b ∈ entry.footprint.sureWrites
      · exact List.mem_append_left _ (updated_of_write (cov.sure _ _ _ hpre b hs))
      · exact List.mem_append_right _ (hk.2 b hb hs)
    · intro v hv
      apply hp.safety w hw v
      cases v with
      | alarm l alarm =>
        obtain ⟨evs, out, h⟩ := hv
        obtain ⟨c, hpre, hs, -⟩ := paired h
        cases c <;> cases hs
        exact ⟨evs, _, hpre⟩
      | assertion l =>
        obtain ⟨evs, e, k, env, out, h, hf⟩ := hv
        obtain ⟨c, hpre, hs, hmem⟩ := paired h
        cases c <;> cases hs
        rename_i old
        have hstep : step entry.subject.prog (.run (.assert l e) k env old) =
            some ((evalExpr entry.subject.prog env old e).1, .next k env old) := rfl
        -- Coverage of the assertion's reads comes from the next prefix.
        have hreads := hk.onKey (cov.accesses _ _ (Steps.snoc hpre hstep))
        have hkey : AccessesCovered entry.key entry.footprint.writes
            (evalExpr entry.subject.prog env old e).1 :=
          fun e he => hreads e (List.mem_append_right _ he)
        have he := assertionHolds_agree
          (fun b hb => hmem.contents b (List.mem_append_right _ hb)) hkey
        exact ⟨evs, e, k, env, old, hpre, he.symm.trans hf⟩
    · rintro l ⟨env, out, evs, s, k, h, hl⟩
      apply hp.reach w hw l
      obtain ⟨c, hpre, hs, -⟩ := paired h
      cases c <;> cases hs
      exact ⟨env, _, evs, s, k, hpre, hl⟩

end CacheEntry

end ReuseModel
