# // straylight-llm roadmap //

> "The matrix has its roots in primitive arcade games..."

## Current Status

**Build:** Passing (GHC 9.12.2, cabal build)  
**Tests:** 249/249 passing (property + integration + adversarial + formal + security)  
**Nix:** `.#straylight-llm` builds successfully  
**COMPASS Target:** 135+ tests - **EXCEEDED (249)**  
**Streaming:** SSE endpoint implemented (`/v1/chat/completions/stream`)  
**Real-time Events:** SSE broadcaster (`/v1/events`)  
**Dhall BUILD:** Complete - typed targets, DICE actions, no globs  
**io_uring:** Production-ready CPS event loop  
**Benchmarks:** Criterion suite complete  

---

## Completed Work

### Phase 1: Type Safety (Complete)
- [x] GHC 9.12.2 upgrade
- [x] `read` → `readMaybe` throughout
- [x] `SomeException` → specific types (`HttpException`, `IOException`)
- [x] All 9 Aeson `Value` fields replaced with proper ADTs
- [x] StrictData enabled

### Phase 2: Effect System (Complete)
- [x] `GatewayM` graded monad (`Effects/Graded.hs`)
- [x] `GatewayGrade` cost tracking (latency, tokens, retries, cache)
- [x] `GatewayCoEffect` resource tracking (HTTP, Auth, Config)
- [x] `GatewayProvenance` audit trail
- [x] All providers use `GatewayM`

### Phase 3: Coeffect Tracking & Discharge Proofs (Complete)
- [x] `Coeffect/Types.hs` - Coeffect, NetworkAccess, FilesystemAccess, AuthUsage
- [x] `Coeffect/Discharge.hs` - ed25519 signing, SHA256 hashing
- [x] `/v1/proof/:requestId` API endpoint
- [x] Router generates discharge proofs

### Phase 4: Property Tests (Complete)
- [x] 85+ hedgehog property tests
- [x] All semantic types have roundtrip tests
- [x] Coeffect types tested
- [x] Base16 encoding/decoding
- [x] Graded monad algebraic laws

### Phase 5: Lean4 Proofs (Complete)
- [x] `proofs/Straylight/Coeffect.lean` - Coeffect monoid, tensor product (305 lines)
- [x] `proofs/Straylight/Gateway.lean` - Provider types, fallback termination (376 lines)
- [x] `proofs/Straylight/Hermetic.lean` - Hermeticity guarantees (223 lines)
- [x] No `sorry`, no `axiom` escapes - 904 lines total

### Phase 6: Dhall BUILD Files (Complete)
- [x] `dhall/Target.dhall` - Typed build targets (no string flags)
- [x] `dhall/Platform.dhall` - Toolchain definitions (GHC, Cabal, containers)
- [x] `dhall/Build.dhall` - Build script generation for Haskell/Cabal
- [x] `dhall/Action.dhall` - DICE-style incremental computation actions
- [x] `dhall/straylight-llm.dhall` - Gateway target (38-file manifest)
- [x] `nix build .#dhall-verify` - Verifies all declared source files exist
- [x] `nix build .#dhall-config` - Exports typed config to JSON

### Phase 7: Performance Benchmarks (Complete)
- [x] Criterion benchmark suite (`gateway/bench/`)
- [x] Request ID generation: 407ns (single), 41μs (100)
- [x] Circuit breaker state check: 7.8ns
- [x] SSE event encoding: 3.5ns (keepalive), 1.4μs (request.completed)
- [x] SSE broadcast (1000 subscribers): 51ns (constant time via STM)
- [x] Coeffect combination: 1.7ns
- [x] BoundedCache lookup: 124-128ns

