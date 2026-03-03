{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE StandaloneKindSignatures #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                           // Effects.Grade
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Type-level grade lattice for the gateway graded monad.
--
--  Effect categories form a bounded join-semilattice:
--
--      Pure ⊑ Net ⊑ Net∪Auth ⊑ ... ⊑ ⊤
--
--  Composition (Plus) is set union: if f : GatewayM '[Net] a and
--  g : GatewayM '[Auth] b, then (f >>= \_ -> g) : GatewayM '[Net, Auth] b.
--
--  This is the type-level tracking. Runtime cost data (latency, tokens,
--  timestamps) is still accumulated at the value level in GatewayGrade,
--  GatewayCoEffect, and GatewayProvenance — those are orthogonal.
--
--  Corresponds to Continuity.lean's Coeffect inductive type, lifted to kinds.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Effects.Grade
  ( -- * Effect labels
    GradeLabel (..)

    -- * Type-level set operations
  , Union
  , Member

    -- * Convenience aliases
  , Pure
  , NetOnly
  , AuthOnly
  , NetAuth
  , Full
  ) where

import Data.Kind (Constraint)

-- | Effect labels — the atoms of the grade lattice.
-- Each label corresponds to a category of side effect that
-- the gateway may perform. A computation's type-level grade
-- is a sorted, deduplicated list of these labels.
data GradeLabel
  = Net      -- ^ Network I/O (HTTP calls to providers)
  | Auth     -- ^ Authentication credential usage
  | Config   -- ^ Configuration access (env vars, files)
  | Log      -- ^ Structured logging / observability
  | Crypto   -- ^ Cryptographic operations (signing, hashing)
  | Fs       -- ^ Filesystem access outside sandbox
  deriving (Show, Eq, Ord)

-- ════════════════════════════════════════════════════════════════════════════
--                                              // type-level set operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Type-level sorted set union. This is the 'Plus' operation for our
-- graded monad: composing two computations unions their effect sets.
--
-- We maintain sorted order so that '[Net, Auth] ~ '[Auth, Net]' after
-- normalization. GHC's type family reduction handles this.
type family Union (xs :: [GradeLabel]) (ys :: [GradeLabel]) :: [GradeLabel] where
  Union '[]       ys        = ys
  Union xs        '[]       = xs
  Union (x ': xs) (x ': ys) = x ': Union xs ys       -- dedup
  Union (x ': xs) (y ': ys) = UnionOrd x y xs ys

-- | Helper: ordered merge based on label ordering.
-- We define a fixed total order matching the data constructor order:
-- Net < Auth < Config < Log < Crypto < Fs
type family UnionOrd (x :: GradeLabel) (y :: GradeLabel)
                     (xs :: [GradeLabel]) (ys :: [GradeLabel]) :: [GradeLabel] where
  -- Net < everything else
  UnionOrd 'Net    'Auth   xs ys = 'Net    ': Union xs ('Auth ': ys)
  UnionOrd 'Net    'Config xs ys = 'Net    ': Union xs ('Config ': ys)
  UnionOrd 'Net    'Log    xs ys = 'Net    ': Union xs ('Log ': ys)
  UnionOrd 'Net    'Crypto xs ys = 'Net    ': Union xs ('Crypto ': ys)
  UnionOrd 'Net    'Fs     xs ys = 'Net    ': Union xs ('Fs ': ys)
  -- Auth < Config, Log, Crypto, Fs
  UnionOrd 'Auth   'Net    xs ys = 'Net    ': Union ('Auth ': xs) ys
  UnionOrd 'Auth   'Config xs ys = 'Auth   ': Union xs ('Config ': ys)
  UnionOrd 'Auth   'Log    xs ys = 'Auth   ': Union xs ('Log ': ys)
  UnionOrd 'Auth   'Crypto xs ys = 'Auth   ': Union xs ('Crypto ': ys)
  UnionOrd 'Auth   'Fs     xs ys = 'Auth   ': Union xs ('Fs ': ys)
  -- Config < Log, Crypto, Fs
  UnionOrd 'Config 'Net    xs ys = 'Net    ': Union ('Config ': xs) ys
  UnionOrd 'Config 'Auth   xs ys = 'Auth   ': Union ('Config ': xs) ys
  UnionOrd 'Config 'Log    xs ys = 'Config ': Union xs ('Log ': ys)
  UnionOrd 'Config 'Crypto xs ys = 'Config ': Union xs ('Crypto ': ys)
  UnionOrd 'Config 'Fs     xs ys = 'Config ': Union xs ('Fs ': ys)
  -- Log < Crypto, Fs
  UnionOrd 'Log    'Net    xs ys = 'Net    ': Union ('Log ': xs) ys
  UnionOrd 'Log    'Auth   xs ys = 'Auth   ': Union ('Log ': xs) ys
  UnionOrd 'Log    'Config xs ys = 'Config ': Union ('Log ': xs) ys
  UnionOrd 'Log    'Crypto xs ys = 'Log    ': Union xs ('Crypto ': ys)
  UnionOrd 'Log    'Fs     xs ys = 'Log    ': Union xs ('Fs ': ys)
  -- Crypto < Fs
  UnionOrd 'Crypto 'Net    xs ys = 'Net    ': Union ('Crypto ': xs) ys
  UnionOrd 'Crypto 'Auth   xs ys = 'Auth   ': Union ('Crypto ': xs) ys
  UnionOrd 'Crypto 'Config xs ys = 'Config ': Union ('Crypto ': xs) ys
  UnionOrd 'Crypto 'Log    xs ys = 'Log    ': Union ('Crypto ': xs) ys
  UnionOrd 'Crypto 'Fs     xs ys = 'Crypto ': Union xs ('Fs ': ys)
  -- Fs is largest
  UnionOrd 'Fs     'Net    xs ys = 'Net    ': Union ('Fs ': xs) ys
  UnionOrd 'Fs     'Auth   xs ys = 'Auth   ': Union ('Fs ': xs) ys
  UnionOrd 'Fs     'Config xs ys = 'Config ': Union ('Fs ': xs) ys
  UnionOrd 'Fs     'Log    xs ys = 'Log    ': Union ('Fs ': xs) ys
  UnionOrd 'Fs     'Crypto xs ys = 'Crypto ': Union ('Fs ': xs) ys

-- | Type-level membership test (as a Constraint).
-- @Member 'Net es@ holds iff 'Net is in the sorted list @es@.
type family Member (x :: GradeLabel) (xs :: [GradeLabel]) :: Constraint where
  Member x (x ': _)  = ()
  Member x (_ ': xs) = Member x xs
  -- No instance for Member x '[] — gives a type error at the call site,
  -- which is exactly what we want: "you tried to do Net in a Pure context"

-- ════════════════════════════════════════════════════════════════════════════
--                                                     // convenience aliases
-- ════════════════════════════════════════════════════════════════════════════

-- | Pure computation — no effects.
type Pure = '[] :: [GradeLabel]

-- | Network-only computation.
type NetOnly = '[ 'Net ]

-- | Auth-only computation.
type AuthOnly = '[ 'Auth ]

-- | Network + Auth (the common case for provider calls).
type NetAuth = '[ 'Net, 'Auth ]

-- | Full effect set (everything).
type Full = '[ 'Net, 'Auth, 'Config, 'Log, 'Crypto, 'Fs ]
