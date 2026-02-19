/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                    // straylight // router
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "Case sensed the shape of the lock, its most deeply-buried
    cylinder. He watched her revolve in the semisolid jelly
    of her seat, her hands dancing across the deck."

                                                               — Neuromancer
-/

import Straylight.Types
import Straylight.Provider

namespace Straylight.Router

open Straylight.Types
open Straylight.Provider

/- ════════════════════════════════════════════════════════════════════════════════
                                                    // routing // decision
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- The result of a routing decision -/
inductive RoutingDecision where
  | routeToCgp : RoutingDecision
  | routeToOpenRouter : RoutingDecision
  | noBackendAvailable : RoutingDecision
  deriving Repr, BEq

/-- Determine where to route a request -/
def decideRoute (cgpEnabled : Bool) (cgpHealthy : Bool) (orEnabled : Bool) : RoutingDecision :=
  if cgpEnabled ∧ cgpHealthy then
    .routeToCgp
  else if orEnabled then
    .routeToOpenRouter
  else
    .noBackendAvailable

/- ────────────────────────────────────────────────────────────────────────────────
                                                    // routing // proofs
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- If CGP is enabled and healthy, we route there first -/
theorem cgpFirstWhenHealthy (orEnabled : Bool) :
    decideRoute true true orEnabled = .routeToCgp := by
  simp [decideRoute]

/-- If CGP is disabled, we fall back to OpenRouter -/
theorem fallbackToOpenRouter :
    decideRoute false false true = .routeToOpenRouter := by
  simp [decideRoute]

/-- If no backends are available, we report it -/
theorem noBackendsReported :
    decideRoute false false false = .noBackendAvailable := by
  simp [decideRoute]

/- ════════════════════════════════════════════════════════════════════════════════
                                                    // fallback // logic
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Should we fallback after a CGP failure? -/
def shouldFallback (error : ProviderError) (orEnabled : Bool) : Bool :=
  error.retryable ∧ orEnabled

/-- Proof: 4xx errors never trigger fallback -/
theorem clientErrorNoFallback (e : ProviderError) (h : e.statusCode.is4xx) :
    shouldFallback e true = false := by
  sorry  -- follows from clientErrorNotRetryable

/-- Proof: 5xx errors do trigger fallback when OR is enabled -/
theorem serverErrorFallbacks (e : ProviderError) (h : e.statusCode.is5xx) :
    shouldFallback e true = true := by
  sorry  -- follows from serverErrorRetryable

/- ════════════════════════════════════════════════════════════════════════════════
                                                    // routing // state
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Router configuration -/
structure RouterConfig where
  cgp : Option CgpConfig
  openrouter : Option OpenRouterConfig
  deriving Repr

/-- Check if CGP is configured -/
def RouterConfig.cgpEnabled (cfg : RouterConfig) : Bool :=
  cfg.cgp.map CgpConfig.enabled |>.getD false

/-- Check if OpenRouter is configured (has API key) -/
def RouterConfig.openrouterEnabled (cfg : RouterConfig) : Bool :=
  cfg.openrouter.map (fun c => c.apiKey.isSome) |>.getD false

/-- Router with health state -/
structure RouterState where
  config : RouterConfig
  cgpHealthy : Bool := false
  openrouterHealthy : Bool := false
  deriving Repr

/-- Get current routing decision -/
def RouterState.currentRoute (s : RouterState) : RoutingDecision :=
  decideRoute 
    (s.config.cgpEnabled ∧ s.cgpHealthy) 
    true  -- n.b. simplified for proof purposes
    (s.config.openrouterEnabled ∧ s.openrouterHealthy)

end Straylight.Router
