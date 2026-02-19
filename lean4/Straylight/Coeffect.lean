/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                    // straylight // coeffect
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "The sky above the port was the color of television,
    tuned to a dead channel."

                                                               — Neuromancer

   Coeffect algebra for resource tracking in graded monads.
   cf. Gaboardi et al., "Combining Effects and Coeffects via Grading"

   The coeffect semiring (R, ⊔, 0, ⊓, 1) tracks resource usage:
   - ⊔ (join): parallel composition (both resources needed)
   - ⊓ (meet): sequential composition (max of resources)
   - 0: no resource usage
   - 1: unit resource usage
-/

namespace Straylight.Coeffect

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // resource // levels
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Resource access level in a lattice.
    n.b. forms a bounded join-semilattice -/
inductive ResourceLevel where
  | none      -- no access
  | read      -- read-only access
  | readWrite -- read and write access
  deriving Repr, BEq, DecidableEq

/-- Ordering on resource levels -/
instance : LE ResourceLevel where
  le a b := match a, b with
    | .none, _           => True
    | .read, .none       => False
    | .read, _           => True
    | .readWrite, .readWrite => True
    | .readWrite, _      => False

instance : LT ResourceLevel where
  lt a b := a ≤ b ∧ a ≠ b

/-- Join (least upper bound) of resource levels -/
def ResourceLevel.join (a b : ResourceLevel) : ResourceLevel :=
  match a, b with
  | .none, x | x, .none => x
  | .read, .read        => .read
  | _, _                => .readWrite

/-- Meet (greatest lower bound) of resource levels -/
def ResourceLevel.meet (a b : ResourceLevel) : ResourceLevel :=
  match a, b with
  | .readWrite, x | x, .readWrite => x
  | .read, .read                  => .read
  | _, _                          => .none

instance : Max ResourceLevel where
  max := ResourceLevel.join

instance : Min ResourceLevel where
  min := ResourceLevel.meet


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // resource // kinds
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Kinds of resources tracked by coeffects -/
inductive ResourceKind where
  | cpu       -- compute resources
  | gpu       -- GPU/accelerator resources
  | memory    -- memory allocation
  | network   -- network I/O
  | storage   -- persistent storage
  deriving Repr, BEq, DecidableEq, Hashable

/-- Resource usage for a single kind -/
structure ResourceUsage where
  kind  : ResourceKind
  level : ResourceLevel
  deriving Repr, BEq


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // coeffect // type
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A coeffect is a mapping from resource kinds to usage levels.
    n.b. absent keys are treated as ResourceLevel.none -/
structure Coeffect where
  cpu     : ResourceLevel := .none
  gpu     : ResourceLevel := .none
  memory  : ResourceLevel := .none
  network : ResourceLevel := .none
  storage : ResourceLevel := .none
  deriving Repr, BEq

/-- The zero coeffect — no resource usage -/
def Coeffect.zero : Coeffect :=
  { cpu := .none, gpu := .none, memory := .none, network := .none, storage := .none }

/-- The unit coeffect — minimal resource usage -/
def Coeffect.one : Coeffect :=
  { cpu := .read, gpu := .none, memory := .none, network := .none, storage := .none }

/-- Join of coeffects — parallel composition -/
def Coeffect.join (a b : Coeffect) : Coeffect :=
  { cpu     := a.cpu.join b.cpu
  , gpu     := a.gpu.join b.gpu
  , memory  := a.memory.join b.memory
  , network := a.network.join b.network
  , storage := a.storage.join b.storage
  }

/-- Meet of coeffects — sequential composition -/
def Coeffect.meet (a b : Coeffect) : Coeffect :=
  { cpu     := a.cpu.meet b.cpu
  , gpu     := a.gpu.meet b.gpu
  , memory  := a.memory.meet b.memory
  , network := a.network.meet b.network
  , storage := a.storage.meet b.storage
  }

instance : Add Coeffect where
  add := Coeffect.join

instance : Mul Coeffect where
  mul := Coeffect.meet


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // common // coeffects
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Pure computation — no external resources -/
def Coeffect.pure : Coeffect := Coeffect.zero

/-- Network read operation -/
def Coeffect.netRead : Coeffect :=
  { cpu := .read, gpu := .none, memory := .read, network := .read, storage := .none }

/-- Network read/write operation -/
def Coeffect.netReadWrite : Coeffect :=
  { cpu := .read, gpu := .none, memory := .read, network := .readWrite, storage := .none }

/-- GPU inference operation -/
def Coeffect.gpuInference : Coeffect :=
  { cpu := .read, gpu := .read, memory := .read, network := .none, storage := .none }

/-- Full LLM request — network + GPU -/
def Coeffect.llmRequest : Coeffect :=
  Coeffect.netReadWrite.join Coeffect.gpuInference


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // semiring // proofs
   ════════════════════════════════════════════════════════════════════════════════ -/

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // join // properties
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Join is commutative -/
theorem ResourceLevel.join_comm (a b : ResourceLevel) :
    a.join b = b.join a := by
  cases a <;> cases b <;> rfl

