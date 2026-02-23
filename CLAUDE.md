# CLAUDE.md — straylight-llm

> "The sky above the port was the color of television, tuned to a dead channel."

## What We're Building

**straylight-llm** is being transformed from a basic LLM proxy into a fully compliant **aleph cube architecture** implementation — a formally verified, effect-tracked, coeffect-discharged gateway with Lean4 proofs.

This is not just "make the API work." This is:
- **Proof-carrying code**: Lean4 theorems that the cache is correct, builds are hermetic, attestations are sound
- **Effect systems**: No raw IO in business logic — tracked, testable, mockable
- **Coeffect tracking**: Every network call, auth usage, filesystem access is declared and discharged
- **Property testing**: Hedgehog + haskemathesis generating realistic test data from OpenAPI schemas
- **No partial functions**: Zero `read`, `head`, `tail`, `fromJust`, `unsafePerformIO`, `SomeException`
- **No stringly-typed garbage**: Proper ADTs, not Aeson `Value`

## The Reference Spec

The architecture is defined in `aleph-reference/src/examples/lean-continuity/Continuity.lean` (923 lines of Lean4). Key concepts:

1. **The Coset**: Equivalence class of toolchains that produce identical builds. Cache key = coset, not toolchain hash.
2. **Hermetic Builds**: `IsHermetic inputs accessed := accessed ⊆ inputs`
3. **Discharge Proofs**: Cryptographically signed proofs that all coeffects were satisfied
4. **No Globs, No Strings**: Dhall typed configs, explicit file lists, typed flags (not `-O2` strings)

## Current State

**Build:** Passing (GHC 9.12.2)  
**Tests:** 213/213 passing (property + integration + adversarial + formal)  
**COMPASS Target:** 135+ tests — **EXCEEDED**
**Live Testing:** Venice AI integration verified working

### Completed (Phase 1 - Type Safety)
- GHC 9.12 upgrade (flake.nix, package.nix) — StrictData by default
- Architecture documentation (`docs/ARCHITECTURE.md`) with full gap analysis
- Config.hs: `read` → `readMaybe`, `SomeException` → `IOException`
- Provider/Venice.hs: `SomeException` → `HttpException`
- Provider/Baseten.hs: `SomeException` → `HttpException`
- Provider/OpenRouter.hs: `SomeException` → `HttpException`
- Provider/Vertex.hs: `SomeException` → `HttpException`/`IOException`, **401 cache invalidation bug fixed**
- Provider/ModelRegistry.hs: `SomeException` → `IOException`, **async startup with timeout**
- All nix builds working: `.#straylight-llm`, `.#basic`, `.#with-cgp`
- **Types.hs: All 9 `Value` fields replaced with proper ADTs**

### Completed (Phase 2 - Effect System)
- `GatewayM` graded monad in `Effects/Graded.hs`
- All providers updated to use `GatewayM` instead of raw `IO`
- Effect tracking: HTTP, Config, Log, Crypto

### Completed (Phase 3 - Discharge Proofs)
- `Coeffect/Types.hs`: Coeffect, NetworkAccess, FilesystemAccess, AuthUsage, DischargeProof
- `Coeffect/Discharge.hs`: ed25519 signing, SHA256 hashing, proof generation
- Router generates discharge proofs after each request
- `/v1/proof/:requestId` API endpoint to retrieve proofs

### Completed (Phase 4 - Property Tests)
- **213 tests total** (hedgehog property + integration + adversarial + formal)
- Property tests: Types roundtrip (41), Coeffect (12), Graded Monad (11), Security, Streaming (21)
- Integration tests: API (5), Proof (1), Lifecycle (11), OpenAPI spec
- Adversarial tests: Race conditions (9), Injection edge cases (22), Provider errors (29)
- Formal tests: Proof correspondence (9) — Haskell ↔ Lean4 verification

### Completed (Phase 5 - Lean4 Proofs)
- `proofs/Straylight/Coeffect.lean` (305 lines): Coeffect monoid, tensor product, discharge laws
- `proofs/Straylight/Gateway.lean` (376 lines): Provider types, fallback termination, retry bounds
- `proofs/Straylight/Hermetic.lean` (223 lines): Hermeticity guarantees, cache isolation
- **No `sorry`, no `axiom` escapes** — all proofs complete

### Completed (Phase 6 - Partial)
- **Dhall BUILD files** (complete + Nix integration):
  - `dhall/Target.dhall` — Typed targets (GhcVersion, OptLevel, Extension ADTs)
  - `dhall/Platform.dhall` — Toolchain definitions
  - `dhall/Build.dhall` — Build script generation
  - `dhall/Action.dhall` — DICE-style incremental computation actions
  - `dhall/straylight-llm.dhall` — Gateway target with explicit 38-file manifest
  - `nix/modules/dhall-build.nix` — Nix integration (verify manifest, export JSON)
  - `nix build .#dhall-verify` — Verifies all declared source files exist
  - `nix build .#dhall-config` — Exports typed config to JSON
