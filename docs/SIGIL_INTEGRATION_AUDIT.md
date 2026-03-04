━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                    // sigil // integration // audit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   "AI incentives are perversely trained... Your model providers do not have
    your best interests in mind... Its time we had access to 'Correct AI'..."

                                                                     — jpyxal

────────────────────────────────────────────────────────────────────────────────
                                                              // date // 2026-03-04
────────────────────────────────────────────────────────────────────────────────

# Goal

Achieve **p99.95 tool call hit rate** across all straylight products:
- strayforge
- converge
- omegacode
- compass
- foundry
- lattice

The gateway is the **single point of truth** for all LLM traffic. Every product
speaks SIGIL over ZMQ. No JSON anywhere inside the perimeter.

────────────────────────────────────────────────────────────────────────────────
                                                     // architecture // overview
────────────────────────────────────────────────────────────────────────────────

```
YOUR APPS (trusted)              GATEWAY                    VENDORS (adversarial)
════════════════════            ════════                    ════════════════════

omegacode ──┐                 ┌───────────────┐             ┌── OpenAI
compass ────┤                 │               │             ├── Anthropic
foundry ────┼── SIGIL/ZMQ ──▶│  DECODE       │── HTTP ────▶├── Vertex
strayforge ─┤                 │  ROUTE        │             ├── Baseten
converge ───┘                 │  OBSERVE      │             └── etc

omegacode ──┐                 │               │             ┌── OpenAI
compass ────┤                 │  PARSE garbage│◀── SSE ─────├── Anthropic
foundry ────┼── SIGIL/ZMQ ◀──│  VALIDATE     │   (jank)    ├── Vertex
strayforge ─┤                 │  ENCODE clean │             ├── Baseten
converge ───┘                 └───────────────┘             └── etc
```

**SIGIL protocol obligations:**
- Correct bytes only — no "close enough", no heuristics
- Ambiguity = RESET — connection torn down, logged, restarted clean
- Explicit failure modes — every error path is typed, handled, observable
- No silent anything — every anomaly surfaces in Parquet

────────────────────────────────────────────────────────────────────────────────
                                               // audit // sigil // encoder/decoder
────────────────────────────────────────────────────────────────────────────────

## Status: libevring/slide

| Component | Status | Blocking p99.95? |
|-----------|--------|------------------|
| Opcode encoding | ✅ Complete | No |
| Hot table | ✅ Complete | No |
| Varint encoding | ✅ Complete | No |
| Opcode decoding | ⚠️ Gaps | **Yes** — 0x7F, unknown bytes silently dropped |
| Reset-on-ambiguity | ⚠️ Partial | **Yes** — varint overflow treated as incomplete |
| Buffer handling | ⚠️ Gaps | Yes — leftover bytes on stream end not detected |
| Tool call wire format | ✅ Complete | No |
| Tool call JSON parsing | ⚠️ Gaps | **Yes** — no accumulation across SSE chunks |
| Tool call text detection | ❌ Missing | **Yes** — passthrough mode can't detect |
| Multi-token delimiters | ❌ Missing | **Yes** — `<tool_call>` may be multiple tokens |

## Critical Gaps

### GAP #1: Varint overflow handling

**Current:** Returns `Nothing`, caller buffers forever
**Required:** Emit `AmbiguityReset VarintOverflow` after 5+ continuation bytes

**Location:** `libevring/src/straylight/slide/src/Slide/Wire/Decode.hs:241-246`

```haskell
-- CURRENT (wrong)
| isExtendedByte currentByte =
    case decodeVarint remainingBytes of
        Nothing -> Left (BS.cons currentByte remainingBytes)  -- Buffers forever!

-- REQUIRED
| isExtendedByte currentByte =
    case decodeVarintWithOverflow remainingBytes of
        VarintIncomplete -> Left (BS.cons currentByte remainingBytes)
        VarintOverflow   -> Right (initDecodeState, Just (Chunk (AmbiguityReset VarintOverflow) True), remainingBytes)
        VarintOk (tokenId, consumed) -> ...
```