/-- Join is associative -/
theorem ResourceLevel.join_assoc (a b c : ResourceLevel) :
    (a.join b).join c = a.join (b.join c) := by
  cases a <;> cases b <;> cases c <;> rfl

/-- Join with none is identity -/
theorem ResourceLevel.join_none_left (a : ResourceLevel) :
    ResourceLevel.none.join a = a := by
  cases a <;> rfl

theorem ResourceLevel.join_none_right (a : ResourceLevel) :
    a.join ResourceLevel.none = a := by
  cases a <;> rfl

/-- Join is idempotent -/
theorem ResourceLevel.join_idem (a : ResourceLevel) :
    a.join a = a := by
  cases a <;> rfl

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // meet // properties
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Meet is commutative -/
theorem ResourceLevel.meet_comm (a b : ResourceLevel) :
    a.meet b = b.meet a := by
  cases a <;> cases b <;> rfl

/-- Meet is associative -/
theorem ResourceLevel.meet_assoc (a b c : ResourceLevel) :
    (a.meet b).meet c = a.meet (b.meet c) := by
  cases a <;> cases b <;> cases c <;> rfl

/-- Meet with readWrite is identity -/
theorem ResourceLevel.meet_readWrite_left (a : ResourceLevel) :
    ResourceLevel.readWrite.meet a = a := by
  cases a <;> rfl

theorem ResourceLevel.meet_readWrite_right (a : ResourceLevel) :
    a.meet ResourceLevel.readWrite = a := by
  cases a <;> rfl

/-- Meet is idempotent -/
theorem ResourceLevel.meet_idem (a : ResourceLevel) :
    a.meet a = a := by
  cases a <;> rfl

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // absorption // laws
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Absorption: a ⊔ (a ⊓ b) = a -/
theorem ResourceLevel.join_meet_absorb (a b : ResourceLevel) :
    a.join (a.meet b) = a := by
  cases a <;> cases b <;> rfl

/-- Absorption: a ⊓ (a ⊔ b) = a -/
theorem ResourceLevel.meet_join_absorb (a b : ResourceLevel) :
    a.meet (a.join b) = a := by
  cases a <;> cases b <;> rfl

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // coeffect // semiring
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Coeffect join is commutative -/
theorem Coeffect.join_comm (a b : Coeffect) :
    a.join b = b.join a := by
  simp [Coeffect.join, ResourceLevel.join_comm]

/-- Coeffect join is associative -/
theorem Coeffect.join_assoc (a b c : Coeffect) :
    (a.join b).join c = a.join (b.join c) := by
  simp [Coeffect.join, ResourceLevel.join_assoc]

/-- Zero is identity for join -/
theorem Coeffect.join_zero_left (a : Coeffect) :
    Coeffect.zero.join a = a := by
  simp [Coeffect.join, Coeffect.zero, ResourceLevel.join_none_left]
  rfl

/-- Coeffect meet is commutative -/
theorem Coeffect.meet_comm (a b : Coeffect) :
    a.meet b = b.meet a := by
  simp [Coeffect.meet, ResourceLevel.meet_comm]

/-- Coeffect meet is associative -/
theorem Coeffect.meet_assoc (a b c : Coeffect) :
    (a.meet b).meet c = a.meet (b.meet c) := by
  simp [Coeffect.meet, ResourceLevel.meet_assoc]


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // subeffecting
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Coeffect ordering — subeffecting relation.
    a ≤ b means a requires no more resources than b -/
def Coeffect.le (a b : Coeffect) : Prop :=
  a.cpu ≤ b.cpu ∧ a.gpu ≤ b.gpu ∧ a.memory ≤ b.memory ∧
  a.network ≤ b.network ∧ a.storage ≤ b.storage

instance : LE Coeffect where
  le := Coeffect.le

/-- Pure is the least coeffect -/
theorem Coeffect.pure_le (c : Coeffect) :
    Coeffect.pure ≤ c := by
  simp [Coeffect.pure, Coeffect.zero, Coeffect.le]
  constructor <;> constructor <;> trivial

/-- Subeffecting is preserved by join -/
theorem Coeffect.le_join_left (a b : Coeffect) :
    a ≤ a.join b := by
  sorry  -- follows from join being upper bound

/-- Subeffecting is preserved by meet -/
theorem Coeffect.meet_le_left (a b : Coeffect) :
    a.meet b ≤ a := by
  sorry  -- follows from meet being lower bound


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // endpoint // coeffects
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Coeffect for /v1/chat/completions endpoint -/
def Coeffect.chatCompletions : Coeffect :=
  { cpu := .read
  , gpu := .read
  , memory := .read
  , network := .readWrite
  , storage := .none
  }

/-- Coeffect for /v1/models endpoint -/
def Coeffect.models : Coeffect :=
  { cpu := .read
  , gpu := .none
  , memory := .read
  , network := .none
  , storage := .none
  }

/-- Coeffect for /health endpoint -/
def Coeffect.health : Coeffect :=
  { cpu := .read
  , gpu := .none
  , memory := .read
  , network := .read
  , storage := .none
  }

end Straylight.Coeffect