### Security Hardening (Complete)
- [x] XSS and injection vector test suite (90+ attack patterns)
- [x] Wallet exfiltration detection (`Security/PromptInjection.hs`)
- [x] Output validation for LLM responses
- [x] Constant-time comparison (`Security/ConstantTime.hs`)
- [x] Request sanitization (`Security/RequestSanitization.hs`)
- [x] Response sanitization (`Security/ResponseSanitization.hs`)
- [x] Observability sanitization (`Security/ObservabilitySanitization.hs`)
- [x] Request limits (`Security/RequestLimits.hs`)

### io_uring Integration (Complete)
- [x] CPS-based single-threaded event loop (`Evring/Wai/Loop.hs`)
- [x] Connection handling with backpressure (`Evring/Wai/Conn.hs`)
- [x] Single-core server (`Evring/Wai/Server.hs`)
- [x] Multi-core with SO_REUSEPORT (`Evring/Wai/MultiCore.hs`)
- [x] Round-robin multi-core (`Evring/Wai/MultiCoreRR.hs`)
- [x] Buffer pool management (`Evring/Wai/Pool.hs`)
- [x] `submitWaitTimeoutDrain` in URing module
- [x] Graceful slot exhaustion (Failure ENOSPC, no crashes)
- [x] `USE_URING=1` / `USE_URING_MC=1` environment variables

### GPU Compute Providers (Complete)
- [x] LambdaLabs provider integration
- [x] RunPod provider integration
- [x] VastAI provider integration
- [x] Rate aggregator for multi-provider cost optimization

### Real-time SSE Events (Complete)
- [x] `Streaming/Events.hs` - Event broadcaster using STM broadcast channels
- [x] `GET /v1/events` - SSE endpoint subscribes to broadcaster
- [x] Event types: `request.started`, `request.completed`, `proof.generated`, `provider.status`, `keepalive`
- [x] Circuit breaker state change notifications
- [x] All request routes emit events

### Frontend - Hydrogen v2 (Partial)
- [x] PureScript + Halogen project in `frontend/`
- [x] Main app shell with tab navigation (`App.purs`)
- [x] API client with full type definitions (`API/Client.purs`)
- [x] Health status component (`Components/HealthStatus.purs`)
- [x] Models panel component (`Components/ModelsPanel.purs`)
- [x] Basic proof viewer component (`Components/ProofViewer.purs`)
- [x] Request timeline component
- [x] 14 themes (`themes.css`)
- [x] Tauri desktop builds (`src-tauri/`)

### Production Deployment (Complete)
- [x] NixOS module for systemd service
- [x] nix2gpu container builds
- [x] CI/CD pipeline

---

## Remaining Work

### High Priority

#### Frontend Visualization
- [ ] Provider status dashboard (real-time health, circuit breaker visualization)
- [ ] Coeffect graph visualization (DAG of coeffect relationships)
- [ ] Enhanced proof inspector (signature verification, hash verification UI)
- [ ] Metrics dashboard (token usage, latency, cache performance)
- [ ] Connect frontend to `GET /v1/events` SSE endpoint

#### Integration Testing
- [ ] E2E tests with Playwright
- [ ] SearXNG + gVisor sandbox integration

### Medium Priority

#### COMPASS Agent Testing Integration
- [ ] Adapt scenario framework for fallback chain testing
- [ ] Add cost tracking assertions from COMPASS patterns

#### SIGIL Encoding (if needed for downstream clients)
- [ ] Add `Slide/Wire/Decode.hs` (with safety fixes)
- [ ] Add `Slide/Wire/Encode.hs` (with safety fixes)
- [ ] Add `Slide/Wire/Frame.hs` (replace `error` with `Either`)

#### Semantic Chunking
- [ ] Add `Slide/Chunk.hs`
- [ ] Add `Slide/HotTable.hs` (fix `unsafePerformIO`)

#### HTTP/2 Support
- [ ] Consider `Provider/HTTP2.hs` from libevring for proper HTTP/2 streaming

### Low Priority

#### Backport Safety Fixes to Production
- [x] Create fix for `straylight-repos/slide` with `reads` pattern fix
  - Commit `5b5c36c` on branch `fix/safe-reads-parse` (local)
  - **Blocked:** No write access to straylight-software/slide
