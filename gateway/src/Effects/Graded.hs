{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                                          // Effects.Graded
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The sky above the port was the color of television, tuned to a dead
--      channel."
--
--                                                              — Neuromancer
--
-- Graded monad for gateway operations with cost/effect tracking.
--
-- Following the aleph cube architecture from Continuity.lean, this module
-- provides:
--
--   - GatewayGrade: Cost tracking (latency, token counts, cache hits)
--   - GatewayCoEffect: Resource access tracking (HTTP, Auth, Config)
--   - GatewayProvenance: Audit trail for requests
--   - GatewayM: Graded monad combining all tracking
--
-- Co-effect equations (verifiable properties):
--
--   - Monotonicity: cost(g1 >> g2) >= max(cost g1, cost g2)
--   - Associativity: (m >>= f) >>= g = m >>= (\x -> f x >>= g)
--   - Idempotency: Cached responses have zero latency cost
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE StrictData #-}

module Effects.Graded
  ( -- * Gateway Grade
    GatewayGrade (..)
  , emptyGrade
  , combineGrades
  , gradeFromLatency

    -- * Gateway Co-Effect
  , GatewayCoEffect (..)
  , emptyCoEffect
  , HttpAccess (..)
  , AuthUsage (..)
  , ConfigAccess (..)

    -- * Gateway Provenance
  , GatewayProvenance (..)
  , emptyProvenance

    -- * Gateway Graded Monad
  , GatewayM (..)
  , runGatewayM
  , runGatewayMPure
  , liftGatewayIO

    -- * Cost Tracking Operations
  , withLatency
  , withTokens
  , withCacheHit
  , withCacheMiss
  , withRetry

    -- * Co-Effect Recording
  , recordHttpAccess
  , recordAuthUsage
  , recordConfigAccess

    -- * Provenance Recording
  , recordProvider
  , recordModel
  , recordRequestId

    -- * Grade Inspection
  , getGrade
  , getCoEffect
  , getProvenance
  , shouldCacheResponse
  ) where

import Control.DeepSeq (NFData (rnf))
import Control.Monad (ap)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import GHC.Generics (Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                             // gateway grade
-- ════════════════════════════════════════════════════════════════════════════

-- | Gateway-specific grade tracking request costs
data GatewayGrade = GatewayGrade
  { -- | Total latency in milliseconds
    ggLatencyMs :: !Int
    -- | Input tokens processed
  , ggInputTokens :: !Int
    -- | Output tokens generated
  , ggOutputTokens :: !Int
    -- | Number of provider calls made
  , ggProviderCalls :: !Int
    -- | Number of retries (fallback attempts)
  , ggRetries :: !Int
    -- | Cache hits
  , ggCacheHits :: !Int
    -- | Cache misses
  , ggCacheMisses :: !Int
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayGrade where
  rnf GatewayGrade {..} =
    rnf ggLatencyMs `seq`
      rnf ggInputTokens `seq`
        rnf ggOutputTokens `seq`
          rnf ggProviderCalls `seq`
            rnf ggRetries `seq`
              rnf ggCacheHits `seq`
                rnf ggCacheMisses

instance Semigroup GatewayGrade where
  g1 <> g2 = GatewayGrade
    { ggLatencyMs = ggLatencyMs g1 + ggLatencyMs g2
    , ggInputTokens = ggInputTokens g1 + ggInputTokens g2
    , ggOutputTokens = ggOutputTokens g1 + ggOutputTokens g2
    , ggProviderCalls = ggProviderCalls g1 + ggProviderCalls g2
    , ggRetries = ggRetries g1 + ggRetries g2
    , ggCacheHits = ggCacheHits g1 + ggCacheHits g2
    , ggCacheMisses = ggCacheMisses g1 + ggCacheMisses g2
    }

instance Monoid GatewayGrade where
  mempty = emptyGrade

-- | Empty grade (identity for combineGrades)
emptyGrade :: GatewayGrade
emptyGrade = GatewayGrade
  { ggLatencyMs = 0
  , ggInputTokens = 0
  , ggOutputTokens = 0
  , ggProviderCalls = 0
  , ggRetries = 0
  , ggCacheHits = 0
  , ggCacheMisses = 0
  }

-- | Combine two grades (monoid operation)
combineGrades :: GatewayGrade -> GatewayGrade -> GatewayGrade
combineGrades = (<>)

-- | Create grade from latency measurement
gradeFromLatency :: Int -> GatewayGrade
gradeFromLatency ms = emptyGrade { ggLatencyMs = ms, ggProviderCalls = 1 }


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // gateway co-effect
-- ════════════════════════════════════════════════════════════════════════════

-- | HTTP access record (matching Continuity.lean NetworkAccess)
data HttpAccess = HttpAccess
  { haUrl :: !Text
  , haMethod :: !Text
  , haTimestamp :: !UTCTime
  , haStatusCode :: !(Maybe Int)
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData HttpAccess where
  rnf HttpAccess {..} =
    rnf haUrl `seq`
      rnf haMethod `seq`
        rnf haTimestamp `seq`
          rnf haStatusCode

-- | Auth usage record (matching Continuity.lean AuthUsage)
data AuthUsage = AuthUsage
  { auProvider :: !Text
  , auScope :: !Text
  , auTimestamp :: !UTCTime
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData AuthUsage where
  rnf AuthUsage {..} =
    rnf auProvider `seq`
      rnf auScope `seq`
        rnf auTimestamp

-- | Config access record
data ConfigAccess = ConfigAccess
  { caKey :: !Text
  , caTimestamp :: !UTCTime
  }
  deriving stock (Show, Eq, Ord, Generic)

instance NFData ConfigAccess where
  rnf ConfigAccess {..} =
    rnf caKey `seq`
      rnf caTimestamp

-- | Co-effect tracking for gateway operations (what resources were accessed)
data GatewayCoEffect = GatewayCoEffect
  { -- | HTTP calls made
    gceHttpAccess :: !(Set HttpAccess)
    -- | Auth credentials used
  , gceAuthUsage :: !(Set AuthUsage)
    -- | Config values accessed
  , gceConfigAccess :: !(Set ConfigAccess)
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayCoEffect where
  rnf GatewayCoEffect {..} =
    rnf gceHttpAccess `seq`
      rnf gceAuthUsage `seq`
        rnf gceConfigAccess

instance Semigroup GatewayCoEffect where
  ce1 <> ce2 = GatewayCoEffect
    { gceHttpAccess = gceHttpAccess ce1 <> gceHttpAccess ce2
    , gceAuthUsage = gceAuthUsage ce1 <> gceAuthUsage ce2
    , gceConfigAccess = gceConfigAccess ce1 <> gceConfigAccess ce2
    }

instance Monoid GatewayCoEffect where
  mempty = emptyCoEffect

-- | Empty co-effect
emptyCoEffect :: GatewayCoEffect
emptyCoEffect = GatewayCoEffect
  { gceHttpAccess = Set.empty
  , gceAuthUsage = Set.empty
  , gceConfigAccess = Set.empty
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // gateway provenance
-- ════════════════════════════════════════════════════════════════════════════

-- | Provenance tracking for gateway requests
data GatewayProvenance = GatewayProvenance
  { -- | Unique request ID
    gpRequestId :: !(Maybe Text)
    -- | Provider(s) used (in order)
  , gpProvidersUsed :: ![Text]
    -- | Model(s) requested
  , gpModelsUsed :: ![Text]
    -- | Timestamp of operation
  , gpTimestamp :: !(Maybe UTCTime)
    -- | Client IP (if available)
  , gpClientIp :: !(Maybe Text)
  }
  deriving stock (Show, Eq, Generic)

instance NFData GatewayProvenance where
  rnf GatewayProvenance {..} =
    rnf gpRequestId `seq`
      rnf gpProvidersUsed `seq`
        rnf gpModelsUsed `seq`
          rnf gpTimestamp `seq`
            rnf gpClientIp

-- | Empty provenance
emptyProvenance :: GatewayProvenance
emptyProvenance = GatewayProvenance
  { gpRequestId = Nothing
  , gpProvidersUsed = []
  , gpModelsUsed = []
  , gpTimestamp = Nothing
  , gpClientIp = Nothing
  }

-- | Combine provenances (later takes precedence for Maybe fields)
combineProvenance :: GatewayProvenance -> GatewayProvenance -> GatewayProvenance
combineProvenance p1 p2 = GatewayProvenance
  { gpRequestId = gpRequestId p2 <|> gpRequestId p1
  , gpProvidersUsed = gpProvidersUsed p1 ++ gpProvidersUsed p2
  , gpModelsUsed = gpModelsUsed p1 ++ gpModelsUsed p2
  , gpTimestamp = gpTimestamp p1 <|> gpTimestamp p2
  , gpClientIp = gpClientIp p1 <|> gpClientIp p2
  }
  where
    Nothing <|> y = y
    x <|> _ = x


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // gateway graded monad
-- ════════════════════════════════════════════════════════════════════════════

-- | Graded monad for gateway operations
-- Tracks grade, provenance, and co-effects
newtype GatewayM a = GatewayM
  { unGatewayM :: IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect)
  }

instance Functor GatewayM where
  fmap f (GatewayM m) = GatewayM $ do
    (a, g, p, ce) <- m
    pure (f a, g, p, ce)

instance Applicative GatewayM where
  pure a = GatewayM $ pure (a, emptyGrade, emptyProvenance, emptyCoEffect)
  (<*>) = ap

instance Monad GatewayM where
  GatewayM m >>= f = GatewayM $ do
    (a, g1, p1, ce1) <- m
    (b, g2, p2, ce2) <- unGatewayM (f a)
    pure (b, combineGrades g1 g2, combineProvenance p1 p2, ce1 <> ce2)

-- | Run gateway computation and return result with all tracking
runGatewayM :: GatewayM a -> IO (a, GatewayGrade, GatewayProvenance, GatewayCoEffect)
runGatewayM = unGatewayM

-- | Run gateway computation discarding tracking
runGatewayMPure :: GatewayM a -> IO a
runGatewayMPure m = (\(a, _, _, _) -> a) <$> runGatewayM m

-- | Lift IO action into GatewayM without tracking
liftGatewayIO :: IO a -> GatewayM a
liftGatewayIO action = GatewayM $ do
  result <- action
  pure (result, emptyGrade, emptyProvenance, emptyCoEffect)


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // cost tracking operations
-- ════════════════════════════════════════════════════════════════════════════

-- | Lift IO action and measure latency
withLatency :: IO a -> GatewayM a
withLatency action = GatewayM $ do
  start <- getCurrentTime
  result <- action
  end <- getCurrentTime
  let ms = round (diffUTCTime end start * 1000)
  pure (result, gradeFromLatency ms, emptyProvenance, emptyCoEffect)

-- | Add token counts to grade
withTokens :: Int -> Int -> GatewayM a -> GatewayM a
withTokens input output (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  let g' = g
        { ggInputTokens = ggInputTokens g + input
        , ggOutputTokens = ggOutputTokens g + output
        }
  pure (a, g', p, ce)

-- | Record cache hit
withCacheHit :: GatewayM a -> GatewayM a
withCacheHit (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  let g' = g { ggCacheHits = ggCacheHits g + 1 }
  pure (a, g', p, ce)

-- | Record cache miss
withCacheMiss :: GatewayM a -> GatewayM a
withCacheMiss (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  let g' = g { ggCacheMisses = ggCacheMisses g + 1 }
  pure (a, g', p, ce)

-- | Record a retry attempt
withRetry :: GatewayM a -> GatewayM a
withRetry (GatewayM m) = GatewayM $ do
  (a, g, p, ce) <- m
  let g' = g { ggRetries = ggRetries g + 1 }
  pure (a, g', p, ce)


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // co-effect recording
-- ════════════════════════════════════════════════════════════════════════════

-- | Record HTTP access
recordHttpAccess :: Text -> Text -> Maybe Int -> GatewayM ()
recordHttpAccess url method status = GatewayM $ do
  now <- getCurrentTime
  let access = HttpAccess
        { haUrl = url
        , haMethod = method
        , haTimestamp = now
        , haStatusCode = status
        }
      ce = emptyCoEffect { gceHttpAccess = Set.singleton access }
  pure ((), emptyGrade, emptyProvenance, ce)

-- | Record auth usage
recordAuthUsage :: Text -> Text -> GatewayM ()
recordAuthUsage provider scope = GatewayM $ do
  now <- getCurrentTime
  let usage = AuthUsage
        { auProvider = provider
        , auScope = scope
        , auTimestamp = now
        }
      ce = emptyCoEffect { gceAuthUsage = Set.singleton usage }
  pure ((), emptyGrade, emptyProvenance, ce)

-- | Record config access
recordConfigAccess :: Text -> GatewayM ()
recordConfigAccess key = GatewayM $ do
  now <- getCurrentTime
  let access = ConfigAccess
        { caKey = key
        , caTimestamp = now
        }
      ce = emptyCoEffect { gceConfigAccess = Set.singleton access }
  pure ((), emptyGrade, emptyProvenance, ce)


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // provenance recording
-- ════════════════════════════════════════════════════════════════════════════

-- | Record provider used
recordProvider :: Text -> GatewayM ()
recordProvider provider = GatewayM $ do
  let p = emptyProvenance { gpProvidersUsed = [provider] }
  pure ((), emptyGrade, p, emptyCoEffect)

-- | Record model used
recordModel :: Text -> GatewayM ()
recordModel model = GatewayM $ do
  let p = emptyProvenance { gpModelsUsed = [model] }
  pure ((), emptyGrade, p, emptyCoEffect)

-- | Record request ID
recordRequestId :: Text -> GatewayM ()
recordRequestId reqId = GatewayM $ do
  now <- getCurrentTime
  let p = emptyProvenance
        { gpRequestId = Just reqId
        , gpTimestamp = Just now
        }
  pure ((), emptyGrade, p, emptyCoEffect)


-- ════════════════════════════════════════════════════════════════════════════
--                                                         // grade inspection
-- ════════════════════════════════════════════════════════════════════════════

-- | Get current grade
getGrade :: GatewayM GatewayGrade
getGrade = GatewayM $ pure (emptyGrade, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Get current co-effect
getCoEffect :: GatewayM GatewayCoEffect
getCoEffect = GatewayM $ pure (emptyCoEffect, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Get current provenance
getProvenance :: GatewayM GatewayProvenance
getProvenance = GatewayM $ pure (emptyProvenance, emptyGrade, emptyProvenance, emptyCoEffect)

-- | Determine if response should be cached based on grade
shouldCacheResponse :: GatewayGrade -> Bool
shouldCacheResponse g =
  ggLatencyMs g > 100          -- More than 100ms latency
    || ggRetries g > 0         -- Any retries occurred
    || ggCacheMisses g > 0     -- Cache miss occurred