### GAP #2: Reserved byte 0x7F silently dropped

**Current:** Falls through all checks, silently dropped
**Required:** Emit `AmbiguityReset (ReservedOpcode 0x7F)`

**Location:** `libevring/src/straylight/slide/src/Slide/Wire/Decode.hs:250-252`

```haskell
-- CURRENT (wrong)
| otherwise =
    Right (state, Nothing, remainingBytes)  -- Silent drop!

-- REQUIRED
| currentByte == 0x7F =
    Right (initDecodeState, Just (Chunk (AmbiguityReset (ReservedOpcode 0x7F)) True), remainingBytes)
| otherwise =
    Right (initDecodeState, Just (Chunk (AmbiguityReset (ReservedOpcode currentByte)) True), remainingBytes)
```

### GAP #3: Leftover bytes on stream end

**Current:** `flushDecoder` only checks buffer, not leftover
**Required:** Check both

**Location:** `libevring/src/straylight/slide/src/Slide/Wire/Decode.hs:395-398`

```haskell
-- REQUIRED
finalizeDecoder :: DecodeState -> [Chunk]
finalizeDecoder state
    | not (BS.null (decodeLeftover state)) =
        [Chunk (DecodeError "Incomplete varint at stream end") True]
    | null (decodeBuffer state) = []
    | otherwise = [buildChunk state True]
```

### GAP #4: Tool call accumulation missing

**Current:** Each SSE chunk parsed independently, `EventToolCall` emitted per chunk
**Required:** Accumulate by `tcIndex`, emit only when complete

**Location:** `libevring/src/straylight/slide/src/Slide/Provider/OpenAI.hs:332-334`

────────────────────────────────────────────────────────────────────────────────
                                                // audit // gateway // integration
────────────────────────────────────────────────────────────────────────────────

## Status: gateway/src/Slide

| Component | Status |
|-----------|--------|
| Slide/Wire code | Duplicated (exact copy from libevring) |
| SIGIL encoding in streaming | ❌ **NOT WIRED** — raw SSE passthrough |
| ZMQ sockets | ❌ **Missing** — ZMTP parser exists, no bindings |
| SSE parsing | Uses Megaparsec, not fed into SIGIL encoder |

## Missing Components

### A. ZMQ Socket Layer

```
MISSING: gateway/src/Transport/Zmq.hs
- libzmq FFI bindings (or zeromq4-haskell package)
- ZmqContext, ZmqSocket types
- Publisher/Subscriber socket creation
- Connection management with io_uring integration
```

### B. Tokenizer Integration

```
MISSING: Real tokenizer (not identity tokenizer)
- Slide/Model.hs has modelTokenizer but uses stubTokenizer (identity)
- Need: HuggingFace tokenizers FFI (tokenizers-cpp)
- Or: Use libevring's Slide/Tokenizer.hs which has FFI
```

### C. SSE-to-SIGIL Bridge

```
MISSING: gateway/src/Streaming/SigilBridge.hs
- Take StreamCallback(raw bytes)
- Parse SSE via Slide/Parse.hs extractDelta
- Re-tokenize text via modelTokenizer
- Feed tokens through Slide/Chunk.processToken
- Emit SIGIL frames
```

### D. Publisher Integration

```
MISSING: Frame emission over ZMQ PUB socket
- Wire Slide.Wire.Frame output to ZMQ socket
- Topic-based routing (per-request-id or per-model)
- Back-pressure handling
```

────────────────────────────────────────────────────────────────────────────────
                                                  // audit // vendor // sse // parsers
────────────────────────────────────────────────────────────────────────────────

## Tool Call Support by Vendor

| Vendor | Tool Call Status | Risk Level |
|--------|------------------|------------|
| **Vertex/Anthropic (slide)** | ❌ **MISSING ENTIRELY** | **CRITICAL** |
| **Gateway Anthropic** | ❌ `InputJsonDelta` discarded | HIGH |
| **Slide OpenAI** | ⚠️ Extracts but no accumulation | MODERATE |
| **Slide OpenRouter** | ⚠️ Extracts but no accumulation | MODERATE |
| **Gateway raw-byte providers** | Delegated to caller | LOW |

