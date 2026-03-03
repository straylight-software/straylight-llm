# effect-monad 0.9.0.0 — GHC 9.12 Modernization

**Orchard & Petricek (2014), dusted off for 2026.**

1,145 lines across 22 source modules → 24 modules (2 new).
692-line unified diff. Zero behavioral changes to existing code.

---

## What This Is

Dominic Orchard's `effect-monad` library implements *graded monads* and
*parametric coeffect comonads* — the type-theoretic machinery behind
Straylight's `GatewayM`. Last touched in 2017 (tested-with: GHC 8.2.2).
This patch modernizes it for GHC 9.12 while preserving every existing
API contract.

---

## Changes by Category

### Blockers Fixed (wouldn't compile on 9.x)

| Issue | File | Fix |
|-------|------|-----|
| **B1.** `fail = undefined` — bare top-level, no type sig, collides with `MonadFail.fail` | `Control.Effect` | Added `fail :: String -> a` with type sig, `= error` (was `= undefined`), explicit export. Documented as RebindableSyntax escape hatch. |
| **B2.** Module-wide `IncoherentInstances` | `Control.Effect.State` | Removed pragma. Added per-instance `{-# OVERLAPPING #-}` on `Show (Var "x"/"y"/"z")` and the two specific `Nubable`/`Update` instances. `{-# OVERLAPPABLE #-}` on the catch-all `Show (Var v)` and the generic `Nubable`/`Update` fallback instances. Semantically identical resolution, no incoherence. |

### Deprecation Fixes (warnings on 9.x)

| Issue | Files | Fix |
|-------|-------|-----|
| **D1.** `mappend` → `(<>)` | `Writer` | `Nubable` instance: `Monoid u` constraint → `Semigroup u`, `mappend` → `(<>)`. Import `Data.Monoid` removed. |
| **D2.** `GHC.Exts (Constraint)` | `Effect`, `Coeffect`, `Cond`, `Reader` | → `Data.Kind (Constraint, Type)` single import. |
| **D3.** `EmptyDataDecls` pragma | `Counter`, `Maybe`, `Update`, `Vector`, `SafeFiles` | Removed (no-op since GHC 7.2). |
| **D4.** Redundant `KindSignatures` | `Effect`, `List`, `Parameterised`, `SafeFiles`, `Reader`, `WriteOnceWriter`, `ParameterisedAsGraded` | Removed (implied by `PolyKinds` or `DataKinds`). |
| **D5.** `TypeSynonymInstances` | `Vector` | Removed (no-op since GHC 7.4). |
| **D6.** Duplicate `KindSignatures` | `Helpers/List` | De-duplicated. |

### New: QualifiedDo Support

Two new modules that are the structural modernization:

**`Control.Effect.Do`** — graded monadic `do`-notation without `RebindableSyntax`:

```haskell
{-# LANGUAGE QualifiedDo #-}
import Control.Effect.Do qualified as E

example :: Counter 2 Int
example = E.do
  x <- tick 1
  y <- tick 2
  E.return (x + y)
```

**`Control.Coeffect.Do`** — parallel module for the comonadic side.

Why this matters:
- `RebindableSyntax` hijacks *all* `do`-blocks in a module. `QualifiedDo` is surgical — `E.do` uses graded bind, regular `do` uses `Prelude.(>>=)`, both coexist in the same function.
- HLS, hlint, ormolu, fourmolu all handle `QualifiedDo` correctly (landed in GHC 9.0, tooling caught up by 9.4).
- Existing `RebindableSyntax` code continues to work unchanged.

### Cabal File

- `cabal-version: >= 1.6` → `2.4`
- `license: BSD3` → `BSD-3-Clause` (SPDX)
- `tested-with: GHC == 9.12.2`
- `default-language: Haskell2010` added (was missing)
- `base >= 4.18 && < 5` (GHC 9.6+ — could lower if needed, 4.18 is conservative floor for `Data.Kind (Constraint)` stability)
- `-Wall -Wno-orphans -Wno-unused-imports -Wno-name-shadowing`
- Version bump `0.8.0.0` → `0.9.0.0` (new modules = minor version bump per PVP)

