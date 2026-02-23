# // straylight-llm architecture //

> "The sky above the port was the color of television, tuned to a dead channel."

## Aleph Cube Compliance Audit

This document tracks compliance with the aleph cube architecture as defined in `aleph-reference/src/examples/lean-continuity/Continuity.lean`.

### Core Principles

| Principle | Current Status | Required |
|-----------|---------------|----------|
| StrictData | Enabled (GHC 9.12) | Yes |
| No partial functions | Compliant (readMaybe) | Zero |
| No `unsafePerformIO` | Compliant | Zero |
| No `fromJust`/`head`/`tail`/`!!` | Compliant | Zero |
| No `Value` (Aeson) | Compliant (proper ADTs) | Zero |
| Semantic newtypes | Compliant (ModelId, etc.) | Yes |
| Typed coeffects | **Complete** (Effects.Graded) | Required |
| Discharge proofs | **Complete** (Coeffect.Discharge) | Required |
| Effect system | **Complete** (GatewayM graded monad) | Required |
| Property tests | **Complete** (171 tests) | Required |
| Lean4 proofs | **Complete** (904 lines, no sorry) | Required |
| Deterministic builds | Partial (Dhall BUILD files) | Required |

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        straylight-llm                           │
├─────────────────────────────────────────────────────────────────┤
│  Main.hs                                                        │
│    └── Raw IO, console printing, server startup                 │
├─────────────────────────────────────────────────────────────────┤
│  Handlers.hs                                                    │
│    └── Servant Handler monad, liftIO, throwError                │
├─────────────────────────────────────────────────────────────────┤
│  Router.hs                                                      │
│    └── IORef mutable state, raw IO provider calls               │
├─────────────────────────────────────────────────────────────────┤
│  Provider/*.hs                                                  │
│    └── HTTP client IO, SomeException catching                   │
├─────────────────────────────────────────────────────────────────┤
│  Types.hs                                                       │
│    └── Aeson Value for dynamic fields (loses type safety)       │
├─────────────────────────────────────────────────────────────────┤
│  Config.hs                                                      │
│    └── `read` partial function, raw IO env var lookup           │
└─────────────────────────────────────────────────────────────────┘
```

**Problems:**
1. No effect tracking - can't prove what IO operations are performed
2. No coeffect tracking - can't prove what resources are required
3. No discharge proofs - can't verify builds satisfied their requirements
4. `Value` type loses compile-time guarantees
5. `SomeException` catching is too broad
6. No property testing for realistic distributions
7. No formal verification

---

## Target Architecture (Aleph Cube)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Lean4 Verification Layer                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Continuity.lean: Core invariants proven                   │  │
│  │ - Cache correctness (same coset → same outputs)           │  │
│  │ - Hermeticity (builds access only declared inputs)        │  │
│  │ - Offline capability (populated store → no network)       │  │
│  │ - Attestation soundness (signatures unforgeable)          │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Dhall Configuration Layer                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ BUILD.dhall: Typed build specifications                   │  │
│  │ - No globs, explicit file lists                           │  │
│  │ - Typed toolchains (Triple, Cpu, Gpu, OptLevel)           │  │
│  │ - Typed flags (no string soup)                            │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Haskell Gateway Layer                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Effectful/Polysemy effect system                          │  │
│  │ - HTTP effect (not raw IO)                                │  │
│  │ - Config effect (not raw env lookup)                      │  │
│  │ - Log effect (not raw putStrLn)                           │  │
│  │ - Crypto effect (for attestation)                         │  │
│  │                                                           │  │
│  │ Typed coeffects                                           │  │
│  │ - NetworkAccess: URL, method, content hash                │  │
│  │ - AuthUsage: provider, scope, timestamp                   │  │
│  │ - FilesystemAccess: path, mode, hash                      │  │
│  │                                                           │  │
│  │ Discharge proofs                                          │  │
│  │ - Build produces DischargeProof                           │  │
│  │ - Proof signed with ed25519                               │  │
│  │ - Proof verifiable offline                                │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Property Testing Layer                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Hedgehog + haskemathesis                                  │  │
│  │ - Realistic distributions from OpenAPI schemas            │  │
│  │ - Round-trip JSON serialization                           │  │
│  │ - Provider error classification                           │  │
│  │ - Fallback chain invariants                               │  │
│  │ - State machine testing for router                        │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    PureScript Frontend Layer                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Halogen UI                                                │  │
│  │ - Provider status dashboard                               │  │
│  │ - Request/response inspector                              │  │
│  │ - Coeffect visualization                                  │  │
│  │ - Discharge proof viewer                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Migration Plan

### Phase 1: Critical Fixes (Immediate)

1. **Fix `read` partial function in Config.hs**
   ```haskell
   -- Before (unsafe)
   port <- maybe 8080 read <$> lookupEnv "STRAYLIGHT_PORT"
   
   -- After (safe)
   port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "STRAYLIGHT_PORT"
   ```

2. **Replace `Value` with proper types**
   ```haskell
   -- Before
   crStop :: Maybe Value  -- String or [String]
   
   -- After
   data StopSequence = StopSingle Text | StopMultiple [Text]
   crStop :: Maybe StopSequence
   ```

3. **Narrow exception handling**
   ```haskell
   -- Before
   result <- try @SomeException $ ...
   
   -- After
   result <- try @HttpException $ ...
   ```

4. **Fix Vertex 401 token cache invalidation**

### Phase 2: Effect System (1-2 weeks) — **COMPLETE**

**Completed:**
1. ✅ Created `Effects.Graded` module with graded monad following COMPASS Voice.Graded pattern
2. ✅ Defined `GatewayM` graded monad tracking (Grade, Provenance, CoEffect)
3. ✅ Defined `GatewayGrade` for cost tracking (latency, tokens, retries, cache)
4. ✅ Defined `GatewayCoEffect` for resource access tracking (HTTP, Auth, Config)
5. ✅ Defined `GatewayProvenance` for audit trail (requestId, providers, models)
6. ✅ Added helper functions: `withLatency`, `withTokens`, `recordHttpAccess`, etc.
7. ✅ Refactored Provider interface to use `GatewayM` instead of raw `IO`
8. ✅ Updated all providers (Venice, Vertex, Baseten, OpenRouter) to use `GatewayM`
9. ✅ Updated Router to track effects through provider chain
10. ✅ Router calls `runGatewayMPure` at boundary to interpret `GatewayM` to `IO`

**Architecture (implemented in Effects.Graded):**
```haskell
-- Graded monad tracking grade, provenance, and co-effects
newtype GatewayM a = GatewayM
  { unGatewayM :: IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect)
  }

-- Cost tracking
data GatewayGrade = GatewayGrade
  { ggLatencyMs, ggInputTokens, ggOutputTokens :: !Int
  , ggProviderCalls, ggRetries, ggCacheHits, ggCacheMisses :: !Int
  }

-- Resource access tracking (co-effects)
data GatewayCoEffect = GatewayCoEffect
  { gceHttpAccess :: !(Set HttpAccess)
  , gceAuthUsage :: !(Set AuthUsage)
  , gceConfigAccess :: !(Set ConfigAccess)
  }

-- Audit trail
data GatewayProvenance = GatewayProvenance
  { gpRequestId :: !(Maybe Text)
  , gpProvidersUsed :: ![Text]
  , gpModelsUsed :: ![Text]
  , gpTimestamp :: !(Maybe UTCTime)
  }
```

### Phase 3: Coeffect Tracking & Discharge Proofs (1 week) — **COMPLETE**

**Completed:**
- ✅ `HttpAccess` type matching Continuity.lean `NetworkAccess`
- ✅ `AuthUsage` type for auth credential tracking
- ✅ `ConfigAccess` type for configuration access tracking
- ✅ All co-effects tracked via `GatewayCoEffect` in `GatewayM`
- ✅ `DischargeProof` generation with ed25519 signatures
- ✅ Proof verification via `verifyProof`
- ✅ SHA256 content hashing for request/response bodies
- ✅ `/v1/proof/:requestId` API endpoint to retrieve proofs
- ✅ Proof cache in Router (TVar-based, thread-safe)
- ✅ ToJSON instances for DischargeProof and Coeffect

**Architecture (implemented in Coeffect/):**
```haskell
-- Coeffect types (Coeffect/Types.hs)
data Coeffect
  = CoeffectPure
  | CoeffectNetwork
  | CoeffectAuth !Text
  | CoeffectSandbox !Text
  | CoeffectFilesystem !Text
  | CoeffectCombined ![Coeffect]

data DischargeProof = DischargeProof
  { dpCoeffects :: ![Coeffect]
  , dpNetworkAccess :: ![NetworkAccess]
  , dpFilesystemAccess :: ![FilesystemAccess]
  , dpAuthUsage :: ![AuthUsage]
  , dpRequestId :: !Text
  , dpDerivationHash :: !Hash
  , dpOutputHashes :: ![(Text, Hash)]
  , dpStartTime :: !UTCTime
  , dpEndTime :: !UTCTime
  , dpSignature :: !(Maybe (PublicKey, Signature))
  }

-- Discharge proof generation (Coeffect/Discharge.hs)
generateDischargeProof :: GatewayCoEffect -> Text -> ByteString -> UTCTime -> UTCTime -> IO DischargeProof
signProof :: SecretKey -> DischargeProof -> DischargeProof
verifyProof :: PublicKey -> DischargeProof -> Bool
```

### Phase 4: Property Tests (1 week) — **COMPLETE**

**Completed:**
- 171 tests total (hedgehog + integration + adversarial + formal)
- Property tests: Types roundtrip (41), Coeffect (12), Graded Monad (11), Security, Streaming (21)
- Integration tests: API (5), Proof (1), Lifecycle (11), OpenAPI spec
- Adversarial tests: Race conditions (9), Injection edge cases (22), Provider errors (29)
- Formal tests: Proof correspondence (9) — Haskell ↔ Lean4 verification

### Phase 5: Lean4 Proofs (2 weeks) — **COMPLETE**

**Completed:**
- `proofs/Straylight/Coeffect.lean` (305 lines): Coeffect monoid, tensor product, discharge laws
- `proofs/Straylight/Gateway.lean` (376 lines): Provider types, fallback termination, retry bounds
- `proofs/Straylight/Hermetic.lean` (223 lines): Hermeticity guarantees, cache isolation
- **No `sorry`, no `axiom` escapes** — all proofs complete

### Phase 6: PureScript Frontend (2 weeks) — **PARTIAL**

**Completed:**
- PureScript + Halogen project in `frontend/`
- `App.purs` — Main app shell with tab navigation (Health/Models/Proofs)
- `API/Client.purs` — Full type definitions, API client
- `Components/HealthStatus.purs`, `ModelsPanel.purs`, `ProofViewer.purs`
- `themes.css` — 14 themes
- `src-tauri/` — Tauri desktop builds (deb/appimage)

**Remaining:**
- Provider Status Dashboard (real-time health, circuit breaker visualization)
- Request/Response Timeline (chronological view with filtering)
- WebSocket/SSE real-time updates
- Coeffect Graph Visualization
- Enhanced Proof Inspector
- Metrics Dashboard

### Phase 7: Integration (1 week) — **PARTIAL**

**Completed:**
- Dhall BUILD files: `Target.dhall`, `Platform.dhall`, `Build.dhall`, `Action.dhall`, `straylight-llm.dhall`
- All Dhall files type-check with `dhall type`
- Evring state machine abstraction (6 modules)
- Resilience modules (Cache, CircuitBreaker, Retry, Backpressure, Metrics)
- Security modules (ConstantTime, PromptInjection, RequestLimits, Sanitization)

**Remaining:**
- Integrate Dhall with flake.nix
- E2E tests with Playwright
- Memory/performance benchmarks
- SearXNG + gVisor sandbox integration

---

## Forbidden Patterns

The following patterns are banned and should be caught by linting:

| Pattern | Why Forbidden | Alternative |
|---------|---------------|-------------|
| `read` | Partial, throws on bad input | `readMaybe` |
| `head`/`tail`/`!!` | Partial, throws on empty | Pattern matching, `listToMaybe` |
| `fromJust` | Partial, throws on Nothing | Pattern matching, `fromMaybe` |
| `unsafePerformIO` | Breaks referential transparency | Effect system |
| `SomeException` | Too broad, hides bugs | Specific exception types |
| `Value` (Aeson) | Loses type safety | Proper ADTs |
| Raw `IO` in business logic | Untestable, no effect tracking | Effect system |
| `putStrLn`/`print` | Unstructured logging | Log effect |
| `error`/`undefined` | Partial, crashes at runtime | `Either`/`Maybe` |
| String-typed configs | Type confusion | Newtypes, ADTs |

---

## File Structure (Target)

```
straylight-llm/
├── flake.nix                      # GHC 9.12, Lean4, PureScript
├── master-spec.md
├── docs/
│   └── ARCHITECTURE.md            # This file
│
├── dhall/                         # Typed build specs
│   ├── BUILD.dhall
│   └── package.dhall
│
├── proofs/                        # Lean4 verification
│   ├── lakefile.lean
│   ├── Gateway.lean               # Gateway-specific proofs
│   └── Coeffect.lean              # Coeffect system proofs
│
├── gateway/                       # Haskell server
│   ├── src/
│   │   ├── Effects/               # Effect definitions
│   │   │   ├── Http.hs
│   │   │   ├── Config.hs
│   │   │   └── Log.hs
│   │   ├── Coeffect/              # Coeffect tracking
│   │   │   ├── Types.hs
│   │   │   └── Discharge.hs
│   │   └── ...existing modules...
│   └── test/
│       ├── Property/              # Hedgehog property tests
│       │   ├── Types.hs
│       │   ├── Router.hs
│       │   └── Provider.hs
│       └── Unit/                  # HUnit tests
│
├── frontend/                      # PureScript dashboard
│   ├── spago.dhall
│   └── src/
│       └── Main.purs
│
└── test/
    ├── e2e/                       # Playwright tests
    └── security/                  # Forbidden pattern checks
```

---

## Verification Checklist

Before any release:

- [ ] All property tests pass
- [ ] Lean4 proofs compile (no `sorry`, no `axiom` escapes)
- [ ] Zero forbidden patterns in codebase
- [ ] Coeffects tracked for all external operations
- [ ] Discharge proofs generated and signed
- [ ] E2E tests pass
- [ ] Security audit complete
- [ ] Memory/perf benchmarks within targets
- [ ] Documentation current