## Critical Failures

### CRITICAL: Vertex/Anthropic — 100% tool call failure

**Location:** `libevring/src/straylight/slide/src/Slide/Provider/Vertex/Anthropic.hs`

```haskell
-- CURRENT (wrong)
handleSSEEvent onEvent _onFinish sseEvent = case sseEvent of
    SSEData jsonContent ->
        case extractAnthropicDelta jsonContent of
            Just content -> onEvent (EventContent content)
            Nothing -> pure ()  -- ← Tool calls silently discarded!
    _ -> pure ()
```

**Required:**
- Handle `content_block_start` with `tool_use` type
- Handle `input_json_delta` for partial tool JSON
- Accumulate tool call state across events

### HIGH: Gateway Anthropic — tool calls discarded

**Location:** `gateway/src/Provider/Anthropic.hs:648-649`

```haskell
-- CURRENT (wrong)
A.InputJsonDelta _partial ->
    pure ()  -- ← Partial tool JSON discarded!
```

**Required:**
- Write to `_toolCallsRef` IORef
- Accumulate partial JSON by tool index
- Emit complete tool calls

### MODERATE: JSON chunk boundary splits

**Location:** `libevring/src/straylight/slide/src/Slide/Parse.hs`

If JSON key is split mid-token (e.g., `"tool_ca` | `lls"`), parser fails silently.
At p99.95 with pathological network conditions, this will happen.

**Required:**
- Buffer until valid JSON
- Or: stream-aware JSON parser

────────────────────────────────────────────────────────────────────────────────
                                                    // audit // parquet // analytics
────────────────────────────────────────────────────────────────────────────────

## Status: No Parquet sink exists

| Question | Answer |
|----------|--------|
| Parquet sink exists? | **No** |
| AmbiguityReset logged? | **No** |
| Per-frame observability? | **No** |
| Tool call failure query? | **No** |

## Required Schema

```
sigil_frames (Parquet table)
├── timestamp: TIMESTAMP
├── request_id: STRING
├── vendor: STRING
├── model: STRING
├── frame_type: ENUM (text, think, tool_call, code_block, stream_end, error, reset)
├── frame_index: INT32
├── token_count: INT32
├── raw_bytes: BINARY (optional)
├── is_complete: BOOLEAN
├── ambiguity_reason: STRING (null if not reset)
├── tool_call_valid_json: BOOLEAN (null if not tool_call)
├── tool_call_parse_error: STRING (null if valid)
```

## Required Queries

```sql
-- Tool call failures by vendor/model
SELECT vendor, model, COUNT(*) as failures
FROM sigil_frames
WHERE frame_type = 'tool_call'
  AND tool_call_valid_json = false
GROUP BY vendor, model
ORDER BY failures DESC;

-- Ambiguity resets by reason
SELECT ambiguity_reason, vendor, COUNT(*) as resets
FROM sigil_frames
WHERE frame_type = 'reset'
GROUP BY ambiguity_reason, vendor;
```

────────────────────────────────────────────────────────────────────────────────
                                                      // audit // omegacode // client
────────────────────────────────────────────────────────────────────────────────

## Status: No SIGIL/ZMQ client

| Question | Answer |
|----------|--------|
| ZMQ client? | **No** |
| SIGIL decoding? | **No** |
| Current transport | SSE/JSON via EventSource |
| Migration complexity | Medium |
| Where to add ZMQ? | Electron main process |

## Migration Path

