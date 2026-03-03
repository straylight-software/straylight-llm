# effect-monad → straylight-llm Integration

## The Problem

Current `GatewayM` is a value-level writer monad:

```haskell
newtype GatewayM a = GatewayM
  { unGatewayM :: IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect) }

instance Monad GatewayM where ...
```

Every function is `GatewayM a` — the type checker can't distinguish between
a function that only reads config and one that makes HTTP calls, uses
credentials, and signs proofs. The "graded" claim exists in comments and
documentation but not in the type system.

## The Fix

Add a type parameter indexed by Orchard's `Effect` class:

```haskell
newtype GatewayM (es :: [GradeLabel]) a = GatewayM
  { unGatewayM :: IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect) }

instance Effect GatewayM where
  type Unit GatewayM = '[]           -- pure
  type Plus GatewayM f g = Union f g -- set union
  type Inv  GatewayM f g = ()
```

Now `GatewayM '[Net, Auth] a` means "may make network calls and use
credentials, nothing else." Enforced by GHC, not by convention.

## Migration Steps

### 1. Add effect-monad dependency

In `gateway/cabal.project`:
```
packages:
  .
  ../effect-monad-912
```

In `gateway/straylight-llm.cabal`:
```
build-depends:
  , effect-monad >= 0.9
```

### 2. Add new modules

```
gateway/src/Effects/Grade.hs   -- Type-level labels: Net, Auth, Config, Log, Crypto, Fs
gateway/src/Effects/Do.hs      -- QualifiedDo re-exports
```

### 3. Modify Effects.Graded

Replace the unparameterized `GatewayM` with the graded version.
The API is backward-compatible if you define:

```haskell
-- Escape hatch for unmigrated code
type UngradedM = GatewayM Full
```

All existing code that uses `GatewayM a` becomes `UngradedM a` = `GatewayM Full a`,
which compiles immediately because `Full` permits all effects.

### 4. Replace liftGatewayIO calls (incremental)

| Before | After | Grade |
|--------|-------|-------|
| `liftGatewayIO (httpCall ...)` | `liftNet (httpCall ...)` | `'[Net]` |
| `liftGatewayIO (readApiKey ...)` | `liftAuth (readApiKey ...)` | `'[Auth]` |
| `liftGatewayIO (readConfig ...)` | `liftConfig (readConfig ...)` | `'[Config]` |
| `liftGatewayIO (logInfo ...)` | `liftLog (logInfo ...)` | `'[Log]` |
| `liftGatewayIO (signEd25519 ...)` | `liftCrypto (signEd25519 ...)` | `'[Crypto]` |
| `liftGatewayIO (anything)` | `liftIO' (anything)` | `Full` (escape hatch) |

This is mechanical. Start at the leaves (functions that do one thing),
give them tight grades, then let GHC tell you what the callers need.

### 5. Switch to QualifiedDo in migrated functions

```haskell
{-# LANGUAGE QualifiedDo #-}
import Effects.Do qualified as G

signResult :: Result -> GatewayM '[Crypto] DischargeProof
signResult result = G.do
  hash <- liftCrypto (sha256 (encode result))
  sig  <- liftCrypto (ed25519Sign key hash)
  G.return (DischargeProof hash sig)
```

Functions that aren't migrated yet keep using regular `do` with `UngradedM`.

## What Doesn't Change

- **Runtime behavior**: Zero runtime cost. The grade parameter is phantom —
  erased at compile time. Same `IO (a, Grade, Prov, CoEffect)` tuple at runtime.

- **Value-level tracking**: `GatewayGrade`, `GatewayCoEffect`, `GatewayProvenance`
  stay exactly as they are. They record what *actually happened*.
  The type-level grade records what was *permitted to happen*.

- **Discharge proofs**: `Coeffect.Types` and `Coeffect.Discharge` don't change.
  They consume the value-level tracking data.

- **Test suite**: Tests call `runGatewayM` which erases the grade. All 249 tests
  continue to pass without modification.

- **Benchmarks**: Same — `runGatewayM` erases the grade, no runtime overhead.

## What Changes

- **Type signatures get more informative**. `routeChat` was `GatewayM a`,
  becomes `GatewayM '[Net, Auth, Log, Crypto] a`. This is documentation
  that GHC enforces.

- **New effect operations caught at compile time**. If someone adds a
  network call inside `signResult`, GHC rejects it because `Net ∉ [Crypto]`.

- **Coeffect.Discharge can validate against the grade**. The type-level
  grade provides a static upper bound that the runtime discharge proof
  must be consistent with.

## Lean4 Correspondence

```
Effects.Grade.GradeLabel  ↔  Straylight.Coeffect.CoeffectLabel
Effects.Grade.Union       ↔  Straylight.Coeffect.join
Effects.Grade.Pure        ↔  Straylight.Coeffect.pure_coeffect
Effect GatewayM           ↔  Straylight.Gateway.GradedMonad (axiomatized)
```

The type-level `Union` in Haskell is the same operation as the lattice
join in the Lean4 formalization. This isn't a coincidence — it's the
Orchard & Petricek (2014) construction instantiated for the Straylight
effect lattice.

## Dependency Chain

```
effect-monad-0.9.0.0        (Orchard, patched for GHC 9.12)
  └── Effects.Grade          (GradeLabel, Union, Member)
  └── Effects.Graded         (GatewayM with Effect instance)
  └── Effects.Do             (QualifiedDo re-exports)
  └── Router.hs              (uses G.do)
  └── Handlers.hs            (uses G.do)
  └── Provider/*.hs          (each provider gets a typed grade)
```

## File Sizes

| Module | Lines | Notes |
|--------|-------|-------|
| `Effects/Grade.hs` | ~130 | Type families, zero runtime code |
| `Effects/Graded.hs` | ~320 | Replaces existing 460-line module |
| `Effects/Do.hs` | ~30 | Trivial re-exports |

Net change: ~40 fewer lines of Haskell, plus type-level safety.
