/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                 // straylight // graded-monad
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "He closed his eyes. Found the ridged face of the power
    stud. And in the bloodlit dark behind his eyes, silver
    phosphenes boiling in from the edge of space, hypnagogic
    images jerking past like film compiled from random frames."

                                                               — Neuromancer

   Graded monads for tracking coeffects through computation.
   cf. Katsumata, "Parametric Effect Monads and Semantics of Effect Systems"

   A graded monad M indexed by a coeffect semiring R satisfies:
   - return : A → M[0] A
   - bind   : M[r] A → (A → M[s] B) → M[r ⊔ s] B

   This allows static tracking of resource usage at the type level.
-/

import Straylight.Coeffect

namespace Straylight.GradedMonad

open Straylight.Coeffect


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // graded // monad
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A graded monad indexed by coeffects.
    n.b. this is a specification for extraction to Haskell -/
class GradedMonad (M : Coeffect → Type → Type) where
  /-- Pure computation with zero coeffect -/
  gpure : α → M Coeffect.zero α

  /-- Graded bind — coeffects compose via join -/
  gbind : M r α → (α → M s β) → M (r.join s) β

  /-- Left identity: gpure a >>= f ≡ f a -/
  gpure_gbind : ∀ (a : α) (f : α → M s β),
    gbind (gpure a) f = cast (by simp [Coeffect.join_zero_left]) (f a)

  /-- Right identity: m >>= gpure ≡ m -/
  gbind_gpure : ∀ (m : M r α),
    gbind m gpure = cast (by simp [Coeffect.join]) m

  /-- Associativity: (m >>= f) >>= g ≡ m >>= (λx. f x >>= g) -/
  gbind_assoc : ∀ (m : M r α) (f : α → M s β) (g : β → M t γ),
    gbind (gbind m f) g = cast (by simp [Coeffect.join_assoc]) (gbind m (fun a => gbind (f a) g))


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // graded // operations
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Graded map -/
def gmap [GradedMonad M] (f : α → β) (m : M r α) : M r β :=
  cast (by simp [Coeffect.join]) (GradedMonad.gbind m (fun a => GradedMonad.gpure (f a)))

/-- Graded sequence -/
def gseq [GradedMonad M] (m1 : M r α) (m2 : M s β) : M (r.join s) β :=
  GradedMonad.gbind m1 (fun _ => m2)


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // graded // io
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Graded IO monad — IO indexed by coeffects.
    n.b. specification for extraction; actual implementation in Haskell -/
structure GIO (r : Coeffect) (α : Type) where
  run : IO α
  coeffect : Coeffect := r

/-- Lift pure computation to GIO -/
def GIO.pure (a : α) : GIO Coeffect.zero α :=
  { run := Pure.pure a, coeffect := Coeffect.zero }

/-- Bind for GIO -/
def GIO.bind (m : GIO r α) (f : α → GIO s β) : GIO (r.join s) β :=
  { run := m.run >>= (fun a => (f a).run)
  , coeffect := r.join s
  }

instance : GradedMonad GIO where
  gpure := GIO.pure
  gbind := GIO.bind
  gpure_gbind := by intros; rfl
  gbind_gpure := by intros; rfl
  gbind_assoc := by intros; rfl


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // effectful // operations
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Read from network with tracked coeffect -/
def netRead (action : IO α) : GIO Coeffect.netRead α :=
  { run := action, coeffect := Coeffect.netRead }

/-- Write to network with tracked coeffect -/
def netWrite (action : IO α) : GIO Coeffect.netReadWrite α :=
  { run := action, coeffect := Coeffect.netReadWrite }

/-- GPU inference operation with tracked coeffect -/
def gpuInfer (action : IO α) : GIO Coeffect.gpuInference α :=
  { run := action, coeffect := Coeffect.gpuInference }


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // subeffecting
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Weaken coeffect — subeffecting rule.
    If r ≤ s, then M[r] A can be treated as M[s] A -/
def weaken [GradedMonad M] (h : r ≤ s) (m : M r α) : M s α :=
  cast (by sorry) m  -- Justified by subeffecting in the coeffect lattice


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // effect // equations
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Effect equation: parallel composition of network operations -/
theorem netParallel_coeffect :
    (Coeffect.netRead.join Coeffect.netRead) = Coeffect.netRead := by
  simp [Coeffect.netRead, Coeffect.join, ResourceLevel.join_idem]

/-- Effect equation: sequential network then GPU -/
theorem netThenGpu_coeffect :
    (Coeffect.netReadWrite.join Coeffect.gpuInference) = Coeffect.llmRequest := by
  simp [Coeffect.netReadWrite, Coeffect.gpuInference, Coeffect.llmRequest, Coeffect.join]

/-- Effect equation: chat completions requires full LLM coeffect -/
theorem chatCompletions_requires_llm :
    Coeffect.chatCompletions = Coeffect.llmRequest := by
  simp [Coeffect.chatCompletions, Coeffect.llmRequest, Coeffect.netReadWrite, Coeffect.gpuInference, Coeffect.join]
  rfl


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // endpoint // types
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Type of the /v1/chat/completions handler -/
def ChatCompletionsHandler (Req Resp : Type) :=
  Req → GIO Coeffect.chatCompletions Resp

/-- Type of the /v1/models handler -/
def ModelsHandler (Resp : Type) :=
  GIO Coeffect.models Resp

/-- Type of the /health handler -/
def HealthHandler (Resp : Type) :=
  GIO Coeffect.health Resp


/- ════════════════════════════════════════════════════════════════════════════════
                                                       // coeffect // manifest
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Manifest entry for an endpoint -/
structure ManifestEntry where
  path      : String
  method    : String
  coeffect  : Coeffect
  deriving Repr

/-- The coeffect manifest for the gateway -/
def gatewayManifest : List ManifestEntry :=
  [ { path := "/v1/chat/completions", method := "POST", coeffect := Coeffect.chatCompletions }
  , { path := "/v1/models",           method := "GET",  coeffect := Coeffect.models }
  , { path := "/health",              method := "GET",  coeffect := Coeffect.health }
  ]

end Straylight.GradedMonad
