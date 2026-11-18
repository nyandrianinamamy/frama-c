import ReuseModel.Domain
import ReuseModel.Semantics
import ReuseModel.Observations

/-!
# Agreement of finite prefixes on a key

Reads use equal contents. A store checks only liveness before replacing a
whole block, so the two old values may differ. Starting and ending local
lifetimes also establish agreement on the affected block. Allocation uses a
separate relation on memories: contents on a key cannot determine the next
fresh identifier.
-/

namespace ReuseModel

open Memory

/-- An agreement on allocation state that survives the memory operations
and gives the same identifier from two creations with the same value. -/
structure AllocatorAgreement (M : Type) [Memory M] where
  rel : M → M → Prop
  store : ∀ {m n m' n' : M} {b v}, rel m n →
    Memory.store m b v = some m' → Memory.store n b v = some n' → rel m' n'
  create : ∀ {m n : M} v, rel m n →
    (Memory.create m v).1 = (Memory.create n v).1 ∧
    rel (Memory.create m v).2 (Memory.create n v).2
  release : ∀ {m n : M} b, rel m n →
    rel (Memory.release m b) (Memory.release n b)

/-- Two function memories agree on allocation when their next identifiers
are equal. -/
def FunMem.allocatorAgreement : AllocatorAgreement FunMem where
  rel m n := m.next = n.next
  store := by
    intro m n m' n' b v h hm hn
    change FunMem.store m b v = some m' at hm
    change FunMem.store n b v = some n' at hn
    unfold FunMem.store at hm hn
    split at hm <;> split at hn <;> cases hm <;> cases hn
    exact h
  create v h := ⟨h, congrArg Nat.succ h⟩
  release _ h := h

/-- The blocks whose contents are established by the events. At a failed
write, both blocks are dead. -/
def updatedBlocks : List Event → BlockSet :=
  List.filterMap fun
    | .read _ => none
    | .write b | .scopeEnter b | .scopeExit b => some b

/-- All reads are keyed and all writes are recorded, including attempted
accesses that fault. -/
def AccessesCovered (K W : BlockSet) (evs : List Event) : Prop :=
  ∀ e ∈ evs, match e with
    | .read b => b ∈ K
    | .write b => b ∈ W
    | _ => True

section

variable {M : Type} [Memory M]

/-- The two memories agree on known contents, on liveness of write targets,
and on allocation state. -/
structure ReplayAgreement (a : AllocatorAgreement M) (K W : BlockSet)
    (m n : M) : Prop where
  contents : AgreeOn K m n
  live : ∀ b ∈ W, (load m b).isSome = (load n b).isSome
  allocator : a.rel m n

