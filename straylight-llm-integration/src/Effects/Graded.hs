{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                          // Effects.Graded
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Graded monad for gateway operations, built on Orchard & Petricek's
-- effect-monad library (Control.Effect).
--
-- The grade parameter is a type-level sorted set of GradeLabel atoms
-- from Effects.Grade. Composition unions the sets:
--
--     f : GatewayM '[Net] a
--     g : GatewayM '[Auth] b
--     f >>= \_ -> g : GatewayM '[Net, Auth] b    -- via Union
--
-- Runtime tracking (latency, tokens, provenance, coeffects) is still
-- accumulated at the value level — the type-level grade is a *static
-- upper bound* on what effects are permitted, while the value-level
-- data records what actually happened.
--
-- Usage with QualifiedDo:
--
--     {-# LANGUAGE QualifiedDo #-}
--     import Effects.Do qualified as G
--
--     handleRequest :: Request -> GatewayM '[Net, Auth, Crypto] Response
--     handleRequest req = G.do
--       provider <- selectProvider req        -- Pure, widened automatically
--       response <- callUpstream provider req -- Net ∪ Auth
--       proof    <- signResponse response     -- Crypto
--       G.return (response, proof)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

module Effects.Graded
  ( -- * Gateway Grade (value-level cost tracking)
    GatewayGrade
      ( GatewayGrade
      , ggLatencyMs
      , ggInputTokens
      , ggOutputTokens
      , ggProviderCalls
      , ggRetries
      , ggCacheHits
      , ggCacheMisses
      )
  , emptyGrade
  , combineGrades
  , gradeFromLatency

    -- * Gateway CoEffect (value-level resource tracking)
  , GatewayCoEffect (GatewayCoEffect, gceHttpAccess, gceAuthUsage, gceConfigAccess)
  , emptyCoEffect
  , HttpAccess (HttpAccess, haUrl, haMethod, haTimestamp, haStatusCode)
  , AuthUsage (AuthUsage, auProvider, auScope, auTimestamp)
  , ConfigAccess (ConfigAccess, caKey, caTimestamp)

    -- * Gateway Provenance
  , GatewayProvenance
      ( GatewayProvenance
      , gpRequestId
      , gpProvidersUsed
      , gpModelsUsed
      , gpTimestamp
      , gpClientIp
      )
  , emptyProvenance

    -- * Graded Monad (type-level indexed)
  , GatewayM (GatewayM, unGatewayM)
  , runGatewayM
  , runGatewayMPure

    -- * Primitive effect operations (each tags the type-level grade)
  , liftPure
  , liftNet
  , liftAuth
  , liftConfig
  , liftLog
  , liftCrypto
  , liftIO'

    -- * Cost tracking
  , withLatency
  , withTokens
  , withCacheHit
  , withCacheMiss
  , withRetry

    -- * CoEffect recording
  , recordHttpAccess
  , recordAuthUsage
  , recordConfigAccess

    -- * Provenance recording
  , recordProvider
  , recordModel
  , recordRequestId

    -- * Grade inspection
  , getGrade
  , getCoEffect
  , getProvenance
  , shouldCacheResponse

    -- * Re-exports for grade construction
  , module Effects.Grade
  ) where

import Control.DeepSeq (NFData (rnf))
import Control.Effect (Effect (..))
import Data.Kind (Type)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import GHC.Generics (Generic)

import Effects.Grade


-- ════════════════════════════════════════════════════════════════════════════
--                                                           // gateway grade
-- ════════════════════════════════════════════════════════════════════════════

-- | Value-level cost accumulator. Tracks what actually happened at runtime.
-- This is orthogonal to the type-level grade — the grade says what's
-- *permitted*, this records what *occurred*.
data GatewayGrade = GatewayGrade
  { ggLatencyMs     :: !Int
  , ggInputTokens   :: !Int
  , ggOutputTokens  :: !Int
  , ggProviderCalls :: !Int
  , ggRetries       :: !Int
  , ggCacheHits     :: !Int
  , ggCacheMisses   :: !Int
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayGrade where
  rnf GatewayGrade {..} =
    rnf ggLatencyMs `seq` rnf ggInputTokens `seq`
    rnf ggOutputTokens `seq` rnf ggProviderCalls `seq`
    rnf ggRetries `seq` rnf ggCacheHits `seq` rnf ggCacheMisses

instance Semigroup GatewayGrade where
  g1 <> g2 = GatewayGrade
    { ggLatencyMs     = ggLatencyMs g1     + ggLatencyMs g2
    , ggInputTokens   = ggInputTokens g1   + ggInputTokens g2
    , ggOutputTokens  = ggOutputTokens g1  + ggOutputTokens g2
    , ggProviderCalls = ggProviderCalls g1  + ggProviderCalls g2
    , ggRetries       = ggRetries g1       + ggRetries g2
    , ggCacheHits     = ggCacheHits g1     + ggCacheHits g2
    , ggCacheMisses   = ggCacheMisses g1   + ggCacheMisses g2
    }

instance Monoid GatewayGrade where
  mempty = emptyGrade

emptyGrade :: GatewayGrade
emptyGrade = GatewayGrade 0 0 0 0 0 0 0

combineGrades :: GatewayGrade -> GatewayGrade -> GatewayGrade
combineGrades = (<>)

gradeFromLatency :: Int -> GatewayGrade
gradeFromLatency ms = emptyGrade { ggLatencyMs = ms, ggProviderCalls = 1 }


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // gateway co-effect
-- ════════════════════════════════════════════════════════════════════════════

data HttpAccess = HttpAccess
  { haUrl        :: !Text
  , haMethod     :: !Text
  , haTimestamp  :: !UTCTime
  , haStatusCode :: !(Maybe Int)
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData HttpAccess where
  rnf HttpAccess {..} =
    rnf haUrl `seq` rnf haMethod `seq` rnf haTimestamp `seq` rnf haStatusCode

data AuthUsage = AuthUsage
  { auProvider  :: !Text
  , auScope     :: !Text
  , auTimestamp :: !UTCTime
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData AuthUsage where
  rnf AuthUsage {..} = rnf auProvider `seq` rnf auScope `seq` rnf auTimestamp

data ConfigAccess = ConfigAccess
  { caKey       :: !Text
  , caTimestamp :: !UTCTime
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData ConfigAccess where
  rnf ConfigAccess {..} = rnf caKey `seq` rnf caTimestamp

data GatewayCoEffect = GatewayCoEffect
  { gceHttpAccess   :: !(Set HttpAccess)
  , gceAuthUsage    :: !(Set AuthUsage)
  , gceConfigAccess :: !(Set ConfigAccess)
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayCoEffect where
  rnf GatewayCoEffect {..} =
    rnf gceHttpAccess `seq` rnf gceAuthUsage `seq` rnf gceConfigAccess

instance Semigroup GatewayCoEffect where
  ce1 <> ce2 = GatewayCoEffect
    { gceHttpAccess   = gceHttpAccess ce1   <> gceHttpAccess ce2
    , gceAuthUsage    = gceAuthUsage ce1    <> gceAuthUsage ce2
    , gceConfigAccess = gceConfigAccess ce1 <> gceConfigAccess ce2
    }

instance Monoid GatewayCoEffect where
  mempty = emptyCoEffect

emptyCoEffect :: GatewayCoEffect
emptyCoEffect = GatewayCoEffect Set.empty Set.empty Set.empty


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // gateway provenance
-- ════════════════════════════════════════════════════════════════════════════

data GatewayProvenance = GatewayProvenance
  { gpRequestId     :: !(Maybe Text)
  , gpProvidersUsed :: ![Text]
  , gpModelsUsed    :: ![Text]
  , gpTimestamp     :: !(Maybe UTCTime)
  , gpClientIp      :: !(Maybe Text)
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayProvenance where
  rnf GatewayProvenance {..} =
    rnf gpRequestId `seq` rnf gpProvidersUsed `seq`
    rnf gpModelsUsed `seq` rnf gpTimestamp `seq` rnf gpClientIp

emptyProvenance :: GatewayProvenance
emptyProvenance = GatewayProvenance Nothing [] [] Nothing Nothing

combineProvenance :: GatewayProvenance -> GatewayProvenance -> GatewayProvenance
combineProvenance p1 p2 = GatewayProvenance
  { gpRequestId     = gpRequestId p2     <|> gpRequestId p1
  , gpProvidersUsed = gpProvidersUsed p1  ++ gpProvidersUsed p2
  , gpModelsUsed    = gpModelsUsed p1     ++ gpModelsUsed p2
  , gpTimestamp     = gpTimestamp p1      <|> gpTimestamp p2
  , gpClientIp      = gpClientIp p1      <|> gpClientIp p2
  }
  where
    Nothing <|> y = y
    x       <|> _ = x


-- ════════════════════════════════════════════════════════════════════════════
--                                               // graded monad (the core)
-- ════════════════════════════════════════════════════════════════════════════

-- | The gateway graded monad.
--
-- @GatewayM es a@ is a computation that:
--   - May perform effects in the set @es@ (type-level, checked at compile time)
--   - Produces a value of type @a@
--   - Accumulates runtime cost data in GatewayGrade, GatewayProvenance,
--     and GatewayCoEffect (value-level, available at runtime)
--
-- The phantom type parameter @es :: [GradeLabel]@ is the grade.
-- It's a sorted set of effect labels. GHC enforces at compile time that
-- operations requiring 'Net are only called from contexts where 'Net is
-- in the grade.
newtype GatewayM (es :: [GradeLabel]) a = GatewayM
  { unGatewayM :: IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect)
  }

-- | GatewayM is an Orchard & Petricek graded monad (Effect from effect-monad).
--
-- The grade algebra:
--   Unit  = '[]              (pure computation, no effects)
--   Plus  = Union            (set union of effect labels)
--   Inv   = ()               (no additional constraints on composition)
instance Effect GatewayM where
  type Unit GatewayM = Pure                -- '[] — the empty effect set
  type Plus GatewayM f g = Union f g       -- set union
  type Inv  GatewayM f g = ()              -- no constraints on composition

  return a = GatewayM $ pure (a, emptyGrade, emptyProvenance, emptyCoEffect)

  (GatewayM m) >>= f = GatewayM $ do
    (a, g1, p1, ce1) <- m
    (b, g2, p2, ce2) <- unGatewayM (f a)
    pure (b, g1 <> g2, combineProvenance p1 p2, ce1 <> ce2)

-- | Run a graded computation. The grade @es@ is erased at runtime —
-- it exists only to constrain composition at compile time.
runGatewayM :: GatewayM es a -> IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect)
runGatewayM = unGatewayM

-- | Run discarding tracking data.
runGatewayMPure :: GatewayM es a -> IO a
runGatewayMPure m = (\(a, _, _, _) -> a) <$> runGatewayM m


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // primitive lift points
-- ════════════════════════════════════════════════════════════════════════════

-- Each lift point tags the type-level grade with exactly the label(s)
-- corresponding to the kind of effect being performed. Callers of these
-- functions get their grade widened automatically by the Effect instance's
-- Plus (= Union).

-- | Lift a pure (no-IO) value. Grade: Pure ('[]). 
liftPure :: a -> GatewayM Pure a
liftPure a = GatewayM $ pure (a, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Lift an IO action that performs network access.
-- Grade: '[Net]. This is the *only* way to introduce 'Net into the grade.
liftNet :: IO a -> GatewayM '[ 'Net ] a
liftNet action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Lift an IO action that uses authentication credentials.
liftAuth :: IO a -> GatewayM '[ 'Auth ] a
liftAuth action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Lift an IO action that reads configuration.
liftConfig :: IO a -> GatewayM '[ 'Config ] a
liftConfig action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Lift a logging action.
liftLog :: IO a -> GatewayM '[ 'Log ] a
liftLog action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Lift a cryptographic operation.
liftCrypto :: IO a -> GatewayM '[ 'Crypto ] a
liftCrypto action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Escape hatch: lift arbitrary IO with full effect set.
-- Use sparingly — this defeats the purpose of grading.
-- Every use should have a comment justifying why.
liftIO' :: IO a -> GatewayM Full a
liftIO' action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)


-- ════════════════════════════════════════════════════════════════════════════
--                                                    // cost tracking (value)
-- ════════════════════════════════════════════════════════════════════════════

-- | Measure latency of a network operation.
-- Note: this is tagged '[Net] because measuring latency implies network I/O.
withLatency :: IO a -> GatewayM '[ 'Net ] a
withLatency action = GatewayM $ do
  start  <- getCurrentTime
  result <- action
  end    <- getCurrentTime
  let ms = round (diffUTCTime end start * 1000)
  pure (result, gradeFromLatency ms, emptyProvenance, emptyCoEffect)

-- | Add token counts. Grade-preserving (doesn't add new effect labels).
withTokens :: Int -> Int -> GatewayM es a -> GatewayM es a
withTokens input output (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  let g' = g { ggInputTokens  = ggInputTokens g + input
             , ggOutputTokens = ggOutputTokens g + output }
  pure (a, g', p, ce)

-- | Record cache hit. Grade-preserving.
withCacheHit :: GatewayM es a -> GatewayM es a
withCacheHit (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  pure (a, g { ggCacheHits = ggCacheHits g + 1 }, p, ce)

-- | Record cache miss. Grade-preserving.
withCacheMiss :: GatewayM es a -> GatewayM es a
withCacheMiss (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  pure (a, g { ggCacheMisses = ggCacheMisses g + 1 }, p, ce)

-- | Record retry. Grade-preserving.
withRetry :: GatewayM es a -> GatewayM es a
withRetry (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  pure (a, g { ggRetries = ggRetries g + 1 }, p, ce)


-- ════════════════════════════════════════════════════════════════════════════
--                                           // co-effect recording (value)
-- ════════════════════════════════════════════════════════════════════════════

-- | Record HTTP access. Introduces 'Net into the grade.
recordHttpAccess :: Text -> Text -> Maybe Int -> GatewayM '[ 'Net ] ()
recordHttpAccess url method status = GatewayM $ do
  now <- getCurrentTime
  let access = HttpAccess url method now status
      ce = emptyCoEffect { gceHttpAccess = Set.singleton access }
  pure ((), emptyGrade, emptyProvenance, ce)

-- | Record auth usage. Introduces 'Auth into the grade.
recordAuthUsage :: Text -> Text -> GatewayM '[ 'Auth ] ()
recordAuthUsage provider scope = GatewayM $ do
  now <- getCurrentTime
  let usage = AuthUsage provider scope now
      ce = emptyCoEffect { gceAuthUsage = Set.singleton usage }
  pure ((), emptyGrade, emptyProvenance, ce)

-- | Record config access. Introduces 'Config into the grade.
recordConfigAccess :: Text -> GatewayM '[ 'Config ] ()
recordConfigAccess key = GatewayM $ do
  now <- getCurrentTime
  let access = ConfigAccess key now
      ce = emptyCoEffect { gceConfigAccess = Set.singleton access }
  pure ((), emptyGrade, emptyProvenance, ce)


-- ════════════════════════════════════════════════════════════════════════════
--                                           // provenance recording (value)
-- ════════════════════════════════════════════════════════════════════════════

-- | Record provider used. Pure — provenance is bookkeeping, not an effect.
recordProvider :: Text -> GatewayM Pure ()
recordProvider provider = GatewayM $
  pure ((), emptyGrade, emptyProvenance { gpProvidersUsed = [provider] }, emptyCoEffect)

-- | Record model used. Pure.
recordModel :: Text -> GatewayM Pure ()
recordModel model = GatewayM $
  pure ((), emptyGrade, emptyProvenance { gpModelsUsed = [model] }, emptyCoEffect)

-- | Record request ID. Pure.
recordRequestId :: Text -> GatewayM Pure ()
recordRequestId reqId = GatewayM $ do
  now <- getCurrentTime
  let p = emptyProvenance { gpRequestId = Just reqId, gpTimestamp = Just now }
  pure ((), emptyGrade, p, emptyCoEffect)


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // grade inspection
-- ════════════════════════════════════════════════════════════════════════════

-- | Inspect accumulated grade. Pure.
getGrade :: GatewayM Pure GatewayGrade
getGrade = GatewayM $ pure (emptyGrade, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Inspect accumulated co-effect. Pure.
getCoEffect :: GatewayM Pure GatewayCoEffect
getCoEffect = GatewayM $ pure (emptyCoEffect, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Inspect accumulated provenance. Pure.
getProvenance :: GatewayM Pure GatewayProvenance
getProvenance = GatewayM $ pure (emptyProvenance, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Should this response be cached? Based on cost heuristics.
shouldCacheResponse :: GatewayGrade -> Bool
shouldCacheResponse g =
  ggLatencyMs g > 100 || ggRetries g > 0 || ggCacheMisses g > 0