- [ ] Create PR for `straylight-repos/libevring` with `BS.uncons` fix

---

## Compliance Audit Results

### Gateway vs Production (straylight-repos)

**Gateway is BETTER than production:**

| File | Why Better |
|------|------------|
| `Slide/Parse.hs` | Uses `reads` instead of partial `read` |
| `Evring/Sigil.hs` | Uses `BS.uncons` instead of partial `head`/`tail` |
| `Provider/*.hs` | Effect tracking, proper error types |
| `Effects/Graded.hs` | Novel graded monad (not in production) |
| `Coeffect/*.hs` | Novel discharge proofs (not in production) |

**Production has issues we fixed:**

| Production File | Issue | Our Fix |
|-----------------|-------|---------|
| `slide/src/Slide/Parse.hs:100` | `read digits` partial | `reads` pattern |
| `slide/src/Slide/Parse.hs:179` | `read` for hex parse | `reads` pattern |
| `libevring/hs/Evring/Sigil.hs:476-477` | `BS.head`/`BS.tail` | `BS.uncons` |

**Forbidden pattern scan:** Zero violations in gateway/src/

---

## Module Status

### Present and Complete
| Module | Lines | Status |
|--------|-------|--------|
| `Api.hs` | ~130 | Complete |
| `Config.hs` | ~260 | Complete |
| `Handlers.hs` | ~280 | Complete |
| `Router.hs` | ~270 | Complete |
| `Types.hs` | ~400 | Complete (all ADTs) |
| `Effects/Graded.hs` | 472 | Complete |
| `Coeffect/Types.hs` | ~200 | Complete |
| `Coeffect/Discharge.hs` | ~200 | Complete |
| `Provider/Venice.hs` | ~250 | Complete |
| `Provider/Vertex.hs` | ~350 | Complete |
| `Provider/Baseten.hs` | ~250 | Complete |
| `Provider/OpenRouter.hs` | ~250 | Complete |
| `Provider/Anthropic.hs` | ~300 | Complete |
| `Provider/Types.hs` | ~100 | Complete |
| `Types/Anthropic.hs` | ~200 | Complete |
| `Slide/Parse.hs` | 188 | Complete (better than prod) |
| `Slide/Wire/Types.hs` | ~60 | Complete |
| `Slide/Wire/Varint.hs` | ~70 | Partial (missing `pokeVarint`) |
| `Evring/Event.hs` | 113 | Complete |
| `Evring/Handle.hs` | 68 | Complete |
| `Evring/Machine.hs` | 111 | Complete |
| `Evring/Ring.hs` | 230 | Complete |
| `Evring/Sigil.hs` | 527 | Complete (better than prod) |
| `Evring/Trace.hs` | 230 | Complete |
| `Evring/Wai.hs` | ~100 | Complete (thin wrapper) |
| `Evring/Wai/Conn.hs` | ~600 | Complete |
| `Evring/Wai/Loop.hs` | ~400 | Complete |
| `Evring/Wai/Server.hs` | ~100 | Complete |
| `Evring/Wai/MultiCore.hs` | ~140 | Complete |
| `Evring/Wai/MultiCoreRR.hs` | ~260 | Complete |
| `Evring/Wai/Pool.hs` | ~60 | Complete |
| `Resilience/Cache.hs` | ~100 | Complete |
| `Resilience/CircuitBreaker.hs` | ~100 | Complete |
| `Resilience/Retry.hs` | ~100 | Complete |
| `Resilience/Backpressure.hs` | ~100 | Complete |
| `Resilience/Metrics.hs` | ~100 | Complete |
| `Security/ConstantTime.hs` | ~50 | Complete |
| `Security/PromptInjection.hs` | ~150 | Complete |
| `Security/RequestLimits.hs` | ~80 | Complete |
| `Security/RequestSanitization.hs` | ~100 | Complete |
| `Security/ResponseSanitization.hs` | ~100 | Complete |
| `Security/ObservabilitySanitization.hs` | ~80 | Complete |
| `Streaming/Events.hs` | ~150 | Complete |