private theorem ReplayAgreement.restrict {a : AllocatorAgreement M}
    {K K' W : BlockSet} {m n : M}
    (h : ReplayAgreement a K W m n) (hK : K' ⊆ K) :
    ReplayAgreement a K' W m n :=
  ⟨fun b hb => h.contents b (hK hb), h.live, h.allocator⟩

private def ReadsAgree (m n : M) (evs : List Event) : Prop :=
  ∀ b, Event.read b ∈ evs → load m b = load n b

private theorem ReadsAgree.left {m n : M} {u v : List Event}
    (h : ReadsAgree m n (u ++ v)) : ReadsAgree m n u :=
  fun b hb => h b (List.mem_append_left _ hb)

private theorem ReadsAgree.right {m n : M} {u v : List Event}
    (h : ReadsAgree m n (u ++ v)) : ReadsAgree m n v :=
  fun b hb => h b (List.mem_append_right _ hb)

private theorem evalExpr_agree (p : Program) (env : Env) (m n : M) (e : Expr)
    (h : ReadsAgree m n (evalExpr p env m e).1) :
    evalExpr p env n e = evalExpr p env m e := by
  induction e with
  | const | addr => rfl
  | var x =>
    simp only [evalExpr] at h ⊢
    cases he : resolve p env x with
    | none => rfl
    | some b =>
      rw [he] at h
      simp [loadValue, h b (by simp)]
  | deref e ih =>
    simp only [evalExpr] at h ⊢
    split at h
    · next es b he =>
      have he' := (ih (by rw [he]; exact h.left)).trans he
      rw [he']
      simp [loadValue, h b (by simp)]
    · next es v he => rw [(ih (by rw [he]; exact h)).trans he]
    · next es a he => rw [(ih (by rw [he]; exact h)).trans he]
  | binop op e₁ e₂ ih₁ ih₂ =>
    simp only [evalExpr] at h ⊢
    split at h
    · next es a he => rw [(ih₁ (by rw [he]; exact h)).trans he]
    · next es v he =>
      split at h
      · next es' a he' => rw [(ih₁ (by rw [he]; exact h.left)).trans he,
          (ih₂ (by rw [he']; exact h.right)).trans he']
      · next es' v' he' => rw [(ih₁ (by rw [he]; exact h.left)).trans he,
          (ih₂ (by rw [he']; exact h.right)).trans he']

private theorem evalLExpr_agree (p : Program) (env : Env) (m n : M) (e : LExpr)
    (h : ReadsAgree m n (evalLExpr p env m e).1) :
    evalLExpr p env n e = evalLExpr p env m e := by
  cases e with
  | var => rfl
  | deref e =>
    simp only [evalLExpr] at h ⊢
    have hreads : ReadsAgree m n (evalExpr p env m e).1 := by
      split at h <;> rename_i he <;> rw [he] <;> exact h
    rw [evalExpr_agree p env m n e hreads]

private theorem evalArgs_agree (p : Program) (env : Env) (m n : M)
    (args : List Expr) (h : ReadsAgree m n (evalArgs p env m args).1) :
    evalArgs p env n args = evalArgs p env m args := by
  induction args with
  | nil => rfl
  | cons e es ih =>
    simp only [evalArgs] at h ⊢
    split at h
    · next evs a he => rw [(evalExpr_agree p env m n e (by rw [he]; exact h)).trans he]
    · next evs v he =>
      split at h
      · next evs' a he' =>
        rw [(evalExpr_agree p env m n e (by rw [he]; exact h.left)).trans he,
          (ih (by rw [he']; exact h.right)).trans he']
      · next evs' vs he' =>
        rw [(evalExpr_agree p env m n e (by rw [he]; exact h.left)).trans he,
          (ih (by rw [he']; exact h.right)).trans he']

private theorem agree_update {a : AllocatorAgreement M} {K W : BlockSet}
    {m n m' n' : M} {b : Block}
    (h : ReplayAgreement a K W m n)
    (hsame : load m' b = load n' b)
    (hm : ∀ c, c ≠ b → load m' c = load m c)
    (hn : ∀ c, c ≠ b → load n' c = load n c)
    (ha : a.rel m' n') : ReplayAgreement a (b :: K) W m' n' := by
  refine ⟨?_, ?_, ha⟩
  · intro c hc
    by_cases heq : c = b
    · subst c; exact hsame
    · rw [hm c heq, hn c heq]
      exact h.contents c ((List.mem_cons.mp hc).resolve_left heq)
  · intro c hc
    by_cases heq : c = b
    · subst c; rw [hsame]
    · rw [hm c heq, hn c heq]
      exact h.live c hc

private theorem store_agree {a : AllocatorAgreement M}
    {K W : BlockSet} {m n : M} {b : Block} (v : Value)
    (h : ReplayAgreement a K W m n) (hb : b ∈ W) :
    match store m b v with
    | none => store n b v = none ∧ ReplayAgreement a (b :: K) W m n
    | some m' => ∃ n', store n b v = some n' ∧ ReplayAgreement a (b :: K) W m' n' := by
  have hstore : (store m b v).isSome = (store n b v).isSome := (store_ok_iff (m := m) (b := b) (v := v)).trans
    ((h.live b hb).trans store_ok_iff.symm)
  cases hm : store m b v <;> cases hn : store n b v
  · have hdead (s : M) (hs : store s b v = none) : load s b = none := by
      have he := store_ok_iff (m := s) (b := b) (v := v)
      cases hl : load s b <;> simp [hs, hl] at he ⊢
    exact ⟨rfl, agree_update h ((hdead m hm).trans (hdead n hn).symm)
      (fun _ _ => rfl) (fun _ _ => rfl) h.allocator⟩
  · simp [hm, hn] at hstore
  · simp [hm, hn] at hstore
  · exact ⟨_, rfl, agree_update h ((load_store_same hm).trans (load_store_same hn).symm)
      (fun _ => load_store_other hm) (fun _ => load_store_other hn) (a.store h.allocator hm hn)⟩

private theorem createAll_agree {a : AllocatorAgreement M}
    {K W : BlockSet} {m n : M} (vs : List Value)
    (h : ReplayAgreement a K W m n) :
    (createAll m vs).1 = (createAll n vs).1 ∧
    ReplayAgreement a ((createAll m vs).1 ++ K) W
      (createAll m vs).2 (createAll n vs).2 := by
  induction vs generalizing K m n with
  | nil => exact ⟨rfl, h⟩
  | cons v vs ih =>
    obtain ⟨he, ha⟩ := a.create v h.allocator
    have hc := agree_update h
      (by rw [load_create_same, he, load_create_same])
      (load_create_other m v) (fun b hb => load_create_other n v b (he ▸ hb)) ha
    obtain ⟨he', hr⟩ := ih hc
    refine ⟨by simp only [createAll, he, he'], hr.restrict ?_⟩
    simp only [createAll, List.cons_append]
    intro b hb
    simpa only [List.mem_cons, List.mem_append, or_comm, or_left_comm, or_assoc] using hb

private theorem releaseAll_agree {a : AllocatorAgreement M}
    {K W : BlockSet} {m n : M} (bs : List Block)
    (h : ReplayAgreement a K W m n) :
    ReplayAgreement a (bs ++ K) W (releaseAll m bs) (releaseAll n bs) := by
  induction bs generalizing K m n with
  | nil => exact h
  | cons b bs ih =>
    have hr := agree_update h
      ((load_release_same m b).trans (load_release_same n b).symm)
      (load_release_other m b) (load_release_other n b) (a.release b h.allocator)
    refine (ih hr).restrict ?_
    intro c hc
    simpa only [List.mem_cons, List.mem_append, or_comm, or_left_comm, or_assoc] using hc

@[simp] private theorem updated_append (es fs : List Event) :
    updatedBlocks (es ++ fs) = updatedBlocks es ++ updatedBlocks fs :=
  List.filterMap_append

@[simp] private theorem updated_enter (bs : List Block) :
    updatedBlocks (bs.map Event.scopeEnter) = bs := by
  induction bs <;> simp_all [updatedBlocks]

@[simp] private theorem updated_exit (bs : List Block) :
    updatedBlocks (bs.map Event.scopeExit) = bs := by
  induction bs <;> simp_all [updatedBlocks]

@[simp] private theorem updated_read (b : Block) :
    updatedBlocks [.read b] = [] := rfl

@[simp] private theorem updated_write (b : Block) :
    updatedBlocks [.write b] = [b] := rfl

@[simp] private theorem updated_expr (p : Program) (env : Env) (m : M) (e : Expr) :
    updatedBlocks (evalExpr p env m e).1 = [] := by
  induction e with
  | const => rfl
  | addr x => simp only [evalExpr]; split <;> rfl
  | var x => simp [evalExpr]; split <;> rfl
  | deref e ih =>
    simp only [evalExpr]
    split <;> rename_i es _ he <;> rw [he] at ih
    · change updatedBlocks es = [] at ih
      simp [ih]
    · exact ih
    · exact ih
  | binop op e₁ e₂ ih₁ ih₂ =>
    simp only [evalExpr]
    split <;> rename_i he <;> rw [he] at ih₁
    · exact ih₁
    · split <;> rename_i he' <;> rw [he'] at ih₂ <;> simp [ih₁, ih₂]

@[simp] private theorem updated_lexpr (p : Program) (env : Env) (m : M) (e : LExpr) :
    updatedBlocks (evalLExpr p env m e).1 = [] := by
  cases e with
  | var x => simp [evalLExpr]; split <;> rfl
  | deref e =>
    simp only [evalLExpr]
    split <;> rename_i he <;> simpa only [he] using updated_expr p env m e

@[simp] private theorem updated_args (p : Program) (env : Env) (m : M) (args : List Expr) :
    updatedBlocks (evalArgs p env m args).1 = [] := by
  induction args with
  | nil => rfl
  | cons e es ih =>
    have he := updated_expr p env m e
    simp only [evalArgs]
    split <;> rename_i h <;> rw [h] at he
    · exact he
    · split <;> rename_i ht <;> rw [ht] at ih <;> simp [he, ih]

private theorem AccessesCovered.reads {K W : BlockSet} {evs : List Event} {m n : M}
    (h : AccessesCovered K W evs) (hK : AgreeOn K m n) : ReadsAgree m n evs :=
  fun b hb => hK b (h (.read b) hb)

private theorem AccessesCovered.sublist {K W : BlockSet} {u v : List Event}
    (h : AccessesCovered K W v) (hu : u ⊆ v) : AccessesCovered K W u :=
  fun e he => h e (hu he)

private theorem AccessesCovered.left {K W : BlockSet} {u v : List Event}
    (h : AccessesCovered K W (u ++ v)) : AccessesCovered K W u :=
  h.sublist (fun _ he => List.mem_append_left _ he)

/-- Replace the memory of a configuration, keeping its control and bindings. -/
def Config.withMem (c : Config M) (m : M) : Config M :=
  match c with
  | .run s k env _ => .run s k env m
  | .next k env _ => .next k env m
  | .ret v k _ => .ret v k m
  | .done o _ => .done o m
  | .fault l alarm _ => .fault l alarm m

private theorem stepAssign_agree {a : AllocatorAgreement M} {K W : BlockSet}
    (p : Program) (l : Label) (lv : LExpr) (e : Expr) (k : Cont) (env : Env)
    {m n : M} (h : ReplayAgreement a K W m n)
    (hc : AccessesCovered K W (execAssign p env m lv e).1) :
    let (evs, c) := stepStmt p (.assign l lv e) k env m
    ∃ n', stepStmt p (.assign l lv e) k env n = (evs, c.withMem n') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c.mem n' := by
  simp only [execAssign] at hc
  simp only [stepStmt, execAssign]
  split at hc
  · next evs alarm he =>
    have hn := (evalExpr_agree p env m n e (by rw [he]; exact hc.reads h.contents)).trans he
    have hu := updated_expr p env m e
    rw [he] at hu
    change updatedBlocks evs = [] at hu
    rw [hn]
    exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
  · next evs v he =>
    split at hc
    · next es alarm hl =>
      have hn := (evalExpr_agree p env m n e
        (by rw [he]; exact (hc.reads h.contents).left)).trans he
      have hln := (evalLExpr_agree p env m n lv
        (by rw [hl]; exact (hc.reads h.contents).right)).trans hl
      have hu := updated_expr p env m e
      have hul := updated_lexpr p env m lv
      rw [he] at hu
      rw [hl] at hul
      change updatedBlocks evs = [] at hu
      change updatedBlocks es = [] at hul
      rw [hn, hln]
      dsimp only
      exact ⟨n, rfl, by simpa [Config.mem, hu, hul] using h⟩
    · next es b hl =>
      have hexpr : AccessesCovered K W (evs ++ es ++ [.write b]) := by
        split at hc <;> exact hc
      have hn := (evalExpr_agree p env m n e
        (by rw [he]; exact (hexpr.reads h.contents).left.left)).trans he
      have hln := (evalLExpr_agree p env m n lv
        (by rw [hl]; exact (hexpr.reads h.contents).left.right)).trans hl
      have hu := updated_expr p env m e
      have hul := updated_lexpr p env m lv
      rw [he] at hu
      rw [hl] at hul
      change updatedBlocks evs = [] at hu
      change updatedBlocks es = [] at hul
      rw [hn, hln]
      dsimp only
      have hs := store_agree v h (hexpr (.write b) (by simp))
      cases hm : store m b v with
      | none =>
        rw [hm] at hs
        rw [hs.1]
        exact ⟨n, rfl, by simpa [Config.mem, hu, hul] using hs.2⟩
      | some m' =>
        rw [hm] at hs
        obtain ⟨n', hsn, ha⟩ := hs
        rw [hsn]
        exact ⟨n', rfl, by simpa [Config.mem, hu, hul] using ha⟩

private theorem stepCall_agree {a : AllocatorAgreement M} {K W : BlockSet}
    (p : Program) (l : Label) (dst : Option Var) (f : FunName) (args : List Expr)
    (k : Cont) (env : Env) {m n : M} (h : ReplayAgreement a K W m n)
    (hc : AccessesCovered K W (execCall p env m dst f args).1) :
    let (evs, c) := stepStmt p (.call l dst f args) k env m
    ∃ n', stepStmt p (.call l dst f args) k env n = (evs, c.withMem n') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c.mem n' := by
  simp only [stepStmt, execCall]
  simp only [execCall] at hc
  have hu := updated_args p env m args
  split at hc
  · next evs alarm he =>
    rw [he] at hu
    change updatedBlocks evs = [] at hu
    rw [(evalArgs_agree p env m n args (by rw [he]; exact hc.reads h.contents)).trans he]
    exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
  · next evs vs he =>
    rw [he] at hu
    change updatedBlocks evs = [] at hu
    have hargs : AccessesCovered K W evs := by
      split at hc
      · split at hc
        · exact hc.left
        · exact hc
      · exact hc
    rw [(evalArgs_agree p env m n args (by rw [he]; exact hargs.reads h.contents)).trans he]
    cases resolveDst p env dst with
    | error alarm => exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
    | ok d =>
      cases p.lookup f with
      | none => exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
      | some fd =>
        by_cases hlen : vs.length = fd.params.length
        · simp only [if_pos hlen]
          obtain ⟨heq, ha⟩ := createAll_agree (vs ++ fd.locals.map fun x => Value.int x.2) h
          refine ⟨_, ?_, by simpa [Config.mem, hu] using ha⟩
          simp only [heq, Config.withMem]
        · simp only [if_neg hlen]
          exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩

private theorem stepRet_agree {a : AllocatorAgreement M} {K W : BlockSet}
    (v : Option Value) (k : Cont) {m n : M} (h : ReplayAgreement a K W m n)
    (hc : AccessesCovered K W (stepRet v k m).1) :
    let (evs, c) := stepRet v k m
    ∃ n', stepRet v k n = (evs, c.withMem n') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c.mem n' := by
  cases k with
  | call site dst env bs k =>
    have ha := releaseAll_agree bs h
    cases dst with
    | none => cases v <;> exact ⟨_, rfl, by simpa [stepRet, Config.mem] using ha⟩
    | some b =>
      cases v with
      | none => exact ⟨_, rfl, by simpa [stepRet, Config.mem] using ha⟩
      | some v =>
        have hall : AccessesCovered K W (bs.map Event.scopeExit ++ [.write b]) := by
          simp only [stepRet] at hc
          split at hc <;> exact hc
        have hs := store_agree v ha (hall (.write b) (by simp))
        cases hm : store (releaseAll m bs) b v with
        | none =>
          rw [hm] at hs
          exact ⟨releaseAll n bs, by simp [stepRet, hm, hs.1, Config.withMem],
            by simpa [stepRet, hm, Config.mem, List.append_assoc,
              List.mem_append] using hs.2.restrict
                (fun c hc => by simpa [or_comm, or_left_comm, or_assoc] using hc)⟩
        | some m' =>
          rw [hm] at hs
          obtain ⟨n', hn, hr⟩ := hs
          exact ⟨n', by simp [stepRet, hm, hn, Config.withMem],
            by simpa [stepRet, hm, Config.mem, List.append_assoc,
              List.mem_append] using hr.restrict
                (fun c hc => by simpa [or_comm, or_left_comm, or_assoc] using hc)⟩
  | _ => exact ⟨n, rfl, h⟩

private theorem stepStmt_agree {a : AllocatorAgreement M} {K W : BlockSet}
    (p : Program) (s : Stmt) (k : Cont) (env : Env)
    {m n : M} (h : ReplayAgreement a K W m n)
    (hc : AccessesCovered K W (stepStmt p s k env m).1) :
    let (evs, c) := stepStmt p s k env m
    ∃ n', stepStmt p s k env n = (evs, c.withMem n') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c.mem n' := by
  cases s with
  | skip | seq => exact ⟨n, rfl, h⟩
  | assign l lv e =>
    apply stepAssign_agree p l lv e k env h
    revert hc
    simp only [stepStmt]
    split <;> rename_i he <;> rw [he] <;> exact id
  | call l dst f args =>
    apply stepCall_agree p l dst f args k env h
    revert hc
    simp only [stepStmt]
    split <;> rename_i he <;> rw [he] <;> exact id
  | ite l e s₁ s₂ =>
    have hr : AccessesCovered K W (evalExpr p env m e).1 := by
      revert hc
      simp only [stepStmt]
      split <;> rename_i he <;> rw [he] <;> exact id
    have hn := evalExpr_agree p env m n e (hr.reads h.contents)
    have hu := updated_expr p env m e
    simp only [stepStmt, hn]
    split <;> rename_i he <;> rw [he] at hu <;>
      exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
  | loop l e s =>
    have hr : AccessesCovered K W (evalExpr p env m e).1 := by
      revert hc
      simp only [stepStmt]
      split
      · rename_i he
        rw [he]
        split <;> exact id
      · rename_i he
        rw [he]
        exact id
    have hn := evalExpr_agree p env m n e (hr.reads h.contents)
    have hu := updated_expr p env m e
    simp only [stepStmt, hn]
    split
    · rename_i he
      rw [he] at hu
      split <;> exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
    · rename_i he
      rw [he] at hu
      exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
  | ret l e =>
    cases e with
    | none => exact ⟨n, rfl, h⟩
    | some e =>
      have hr : AccessesCovered K W (evalExpr p env m e).1 := by
        revert hc
        simp only [stepStmt]
        split <;> rename_i he <;> rw [he] <;> exact id
      have hn := evalExpr_agree p env m n e (hr.reads h.contents)
      have hu := updated_expr p env m e
      simp only [stepStmt, hn]
      split <;> rename_i he <;> rw [he] at hu <;>
        exact ⟨n, rfl, by simpa [Config.mem, hu] using h⟩
  | assert l e =>
    have hn := evalExpr_agree p env m n e (hc.reads h.contents)
    exact ⟨n, by simp only [stepStmt, hn, Config.withMem],
      by simpa [stepStmt, Config.mem] using h⟩

private theorem step_agree {a : AllocatorAgreement M} {K W : BlockSet}
    {p : Program} {c c' : Config M} {evs : List Event} {n : M}
    (hs : step p c = some (evs, c')) (h : ReplayAgreement a K W c.mem n)
    (hc : AccessesCovered K W evs) :
    ∃ n', step p (c.withMem n) = some (evs, c'.withMem n') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c'.mem n' := by
  cases c with
  | run s k env m =>
    simp only [step, Option.some.injEq] at hs
    have he : _ = evs := congrArg Prod.fst hs
    have hcfg : _ = c' := congrArg Prod.snd hs
    subst evs c'
    obtain ⟨n', hn, ha⟩ := stepStmt_agree p s k env h hc
    exact ⟨n', congrArg some hn, ha⟩
  | next k env m =>
    simp only [step, Option.some.injEq] at hs
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj hs
    cases k <;> exact ⟨n, rfl, h⟩
  | ret v k m =>
    simp only [step, Option.some.injEq] at hs
    have he : _ = evs := congrArg Prod.fst hs
    have hcfg : _ = c' := congrArg Prod.snd hs
    subst evs c'
    obtain ⟨n', hn, ha⟩ := stepRet_agree v k h hc
    exact ⟨n', congrArg some hn, ha⟩
  | done | fault => contradiction

/-- Under coverage of producing prefixes, the matched run has the same
events and control at each finite step count. Its memory agrees on the key
and on every block updated along the prefix. -/
theorem run_agree {a : AllocatorAgreement M} {K W : BlockSet}
    {p : Program} {c : Config M} {m : M}
    (h : ReplayAgreement a K W c.mem m)
    (hc : ∀ evs c', Steps p c evs c' → AccessesCovered K W evs) (fuel : Nat) :
    let (evs, c') := run p fuel c
    ∃ m', run p fuel (c.withMem m) = (evs, c'.withMem m') ∧
      ReplayAgreement a (updatedBlocks evs ++ K) W c'.mem m' := by
  induction fuel generalizing K c m with
  | zero => exact ⟨m, rfl, h⟩
  | succ fuel ih =>
    simp only [run]
    cases hs : step p c with
    | some r =>
      obtain ⟨es, c₁⟩ := r
      obtain ⟨m₁, hm₁, ha⟩ := step_agree hs h
        (by simpa using hc _ _ (Steps.head hs (.refl _)))
      rw [hm₁]
      have htail (fs : List Event) (c₂ : Config M) (ht : Steps p c₁ fs c₂) :
          AccessesCovered (updatedBlocks es ++ K) W fs := by
        intro e he
        have hmem := hc _ _ (.head hs ht) e (List.mem_append_right _ he)
        cases e with
        | read b => exact List.mem_append_right _ hmem
        | _ => exact hmem
      obtain ⟨m', hm', hr⟩ := ih ha htail
      refine ⟨m', by simp only [hm'], hr.restrict ?_⟩
      intro b hb
      simpa only [updated_append, List.mem_append, or_comm, or_left_comm, or_assoc]
        using hb
    | none =>
      cases c <;> first | contradiction | exact ⟨m, rfl, h⟩

/-- Agreement on the reads of an assertion makes its observation equal. -/
theorem assertionHolds_agree {p : Program} {env : Env} {m n : M}
    {e : Expr} {K W : BlockSet} (h : AgreeOn K m n)
    (hc : AccessesCovered K W (evalExpr p env m e).1) :
    assertionHolds p env n e = assertionHolds p env m e := by
  unfold assertionHolds
  rw [evalExpr_agree p env m n e (hc.reads h)]

end

end ReuseModel
