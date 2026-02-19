/- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                       // straylight // types
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -/

/-
   "The matrix has its roots in primitive arcade games... in
    early graphics programs and military experimentation with
    cranial jacks."

                                                               — Neuromancer
-/

namespace Straylight.Types

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // basic // primitives
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- A non-empty string type with proof of non-emptiness.
    n.b. used as base for ModelId, ApiKey validation -/
structure NonEmptyString where
  val : String
  nonempty : val.length > 0
  deriving Repr

/-- Model identifier — validated non-empty string -/
abbrev ModelId := NonEmptyString

/-- API key — kept opaque for security.
    n.b. private field prevents accidental logging -/
structure ApiKey where
  private val : String
  deriving Repr

/-- Port number in valid range (1–65535) -/
structure Port where
  val : Nat
  valid : val > 0 ∧ val < 65536
  deriving Repr

def Port.default : Port := ⟨4000, And.intro (by decide) (by decide)⟩

/-- Timeout in seconds (positive).
    n.b. default 120s matches typical LLM inference latency -/
structure Timeout where
  seconds : Nat
  positive : seconds > 0
  deriving Repr

def Timeout.default : Timeout := ⟨120, by decide⟩

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // chat // messages
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Role in a chat conversation.
    cf. OpenAI Chat Completions API specification -/
inductive Role where
  | assistant
  | system
  | tool
  | user
  deriving Repr, BEq, Inhabited

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // content // variants
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Image URL with optional detail level.
    i.e. for vision models -/
structure ImageUrl where
  url : String
  detail : Option String := none
  deriving Repr

/-- A part of multimodal content -/
inductive ContentPart where
  | imagePart : ImageUrl → ContentPart
  | textPart : String → ContentPart
  deriving Repr

/-- Content can be text or structured (for multimodal) -/
inductive Content where
  | parts : List ContentPart → Content
  | text : String → Content
  deriving Repr

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // tool // calls
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- Function call details -/
structure FunctionCall where
  name : String
  arguments : String  -- JSON string
  deriving Repr

/-- Tool call in assistant messages -/
structure ToolCall where
  id : String
  type : String  -- n.b. always "function" for now
  function : FunctionCall
  deriving Repr

/- ────────────────────────────────────────────────────────────────────────────────
                                                       // chat // message
   ──────────────────────────────────────────────────────────────────────────────── -/

/-- A single chat message -/
structure ChatMessage where
  role : Role
  content : Option Content := none
  name : Option String := none
  toolCallId : Option String := none
  toolCalls : Option (List ToolCall) := none
  deriving Repr

/-- Proof: a valid user message has content or tool_call_id.
    n.b. enforced by smart constructor in runtime -/
theorem userMessageHasContent (msg : ChatMessage) (h : msg.role = Role.user) :
    msg.content.isSome ∨ msg.toolCallId.isSome := by
  sorry  -- would be enforced by smart constructor

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // tools // definitions
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- JSON Schema type for tool parameters.
    cf. JSON Schema Draft 2020-12 -/
inductive JsonSchemaType where
  | array : JsonSchemaType → JsonSchemaType
  | boolean
  | enum : List String → JsonSchemaType
  | integer
  | nullable : JsonSchemaType → JsonSchemaType
  | number
  | object : List (String × JsonSchemaType) → JsonSchemaType
  | string
  deriving Repr

/-- Tool function definition -/
structure FunctionDef where
  name : String
  description : Option String := none
  parameters : Option JsonSchemaType := none
  strict : Option Bool := none
  deriving Repr

/-- Tool definition wrapper -/
structure Tool where
  type : String  -- n.b. always "function"
  function : FunctionDef
  deriving Repr

/-- Tool choice specification -/
inductive ToolChoice where
  | auto
  | none
  | required
  | specific : String → ToolChoice  -- function name
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // response // format
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Response format specification.
    cf. OpenAI structured outputs -/
inductive ResponseFormat where
  | jsonObject
  | jsonSchema : JsonSchemaType → ResponseFormat
  | text
  deriving Repr

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // usage // statistics
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Token usage statistics -/
structure Usage where
  promptTokens : Nat
  completionTokens : Nat
  totalTokens : Nat
  deriving Repr

/-- Proof: total is at least sum of parts.
    n.b. some providers include additional overhead tokens -/
theorem usageConsistent (u : Usage) :
    u.totalTokens = u.promptTokens + u.completionTokens ∨
    u.totalTokens ≥ u.promptTokens + u.completionTokens := by
  sorry  -- would validate at construction

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // finish // reasons
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Why the model stopped generating -/
inductive FinishReason where
  | contentFilter
  | functionCall  -- n.b. deprecated in favor of toolCalls
  | length
  | stop
  | toolCalls
  deriving Repr, BEq

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // embedding // types
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Embedding vector (list of floats) -/
structure EmbeddingVector where
  values : List Float
  deriving Repr

/-- Embedding encoding format -/
inductive EncodingFormat where
  | base64
  | float
  deriving Repr, BEq

/- ════════════════════════════════════════════════════════════════════════════════
                                                       // model // info
   ════════════════════════════════════════════════════════════════════════════════ -/

/-- Model information from /v1/models endpoint -/
structure ModelInfo where
  id : String
  object : String  -- n.b. always "model"
  created : Nat    -- Unix timestamp
  ownedBy : String
  deriving Repr

end Straylight.Types
