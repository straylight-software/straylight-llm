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

### Completed (Phase 1 - Type Safety)
- GHC 9.12 upgrade (flake.nix, package.nix) — StrictData by default
- Architecture documentation (`docs/ARCHITECTURE.md`) with full gap analysis
- Config.hs: `read` → `readMaybe`, `SomeException` → `IOException`
- Provider/Venice.hs: `SomeException` → `HttpException`
- Provider/Baseten.hs: `SomeException` → `HttpException`
- Provider/OpenRouter.hs: `SomeException` → `HttpException`
- Provider/Vertex.hs: `SomeException` → `HttpException`/`IOException`, **401 cache invalidation bug fixed**
- All nix builds working: `.#straylight-llm`, `.#basic`, `.#with-cgp`
- **Types.hs: All 9 `Value` fields replaced with proper ADTs:**
  - `msgToolCalls :: Maybe [ToolCall]` — with `FunctionCall` record
  - `crStop :: Maybe StopSequence` — `StopSingle Text | StopMultiple [Text]`
  - `crLogitBias :: Maybe LogitBias` — newtype over `[(Text, Double)]`
  - `crTools :: Maybe [ToolDef]` — with `ToolFunction`, `JsonSchema`
  - `crToolChoice :: Maybe ToolChoice` — `ToolChoiceAuto | ToolChoiceNone | ToolChoiceRequired | ToolChoiceSpecific`
  - `crResponseFormat :: Maybe ResponseFormat` — `ResponseFormatText | ResponseFormatJsonObject | ResponseFormatJsonSchema`
  - `deltaDelta :: Maybe DeltaContent` — with `ToolCallDelta`, `FunctionCallDelta`
  - `complStop :: Maybe StopSequence` — same as crStop
  - `embInput :: EmbeddingInput` — `EmbeddingText | EmbeddingTexts | EmbeddingTokens | EmbeddingTokenArrays`

### Remaining Phases
- **Phase 2**: Add effect system (effectful or polysemy)
- **Phase 3**: Add coeffect tracking with discharge proofs
- **Phase 4**: Add hedgehog + haskemathesis property tests
- **Phase 5**: Add Lean4 proofs (no `sorry`, no `axiom` escapes)
- **Phase 6**: PureScript/Halogen frontend
- **Phase 7**: Integration (Dhall, DICE, e2e, security)

## Build Commands

```bash
# Build in nix shell (required - LSP fails outside due to zlib)
nix develop --command bash -c "cd gateway && cabal build"

# Nix builds
nix build .#straylight-llm    # Binary
nix build .#basic             # Container (OpenRouter only)
nix build .#with-cgp          # Container (CGP-first)
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
├── docs/
│   └── ARCHITECTURE.md            # Full 7-phase migration plan
├── aleph-reference/
│   └── src/examples/lean-continuity/
│       └── Continuity.lean        # Reference spec (923 lines)
├── gateway/
│   ├── src/
│   │   ├── Config.hs              # FIXED: readMaybe, IOException
│   │   ├── Types.hs               # FIXED: All 9 Value fields → proper ADTs
│   │   └── Provider/
│   │       ├── Venice.hs          # FIXED: HttpException
│   │       ├── Vertex.hs          # FIXED: HttpException, 401 cache bug
│   │       ├── Baseten.hs         # FIXED: HttpException
│   │       └── OpenRouter.hs      # FIXED: HttpException
│   └── app/
│       └── Main.hs
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
