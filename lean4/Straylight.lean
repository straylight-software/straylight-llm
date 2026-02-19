/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                            // straylight //
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   Straylight LLM — CGP-first OpenAI Gateway with Verified Types

   System F Omega types for OpenAI API with proofs of correctness.
   Graded monads with coeffect equations track resource usage.
   Types are extracted to Haskell for the runtime implementation.

   cf. Gaboardi et al., "Combining Effects and Coeffects via Grading"
   cf. Katsumata, "Parametric Effect Monads and Semantics of Effect Systems"
-/

-- // core // types
import Straylight.Types
import Straylight.Request
import Straylight.Response

-- // provider // abstraction
import Straylight.Provider
import Straylight.Router

-- // graded // monads
import Straylight.Coeffect
import Straylight.GradedMonad