```
Phase 1: Add ZMQ to Electron main process
─────────────────────────────────────────
electron/zmq.js (new)
  - require('zeromq') — ZMQ SUB socket
  - Connect to gateway SIGIL endpoint
  - Receive raw binary frames

electron/ipc.js
  - Add handler: ipcMain.on('zmq:subscribe', ...)
  - Forward frames: webContents.send('zmq:frame', buffer)

electron/preload.js
  - Expose: onZmqFrame(callback), zmqSubscribe(endpoint)

Phase 2: SIGIL frame decoder
────────────────────────────
lib/src/Weapon/Sigil.js (new FFI)
  - Parse SIGIL wire format
  - Return structured frame object

lib/src/Weapon/Sigil.purs (new)
  - foreign import decodeSigilFrame :: ArrayBuffer -> Effect (Either String Frame)

Phase 3: Replace WebSocket module
─────────────────────────────────
lib/src/Weapon/WebSocket.purs
  - Same interface, ZMQ internals
  - connect → zmqSubscribe
  - subscribe → onZmqFrame → decodeSigilFrame → handler

Phase 4: Update app integration
───────────────────────────────
src/WeaponUI/App/State.purs
  - Rename eventSource to zmqConnection

src/WeaponUI/App.purs
  - No changes if interface stays same
```

────────────────────────────────────────────────────────────────────────────────
                                                         // todo // critical // path
────────────────────────────────────────────────────────────────────────────────

## Must Fix (blocking correctness)

- [ ] **SIGIL-001**: Varint overflow — emit AmbiguityReset, not buffer forever
- [ ] **SIGIL-002**: 0x7F / unknown bytes — emit AmbiguityReset, not silent drop
- [ ] **SIGIL-003**: Leftover bytes on stream end — detect and error
- [ ] **VENDOR-001**: Vertex/Anthropic tool calls — implement content_block_start + input_json_delta
- [ ] **VENDOR-002**: Gateway Anthropic — wire up _toolCallsRef accumulation
- [ ] **VENDOR-003**: Tool call accumulation — track by index, concatenate args across chunks

## Must Build (missing infrastructure)

- [ ] **INFRA-001**: ZMQ socket layer in gateway (zeromq4-haskell)
- [ ] **INFRA-002**: SSE→SIGIL bridge (parse→tokenize→encode)
- [ ] **INFRA-003**: Real tokenizer integration (not identity stub)
- [ ] **INFRA-004**: Parquet sink for frame-level analytics
- [ ] **INFRA-005**: omegacode ZMQ client (Electron main process)
- [ ] **INFRA-006**: omegacode SIGIL decoder (PureScript FFI)

## Should Fix (robustness)

- [ ] **ROBUST-001**: JSON boundary-aware buffering in extractToolCalls
- [ ] **ROBUST-002**: Multi-token delimiter detection for passthrough
- [ ] **ROBUST-003**: OP_ERROR (0xCE) handling in decoder
- [ ] **ROBUST-004**: Deduplicate Slide/Wire code (gateway vs libevring)

────────────────────────────────────────────────────────────────────────────────
                                                              // priority // matrix
────────────────────────────────────────────────────────────────────────────────

| Priority | Item | Impact | Effort |
|----------|------|--------|--------|
| P0 | VENDOR-001 (Vertex/Anthropic) | 100% failure → 0% | 1 day |
| P0 | VENDOR-002 (Gateway Anthropic) | HIGH failure rate | 0.5 day |
| P0 | SIGIL-001 (varint overflow) | Stall on malformed | 0.5 day |
| P1 | SIGIL-002 (0x7F handling) | Silent corruption | 0.5 day |
| P1 | VENDOR-003 (accumulation) | Partial tool calls | 1 day |
| P1 | INFRA-001 (ZMQ sockets) | Blocks all ZMQ | 1 day |
| P1 | INFRA-002 (SSE→SIGIL) | Blocks SIGIL emit | 1 day |
| P2 | INFRA-004 (Parquet) | No observability | 2 days |
| P2 | INFRA-005 (omegacode ZMQ) | Client migration | 2 days |
| P3 | ROBUST-001 (JSON buffering) | Edge case failures | 1 day |
| P3 | ROBUST-004 (dedupe code) | Tech debt | 0.5 day |

────────────────────────────────────────────────────────────────────────────────

                                                                — b7r6 // 2026-03-04

