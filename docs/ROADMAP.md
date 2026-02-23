# // straylight-llm roadmap //

> "The matrix has its roots in primitive arcade games..."

## Current Status

**Build:** Passing (GHC 9.10.3, cabal build)  
**Tests:** 130/130 passing (property + integration + adversarial)  
**Nix:** `.#straylight-llm` builds successfully  

---

## Completed Work

### Phase 1: Type Safety (Complete)
- [x] GHC 9.12 upgrade
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
- [x] 47 hedgehog property tests
- [x] All semantic types have roundtrip tests
- [x] Coeffect types tested
- [x] Base16 encoding/decoding

### Phase 5: Lean4 Proofs (Complete)
- [x] `proofs/Straylight/Coeffect.lean` - Coeffect monoid, tensor product
- [x] `proofs/Straylight/Gateway.lean` - Provider types, fallback termination
- [x] `proofs/Straylight/Hermetic.lean` - Hermeticity guarantees
- [x] No `sorry`, no `axiom` escapes

### Session Work (Feb 23, 2026)
- [x] Anthropic provider integrated into fallback chain (last position)
- [x] `Anthropic` added to `ProviderName` enum
- [x] Config/Router updated with `cfgAnthropic`/`routerAnthropicConfig`
- [x] `FromJSON HealthResponse` for test support
- [x] Dynamic ModelRegistry with realtime provider sync
- [x] 404 → Retry fix for all providers
- [x] Anthropic models API integration
- [x] COMPASS-style adversarial test suite (37 new tests)
  - Race condition tests (STM atomicity, cache concurrency)
  - Injection edge case tests (Unicode, path traversal, JSON attacks)
  - Coeffect algebraic property tests

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

## Remaining Work

### High Priority

#### Backport Safety Fixes to Production
- [x] Create fix for `straylight-repos/slide` with `reads` pattern fix
  - Commit `5b5c36c` on branch `fix/safe-reads-parse` (local)
  - **Blocked:** No write access to straylight-software/slide
  - **Action:** Request push access or submit via internal process
- [ ] Create PR for `straylight-repos/libevring` with `BS.uncons` fix

#### COMPASS Agent Testing Integration
- [x] Study `compass-evals` patterns for provider testing
- [x] Added graded monad algebraic property tests (11 new tests)
- [ ] Adapt scenario framework for fallback chain testing (future)
- [ ] Add cost tracking assertions from COMPASS patterns (future)

### Medium Priority

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

#### Full Evring Integration
- [ ] Add `Evring/Ring.hs` (io_uring runner) if kernel-level ops needed
- [ ] Add `Evring/Trace.hs` for trace recording

### Phase 6: PureScript Frontend (Future)
- [ ] Set up PureScript + Halogen project
- [ ] Provider status dashboard
- [ ] Request/response timeline
- [ ] Coeffect visualization
- [ ] Discharge proof viewer

### Phase 7: Integration (Future)
- [ ] Dhall BUILD files
- [ ] DICE action definitions
- [ ] E2E tests with Playwright
- [ ] Memory/performance benchmarks
- [ ] Security audit automation

---

## Module Status

### Present and Complete
| Module | Lines | Status |
|--------|-------|--------|
| `Api.hs` | ~115 | Complete |
| `Config.hs` | ~260 | Complete |
| `Handlers.hs` | ~150 | Complete |
| `Router.hs` | ~250 | Complete |
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
| `Evring/Event.hs` | 113 | Simplified (gateway-only ops) |
| `Evring/Handle.hs` | ~50 | Complete |
| `Evring/Machine.hs` | ~100 | Complete |
| `Evring/Sigil.hs` | 474 | Complete (better than prod) |
| `Resilience/Cache.hs` | ~100 | Complete |
| `Resilience/CircuitBreaker.hs` | ~100 | Complete |
| `Resilience/Retry.hs` | ~100 | Complete |
| `Resilience/Backpressure.hs` | ~100 | Complete |
| `Resilience/Metrics.hs` | ~100 | Complete |

### Missing (may not be needed)
| Module | Priority | Notes |
|--------|----------|-------|
| `Slide/Wire/Decode.hs` | Low | Only if decoding SIGIL from clients |
| `Slide/Wire/Encode.hs` | Medium | Only if emitting SIGIL to clients |
| `Slide/Wire/Frame.hs` | Medium | Required for SIGIL encoding |
| `Slide/Chunk.hs` | Medium | Semantic chunking |
| `Slide/HotTable.hs` | Medium | Hot token compression |
| `Slide/Model.hs` | Low | Model abstraction |
| `Evring/Ring.hs` | Low | io_uring (uses HTTP client instead) |
| `Evring/Trace.hs` | Low | Trace recording |

---

## Test Coverage

| Category | Tests | Status |
|----------|-------|--------|
| Property: Types.hs | 41 | Passing |
| Property: Coeffect (roundtrip) | 6 | Passing |
| Property: Coeffect (algebraic) | 6 | Passing |
| Property: Graded Monad | 11 | Passing |
| Integration: Health | 2 | Passing |
| Integration: Models | 1 | Passing |
| Integration: Chat | 1 | Passing |
| Integration: Embeddings | 1 | Passing |
| Integration: Proof | 1 | Passing |
| Adversarial: Race Conditions | 9 | Passing |
| Adversarial: Injection Edge Cases | 22 | Passing |
| Adversarial: Provider Errors | 29 | Passing |
| **Total** | **130** | **Passing** |

---

## Build Artifacts

```bash
# Binary
nix build .#straylight-llm

# Containers
nix build .#basic        # OpenRouter only
nix build .#with-cgp     # CGP-first

# Development
nix develop --command bash -c "cd gateway && cabal build"
nix develop --command bash -c "cd gateway && cabal test"
```

---

## Provider Chain Order

```
Venice → Vertex → Baseten → OpenRouter → Anthropic
  ↓        ↓         ↓          ↓           ↓
primary  GCP      tertiary   fallback    direct API
         credits                          (last)
```

Anthropic is last: direct API access, used when explicitly requested or all others fail.

---

## References

- `docs/ARCHITECTURE.md` - Full architecture documentation
- `CLAUDE.md` - AI agent context and standards
- `proofs/` - Lean4 verification
- `/home/justin/jpyxal/straylight-repos/` - Production reference code
- `/home/justin/jpyxal/COMPASS/` - Agent testing patterns

---

*Last updated: February 23, 2026*