- **PureScript/Halogen frontend** (partial):
  - `App.purs` — Main app shell with tab navigation (Health/Models/Proofs)
  - `API/Client.purs` — Full type definitions, API client
  - `Components/HealthStatus.purs` — Basic status cards
  - `Components/ModelsPanel.purs` — Model listing
  - `Components/ProofViewer.purs` — Basic proof display
  - `themes.css` — 14 themes
  - `src-tauri/` — Tauri desktop builds (deb/appimage)
- **Evring state machine** (complete):
  - `Evring/Event.hs`, `Handle.hs`, `Machine.hs`, `Ring.hs`, `Sigil.hs`, `Trace.hs`
  - Deterministic trace recording/replay for testing
- **Slide wire protocol** (partial):
  - `Slide/Parse.hs` — Uses `reads` (better than production)
  - `Slide/Wire/Types.hs`, `Slide/Wire/Varint.hs`
- **Resilience** (complete):
  - `Resilience/Cache.hs`, `CircuitBreaker.hs`, `Retry.hs`, `Backpressure.hs`, `Metrics.hs`
- **Security** (complete):
  - `Security/ConstantTime.hs`, `PromptInjection.hs`, `RequestLimits.hs`
  - `Security/RequestSanitization.hs`, `ResponseSanitization.hs`, `ObservabilitySanitization.hs`
- **Streaming SSE** (complete):
  - `POST /v1/chat/completions/stream` endpoint
  - WAI `responseStream` with `text/event-stream`
  - OpenAI-compatible format with `[DONE]` marker
- **Real-time SSE Events** (complete):
  - `Streaming/Events.hs` — Event broadcaster using STM broadcast channels
  - `GET /v1/events` — SSE endpoint subscribes to broadcaster
  - Event types: `request.started`, `request.completed`, `proof.generated`, `provider.status`, `keepalive`
  - Circuit breaker state change notifications emitted on provider.status
  - All request routes (chat, stream, embeddings, models) emit events

### Remaining (Phase 6 - Frontend)
- Provider Status Dashboard (real-time provider health, circuit breaker visualization) — **backend SSE ready**
- Request/Response Timeline (chronological view with filtering) — **backend SSE ready**
- ~~WebSocket/SSE real-time updates~~ **backend complete, frontend pending**
- Coeffect Graph Visualization (DAG of coeffect relationships)
- Enhanced Proof Inspector (signature verification, hash verification)
- Metrics Dashboard (token usage, latency, cache performance)

### Completed (Phase 7 - Performance Benchmarks)
- **Criterion benchmark suite** (`gateway/bench/`):
  - `bench/Main.hs` — Benchmark entry point
  - `bench/Bench/Router.hs` — Request ID generation, proof cache operations
  - `bench/Bench/CircuitBreaker.hs` — State checks, transitions, concurrent access
  - `bench/Bench/SSEBroadcaster.hs` — Event encoding, broadcast latency, subscriber scaling
  - `bench/Bench/Coeffect.hs` — Combination, serialization, hashing, proof generation
- **Key results** (GHC 9.12.2, -O2):
  - Request ID generation: **407ns** (single), 41μs (100)
  - Circuit breaker state check: **7.8ns** (closed), 7.7ns (open)
  - Circuit breaker getStats: **12.5ns**
  - withCircuitBreaker success: **85.5ns**
  - withCircuitBreaker open/fast-fail: **86.5ns**
  - SSE event encoding: **3.5ns** (keepalive), 410ns (request.started), 1.4μs (request.completed)
  - SSE broadcast (no subscribers): **26.5ns** (single), 25μs (1000 events)
  - SSE broadcast (1000 subscribers): **51ns** (constant time via STM broadcast)
  - Coeffect combination (Pure+Pure): **1.7ns**
  - Map-based cache lookup: **51-53ns** (hit/miss)
  - BoundedCache lookup: **124-128ns**

### Remaining (Phase 7 - Integration)
- ~~Integrate Dhall BUILD files with flake.nix~~ **DONE**
- ~~Memory/performance benchmarks~~ **DONE** (see above)
- E2E tests with Playwright
- SearXNG + gVisor sandbox integration

## Build Commands

```bash
# Build in nix shell (required - LSP fails outside due to zlib)
nix develop --command bash -c "cd gateway && cabal build"

# Nix builds
nix build .#straylight-llm    # Binary
nix build .#basic             # Container (OpenRouter only)
nix build .#with-cgp          # Container (CGP-first)

# Dhall verification
nix build .#dhall-verify      # Verify source manifest (all 38 files exist)
nix build .#dhall-config      # Export typed config to JSON
```

