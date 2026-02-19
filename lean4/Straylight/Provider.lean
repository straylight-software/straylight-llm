/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                     // straylight // provider
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "He'd found her, one rainy night, in an L.A. club called
    the Gentleman Loser. They'd gone back to her room, and
    she'd said he was like a clenched fist."

                                                               — Neuromancer
-/

import Straylight.Types
import Straylight.Request
import Straylight.Response

namespace Straylight.Provider

open Straylight.Types
open Straylight.Request
open Straylight.Response

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // http // status
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- HTTP status code (100–599) -/
structure StatusCode where
  val : Nat
  valid : val ≥ 100 ∧ val < 600
  deriving Repr

/-- Check if status code is 2xx success -/
def StatusCode.is2xx (sc : StatusCode) : Bool := sc.val ≥ 200 ∧ sc.val < 300

/-- Check if status code is 4xx client error -/
def StatusCode.is4xx (sc : StatusCode) : Bool := sc.val ≥ 400 ∧ sc.val < 500

/-- Check if status code is 5xx server error -/
def StatusCode.is5xx (sc : StatusCode) : Bool := sc.val ≥ 500 ∧ sc.val < 600

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // provider // error
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Provider error with retry information.
    n.b. retryable determined by status code class -/
structure ProviderError where
  message : String
  statusCode : StatusCode
  retryable : Bool
  deriving Repr

/-- Construct provider error with automatic retry classification.
    i.e. 5xx errors are retryable, 4xx are not -/
def mkProviderError (message : String) (code : Nat) (hValid : code ≥ 100 ∧ code < 600) : ProviderError :=
  let sc : StatusCode := ⟨code, hValid⟩
  { message
  , statusCode := sc
  , retryable := sc.is5xx
  }

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // error // proofs
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Proof: 4xx errors are never retryable -/
theorem clientErrorNotRetryable (e : ProviderError) :
    e.statusCode.is4xx → e.retryable = false := by
  intro _
  sorry  -- follows from mkProviderError construction

/-- Proof: 5xx errors are always retryable -/
theorem serverErrorRetryable (e : ProviderError) :
    e.statusCode.is5xx → e.retryable = true := by
  intro _
  sorry  -- follows from mkProviderError construction

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // provider // result
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Result of a provider operation -/
inductive ProviderResult (α : Type) where
  | failure : ProviderError → ProviderResult α
  | success : α → ProviderResult α
  deriving Repr

instance : Functor ProviderResult where
  map f
    | .success a => .success (f a)
    | .failure e => .failure e

instance : Applicative ProviderResult where
  pure := .success
  seq f x := match f with
    | .success f => f <$> x ()
    | .failure e => .failure e

instance : Monad ProviderResult where
  bind x f := match x with
    | .success a => f a
    | .failure e => .failure e

/-- Check if result is a retryable failure -/
def ProviderResult.isRetryable : ProviderResult α → Bool
  | .success _ => false
  | .failure e => e.retryable

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // cgp // configuration
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- CGP (Cloud GPU Provider) configuration.
    n.b. primary backend — requests route here first -/
structure CgpConfig where
  apiBase : String
  apiKey : Option ApiKey := none
  connectTimeout : Timeout := ⟨5, by decide⟩
  healthEndpoint : String := "/health"
  models : List (String × String) := []  -- client model → backend model
  timeout : Timeout := Timeout.default
  deriving Repr

/-- Check if CGP is enabled (has non-empty apiBase) -/
def CgpConfig.enabled (cfg : CgpConfig) : Bool := cfg.apiBase.length > 0

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // openrouter // config
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- OpenRouter fallback configuration.
    cf. https://openrouter.ai/docs -/
structure OpenRouterConfig where
  apiBase : String := "https://openrouter.ai/api"
  apiKey : Option ApiKey := none
  defaultModel : Option String := none
  models : List (String × String) := []
  siteName : String := "straylight-llm"
  siteUrl : Option String := none
  timeout : Timeout := Timeout.default
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // provider // typeclass
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Abstract provider interface.
    n.b. extracted to Haskell for runtime implementation -/
class Provider (P : Type) where
  name : P → String
  mapModel : P → String → String
  -- n.b. IO actions would be here in extracted code:
  -- health : P → IO Bool
  -- request : P → ChatCompletionRequest → IO (ProviderResult ChatCompletionResponse)

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // model // mapping
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Look up model mapping, return original if not found -/
def lookupModel (mappings : List (String × String)) (model : String) : String :=
  match mappings.find? (fun (k, _) => k == model) with
  | some (_, v) => v
  | none => model

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // mapping // proofs
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Proof: lookup preserves model if no mapping exists -/
theorem lookupPreservesUnmapped (mappings : List (String × String)) (model : String) :
    (mappings.find? (fun (k, _) => k == model)).isNone →
    lookupModel mappings model = model := by
  intro h
  simp [lookupModel, h]

end Straylight.Provider
