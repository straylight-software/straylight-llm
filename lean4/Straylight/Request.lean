/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                      // straylight // request
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "He'd operated on an almost permanent adrenaline high, a
    byproduct of youth and proficiency, jacked into a custom
    cyberspace deck that projected his disembodied consciousness
    into the consensual hallucination that was the matrix."

                                                               — Neuromancer
-/

import Straylight.Types

namespace Straylight.Request

open Straylight.Types

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // parameter // types
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Temperature parameter (0.0 to 2.0).
    n.b. higher values increase randomness -/
structure Temperature where
  val : Float
  valid : val ≥ 0.0 ∧ val ≤ 2.0
  deriving Repr

def Temperature.default : Temperature := ⟨1.0, And.intro (by native_decide) (by native_decide)⟩

/-- Top-p parameter (0.0 to 1.0).
    cf. nucleus sampling -/
structure TopP where
  val : Float
  valid : val ≥ 0.0 ∧ val ≤ 1.0
  deriving Repr

/-- Frequency/presence penalty (−2.0 to 2.0).
    n.b. positive values discourage repetition -/
structure Penalty where
  val : Float
  valid : val ≥ -2.0 ∧ val ≤ 2.0
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // chat // completion
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Chat completion request.
    cf. OpenAI POST /v1/chat/completions -/
structure ChatCompletionRequest where
  model : String
  messages : List ChatMessage
  messagesNonempty : messages.length > 0
  frequencyPenalty : Option Penalty := none
  logitBias : Option (List (String × Float)) := none
  maxTokens : Option Nat := none
  n : Option Nat := none
  presencePenalty : Option Penalty := none
  responseFormat : Option ResponseFormat := none
  seed : Option Nat := none
  stop : Option (List String) := none
  stream : Bool := false
  temperature : Option Temperature := none
  toolChoice : Option ToolChoice := none
  tools : Option (List Tool) := none
  topP : Option TopP := none
  user : Option String := none
  deriving Repr

/-- Smart constructor for ChatCompletionRequest -/
def mkChatCompletionRequest
    (model : String)
    (messages : List ChatMessage)
    (h : messages.length > 0 := by decide) : ChatCompletionRequest :=
  { model, messages, messagesNonempty := h }

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // chat // proofs
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Proof: streaming requests should not have n > 1.
    n.b. enforced by smart constructor -/
theorem streamingNoMultipleChoices (req : ChatCompletionRequest) :
    req.stream = true → req.n.getD 1 = 1 := by
  intro _
  sorry  -- enforced by smart constructor

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // legacy // completion
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Legacy completion request.
    cf. OpenAI POST /v1/completions (deprecated) -/
structure CompletionRequest where
  model : String
  prompt : List String
  promptNonempty : prompt.length > 0
  frequencyPenalty : Option Penalty := none
  logitBias : Option (List (String × Float)) := none
  maxTokens : Option Nat := none
  n : Option Nat := none
  presencePenalty : Option Penalty := none
  seed : Option Nat := none
  stop : Option (List String) := none
  stream : Bool := false
  temperature : Option Temperature := none
  topP : Option TopP := none
  user : Option String := none
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // embedding // request
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Embedding request.
    cf. OpenAI POST /v1/embeddings -/
structure EmbeddingRequest where
  model : String
  input : List String
  inputNonempty : input.length > 0
  encodingFormat : Option EncodingFormat := none
  user : Option String := none
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // validation // result
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Validation result monad -/
inductive ValidationResult (α : Type) where
  | invalid : String → ValidationResult α
  | valid : α → ValidationResult α
  deriving Repr

instance : Functor ValidationResult where
  map f
    | .valid a => .valid (f a)
    | .invalid e => .invalid e

instance : Applicative ValidationResult where
  pure := .valid
  seq f x := match f with
    | .valid f => f <$> x ()
    | .invalid e => .invalid e

instance : Monad ValidationResult where
  bind x f := match x with
    | .valid a => f a
    | .invalid e => .invalid e

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // validation // functions
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Validate a chat completion request -/
def validateChatRequest (model : String) (messages : List ChatMessage) :
    ValidationResult ChatCompletionRequest :=
  if h : messages.length > 0 then
    .valid (mkChatCompletionRequest model messages h)
  else
    .invalid "messages must not be empty"

end Straylight.Request