### Cosmetic

- Explicit export lists on `Control.Coeffect` (was bare `where`)
- Typo fixes: "Cominbing" → "Combining", "coeffec" → "coeffect", "indicies" → "indices", "copmutations" → "computations"
- Trailing whitespace cleaned
- Dead commented-out code removed from `State.hs` (the `Subeffect State` instance that was never finished)
- Missing trailing newlines added

---

## Files Unchanged

These required no modifications:

- `Control.Effect.Monad` — trivial graded wrapper over `Prelude.Monad`, already clean
- `Control.Effect.CounterNat` — uses `GHC.TypeLits.Nat`, no deprecated features
- `Control.Effect.ReadOnceReader` — no deprecated imports
- `Control.Coeffect.Coreader` — clean `Data.Kind` import already present
- `Control.Effect.Parameterised` — only removed redundant `KindSignatures`
- `Control.Effect.Parameterised.State` — already clean
- `Control.Effect.Parameterised.AtomicState` — already clean
- `Control.Effect.Parameterised.ExtensibleState` — uses `RebindableSyntax` from `Parameterised`, clean

---

## Dependency Risk: type-level-sets

`type-level-sets >= 0.8.7.0` is also Orchard's package. Used by 5 modules:
`State`, `Writer`, `Reader`, `Coreader`, `ExtensibleState`.

The core `Effect` and `Coeffect` classes have **zero** dependency on it.
If `type-level-sets` doesn't build on 9.12, only the set-indexed instances
break — the fundamental graded monad / coeffect comonad machinery works fine.

`type-level-sets` likely needs the same treatment (it uses similar vintage
GHC extensions). That's a separate patch but same shape of work.

---

## What's NOT in This Patch

Things deliberately left for a follow-up:

1. **`GHC2024` as default-language** — would eliminate many per-file pragmas
   but forces GHC 9.12+ as minimum. `Haskell2010` keeps broader compat.

2. **Type-level grading via `DataKinds`** — the `Effect` class tracks grades
   at the type level already (that's the whole point). What's missing is
   enforcing that `IO` operations can't sneak in untracked. That's the
   `GatewayM` integration work, not a library-level change.

3. **Test suite** — the library has zero tests. The examples serve as
   integration tests but there's no `cabal test` target. Would be good
   to add `hspec` or `tasty` with the examples as test cases.

4. **Haddock pass** — documentation compiles but many modules lack
   top-level module docs. The papers are linked but the connection
   between `Control.Effect.State` and Section 4 of Orchard & Petricek
   (2014) should be explicit.

---

## For Straylight

This positions `effect-monad` as the foundation for `GatewayM`'s graded monad
claim. Instead of hand-rolling type-level lattice plumbing:

```haskell
-- Current straylight-llm: DIY writer-monad with aspirational "graded" label
newtype GatewayM a = GatewayM (IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect))

-- With effect-monad 0.9: actual Orchard & Petricek graded monad
instance Effect GatewayM where
    type Unit GatewayM = 'Pure
    type Plus GatewayM f g = Merge f g  -- type-level lattice join
    type Inv  GatewayM f g = ()
    ...
```

The `QualifiedDo` module means handler code reads naturally:

```haskell
import Control.Effect.Do qualified as G

handleRequest :: Request -> G.do  -- graded do-notation
  provider <- G.return (selectProvider req)  -- Pure
  response <- callUpstream provider req      -- Net ∪ Auth
  proof    <- generateProof response         -- Net ∪ Auth ∪ Crypto
  G.return (response, proof)
```

Cite: Orchard, D. & Petricek, T. (2014). "Embedding effect systems in Haskell."
*Haskell Symposium*. http://dorchard.co.uk/publ/haskell14-effects.pdf