### Dhall BUILD Files
| File | Lines | Status |
|------|-------|--------|
| `dhall/Target.dhall` | 177 | Complete (typed targets, no globs) |
| `dhall/Platform.dhall` | 95 | Complete (toolchains) |
| `dhall/Build.dhall` | 214 | Complete (script generation) |
| `dhall/Action.dhall` | 218 | Complete (DICE actions) |
| `dhall/straylight-llm.dhall` | 233 | Complete (gateway definition) |
| `dhall/examples/*.dhall` | 70 | Complete (examples) |

### Missing (may not be needed)
| Module | Priority | Notes |
|--------|----------|-------|
| `Slide/Wire/Decode.hs` | Low | Only if decoding SIGIL from clients |
| `Slide/Wire/Encode.hs` | Medium | Only if emitting SIGIL to clients |
| `Slide/Wire/Frame.hs` | Medium | Required for SIGIL encoding |
| `Slide/Chunk.hs` | Medium | Semantic chunking |
| `Slide/HotTable.hs` | Medium | Hot token compression |
| `Slide/Model.hs` | Low | Model abstraction |

---

## Test Coverage

| Category | Tests | Status |
|----------|-------|--------|
| Property: Types.hs | 41 | Passing |
| Property: Coeffect (roundtrip) | 6 | Passing |
| Property: Coeffect (algebraic) | 6 | Passing |
| Property: Graded Monad | 11 | Passing |
| Property: Streaming | 21 | Passing |
| Property: Security | 8 | Passing |
| Integration: API | 5 | Passing |
| Integration: Proof | 1 | Passing |
| Integration: Lifecycle | 11 | Passing |
| Integration: OpenAPI | 4 | Passing |
| Adversarial: Race Conditions | 9 | Passing |
| Adversarial: Injection Edge Cases | 22 | Passing |
| Adversarial: Provider Errors | 29 | Passing |
| Adversarial: XSS Vectors | 8 | Passing |
| Formal: Proof Correspondence | 9 | Passing |
| Conformance: haskemathesis | 58 | Passing |
| **Total** | **249** | **Passing** |

---

## Build Artifacts

```bash
# Binary
nix build .#straylight-llm

# Containers
nix build .#basic        # OpenRouter only
nix build .#with-cgp     # CGP-first

# Dhall verification
nix build .#dhall-verify  # Verify source manifest
nix build .#dhall-config  # Export typed config to JSON

# Development
nix develop --command bash -c "cd gateway && cabal build"
nix develop --command bash -c "cd gateway && cabal test"

# Benchmarks
nix develop --command bash -c "cd gateway && cabal bench"

# io_uring mode
USE_URING=1 ./run-uring.sh       # Single-core
USE_URING_MC=1 ./run-uring.sh    # Multi-core (SO_REUSEPORT)
```

---

## Provider Chain Order

```
Venice → Vertex → Baseten → OpenRouter → Anthropic
  ↓        ↓         ↓          ↓           ↓
primary  GCP      tertiary   fallback    direct API
         credits                          (last)

GPU Compute (on-demand):
LambdaLabs → RunPod → VastAI
```

Anthropic is last: direct API access, used when explicitly requested or all others fail.

---

## References

- `docs/ARCHITECTURE.md` - Full architecture documentation
- `docs/API_REFERENCE.md` - API endpoint documentation
- `docs/CONFIGURATION.md` - Environment variables and config
- `docs/DEPLOYMENT.md` - Production deployment guide
- `docs/QUICKSTART.md` - Getting started guide
- `CLAUDE.md` - AI agent context and standards
- `proofs/` - Lean4 verification (904 lines)

---

*Last updated: March 3, 2026*