## Forbidden Patterns

| Pattern | Why | Alternative |
|---------|-----|-------------|
| `read` | Partial | `readMaybe` |
| `head`/`tail`/`!!` | Partial | Pattern match, `listToMaybe` |
| `fromJust` | Partial | Pattern match, `fromMaybe` |
| `unsafePerformIO` | Breaks referential transparency | Effect system |
| `SomeException` | Too broad | Specific types (`HttpException`, `IOException`) |
| `Value` (Aeson) | Loses type safety | Proper ADTs |
| Raw `IO` in business logic | Untestable | Effect system |
| `error`/`undefined` | Partial | `Either`/`Maybe` |

## Key Files

```
straylight-llm/
├── flake.nix                      # GHC 9.12 configured
├── CLAUDE.md                      # This file
├── CONTINUITY_VISION.md           # Why we build correct AI
├── docs/
│   └── ARCHITECTURE.md            # Full 7-phase migration plan
├── aleph-reference/
│   └── src/examples/lean-continuity/
│       └── Continuity.lean        # Reference spec (923 lines)
├── gateway/
│   ├── src/
│   │   ├── Config.hs              # FIXED: readMaybe, IOException
│   │   ├── Types.hs               # FIXED: All 9 Value fields → proper ADTs
│   │   ├── Effects/
│   │   │   └── Graded.hs          # Phase 2: GatewayM graded monad
│   │   ├── Coeffect/
│   │   │   ├── Types.hs           # Phase 3: Coeffect, DischargeProof types
│   │   │   └── Discharge.hs       # Phase 3: proof generation, ed25519
│   │   ├── Router.hs              # Modified: generates discharge proofs
│   │   ├── Api.hs                 # Modified: added ProofAPI
│   │   ├── Handlers.hs            # Modified: added proofHandler
│   │   ├── Evring/                # State machine abstraction (6 modules)
│   │   ├── Slide/                 # Wire protocol (3 modules)
│   │   ├── Resilience/            # Cache, CircuitBreaker, Retry, etc. (5 modules)
│   │   ├── Security/              # Sanitization, limits, injection detection (6 modules)
│   │   ├── Streaming/             # SSE events (1 module: Events.hs)
│   │   └── Provider/
│   │       ├── Venice.hs          # FIXED: HttpException, uses GatewayM
│   │       ├── Vertex.hs          # FIXED: HttpException, 401 cache bug
│   │       ├── Baseten.hs         # FIXED: HttpException, uses GatewayM
│   │       ├── OpenRouter.hs      # FIXED: HttpException, uses GatewayM
│   │       └── Anthropic.hs       # Direct Anthropic API
│   ├── test/
│   │   ├── Main.hs                # Test runner (213 tests)
│   │   ├── Property/              # 6 modules (Types, Coeffect, Graded, Security, Streaming, Generators)
│   │   ├── Integration/           # 5 modules (API, Proof, Lifecycle, OpenAPI, TestServer)
│   │   ├── Adversarial/           # 3 modules (Race, Injection, ProviderErrors)
│   │   └── Formal/                # 1 module (ProofCorrespondence)
│   ├── bench/
│   │   ├── Main.hs                # Criterion benchmark runner
│   │   └── Bench/                 # Router, CircuitBreaker, SSEBroadcaster, Coeffect
│   └── app/
│       └── Main.hs
├── proofs/
│   └── Straylight/
│       ├── Coeffect.lean          # 305 lines
│       ├── Gateway.lean           # 376 lines
│       └── Hermetic.lean          # 223 lines
├── dhall/
│   ├── Target.dhall               # Typed build targets
│   ├── Platform.dhall             # Toolchain definitions
│   ├── Build.dhall                # Build script generation
│   ├── Action.dhall               # DICE actions
│   └── straylight-llm.dhall       # Gateway target definition
└── frontend/
    └── src/Straylight/
        ├── App.purs               # Main app shell
        ├── API/Client.purs        # API client
        └── Components/            # HealthStatus, ModelsPanel, ProofViewer, etc.
```

## The Vision

When complete, every request through straylight-llm will:

1. Have its effects tracked (HTTP, Config, Log, Crypto)
2. Have its coeffects declared (NetworkAccess, AuthUsage, FilesystemAccess)
3. Produce a DischargeProof signed with ed25519
4. Be covered by property tests with realistic distributions
5. Have critical invariants proven in Lean4
6. Be visualizable in a PureScript/Halogen dashboard

This is the difference between "it works" and "we can prove it works."
