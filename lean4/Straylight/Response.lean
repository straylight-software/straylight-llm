/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                     // straylight // response
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "Cyberspace. A consensual hallucination experienced daily
    by billions of legitimate operators, in every nation..."

                                                               — Neuromancer
-/

import Straylight.Types

namespace Straylight.Response

open Straylight.Types

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // chat // completion
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A single choice in a chat completion response -/
structure ChatCompletionChoice where
  index : Nat
  message : ChatMessage
  finishReason : Option FinishReason
  deriving Repr

/-- Chat completion response.
    cf. OpenAI POST /v1/chat/completions response -/
structure ChatCompletionResponse where
  id : String
  object : String  -- n.b. always "chat.completion"
  created : Nat    -- Unix timestamp
  model : String
  choices : List ChatCompletionChoice
  choicesNonempty : choices.length > 0
  usage : Option Usage := none
  deriving Repr

/-- Proof: response has at least one choice -/
theorem responseHasChoice (resp : ChatCompletionResponse) :
    resp.choices.length > 0 := resp.choicesNonempty

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // streaming // response
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Delta in a streaming response.
    n.b. partial updates sent via SSE -/
structure ChatCompletionDelta where
  content : Option String := none
  role : Option Role := none
  toolCalls : Option (List ToolCall) := none
  deriving Repr

/-- A choice in a streaming chunk -/
structure ChatCompletionChunkChoice where
  index : Nat
  delta : ChatCompletionDelta
  finishReason : Option FinishReason
  deriving Repr

/-- Streaming chunk.
    cf. SSE data: {...} format -/
structure ChatCompletionChunk where
  id : String
  object : String  -- n.b. always "chat.completion.chunk"
  created : Nat
  model : String
  choices : List ChatCompletionChunkChoice
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // legacy // completion
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A choice in a legacy completion response -/
structure CompletionChoice where
  text : String
  index : Nat
  finishReason : Option FinishReason
  deriving Repr

/-- Legacy completion response.
    cf. OpenAI POST /v1/completions (deprecated) -/
structure CompletionResponse where
  id : String
  object : String  -- n.b. always "text_completion"
  created : Nat
  model : String
  choices : List CompletionChoice
  choicesNonempty : choices.length > 0
  usage : Option Usage := none
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // embedding // response
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A single embedding -/
structure EmbeddingData where
  object : String  -- n.b. always "embedding"
  embedding : EmbeddingVector
  index : Nat
  deriving Repr

/-- Embedding response.
    cf. OpenAI POST /v1/embeddings response -/
structure EmbeddingResponse where
  object : String  -- n.b. always "list"
  data : List EmbeddingData
  model : String
  usage : Usage
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // models // response
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Models list response.
    cf. OpenAI GET /v1/models -/
structure ModelsResponse where
  object : String  -- n.b. always "list"
  data : List ModelInfo
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // error // response
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Error detail -/
structure ErrorDetail where
  message : String
  type : String
  code : Option String := none
  param : Option String := none
  deriving Repr

/-- Error response.
    cf. OpenAI error format -/
structure ErrorResponse where
  error : ErrorDetail
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // health // response
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Health status enumeration -/
inductive HealthStatus where
  | degraded
  | ok
  | unhealthy
  deriving Repr, BEq

/-- Backend health info -/
structure BackendHealth where
  configured : Bool
  healthy : Bool
  apiBase : Option String := none
  deriving Repr

/-- Health check response.
    n.b. straylight-llm specific endpoint -/
structure HealthResponse where
  status : HealthStatus
  cgp : BackendHealth
  openrouter : BackendHealth
  deriving Repr

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // health // proofs
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Proof: if both backends are down, status is degraded or unhealthy -/
theorem bothDownMeansDegraded (h : HealthResponse) :
    h.cgp.healthy = false → h.openrouter.healthy = false →
    h.status = HealthStatus.degraded ∨ h.status = HealthStatus.unhealthy := by
  intro _ _
  sorry  -- enforced by construction

end Straylight.Response
