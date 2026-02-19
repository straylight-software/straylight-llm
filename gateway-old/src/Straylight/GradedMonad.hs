{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

{- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                 // straylight // graded-monad
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -}

{- |
   "He closed his eyes. Found the ridged face of the power
    stud. And in the bloodlit dark behind his eyes, silver
    phosphenes boiling in from the edge of space, hypnagogic
    images jerking past like film compiled from random frames."

                                                               — Neuromancer

   Graded monads for tracking coeffects through computation.
   n.b. corresponds to Lean4 Straylight.GradedMonad.

   A graded monad M indexed by a coeffect semiring R satisfies:
   - return : A → M[0] A
   - bind   : M[r] A → (A → M[s] B) → M[r ⊔ s] B
-}
module Straylight.GradedMonad
  ( -- // graded // io
    GIO (..)
    -- // graded // operations
  , gpure
  , gbind
  , gmap
  , gseq
    -- // lifting // operations
  , liftIO
  , netRead
  , netWrite
  , gpuInfer
    -- // running
  , runGIO
  ) where

import Straylight.Coeffect


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // graded // io
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Graded IO monad — IO indexed by coeffects.
--   The phantom type parameter tracks resource usage at the type level.
newtype GIO (c :: *) a = GIO { unGIO :: IO a }
  deriving stock (Functor)

-- | Run a graded IO action, discarding the coeffect information.
--   n.b. this is the "escape hatch" that erases coeffect tracking
runGIO :: GIO c a -> IO a
runGIO = unGIO


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // graded // operations
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Pure computation with zero coeffect.
--   cf. Lean4 GradedMonad.gpure
gpure :: a -> GIO Pure a
gpure = GIO . pure

-- | Graded bind — coeffects compose via join.
--   cf. Lean4 GradedMonad.gbind
--
--   Note: In full dependent types, the return type would be:
--     GIO (Join r s) b
--   In Haskell, we approximate with unconstrained output coeffect.
gbind :: GIO r a -> (a -> GIO s b) -> GIO (Join r s) b
gbind (GIO ma) f = GIO $ do
  a <- ma
  unGIO (f a)

-- | Graded map
gmap :: (a -> b) -> GIO r a -> GIO r b
gmap f (GIO ma) = GIO (f <$> ma)

-- | Graded sequence — run two actions, keeping second result
gseq :: GIO r a -> GIO s b -> GIO (Join r s) b
gseq ma mb = gbind ma (const mb)

-- | Infix operator for graded bind
infixl 1 `gbind`


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // lifting // operations
   ════════════════════════════════════════════════════════════════════════════════ -}

-- | Lift an arbitrary IO action with explicit coeffect annotation.
--   n.b. caller is responsible for correct coeffect
liftIO :: SCoeffect c -> IO a -> GIO c a
liftIO _ = GIO

-- | Read from network with tracked coeffect
netRead :: IO a -> GIO NetRead a
netRead = GIO

-- | Write to network with tracked coeffect
netWrite :: IO a -> GIO NetReadWrite a
netWrite = GIO

-- | GPU inference operation with tracked coeffect
gpuInfer :: IO a -> GIO GpuInference a
gpuInfer = GIO


{- ════════════════════════════════════════════════════════════════════════════════
                                                        // applicative // instance
   ════════════════════════════════════════════════════════════════════════════════ -}

-- Note: We can't have a proper Applicative/Monad instance because
-- the coeffects would need to be tracked at the type level.
-- Instead, users must use gpure and gbind explicitly.
--
-- For ergonomics, we provide these helpers that work within a
-- single coeffect level:

-- | Applicative-like operation within same coeffect
gapply :: GIO c (a -> b) -> GIO c a -> GIO c b
gapply (GIO mf) (GIO ma) = GIO (mf <*> ma)

-- | Monad-like bind within same coeffect
gbindSame :: GIO c a -> (a -> GIO c b) -> GIO c b
gbindSame (GIO ma) f = GIO (ma >>= unGIO . f)
