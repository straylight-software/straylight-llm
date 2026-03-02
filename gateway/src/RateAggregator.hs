-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // straylight-llm // rate-aggregator
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- GPU Rate Aggregator — Multi-source pricing for compute resources.
--
-- Sources: Lambda Labs, RunPod, vast.ai, OpenRouter, Venice
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}

module RateAggregator
  ( -- * Types
    GPURate (..),
    RateSource (..),
  )
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Data.Time.Clock (UTCTime)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Source of GPU rate information
data RateSource
  = SourceLambdaLabs
  | SourceRunPod
  | SourceVastAI
  | SourceOpenRouter
  | SourceVenice
  deriving (Eq, Show, Ord)

-- | Normalized GPU rate across all sources
data GPURate = GPURate
  { -- | Where this rate came from
    grSource :: RateSource,
    -- | Normalized GPU type (H100, A100, etc.)
    grGPUType :: Text,
    -- | USD per hour
    grPricePerHour :: Double,
    -- | Currently available
    grAvailable :: Bool,
    -- | VRAM in GB
    grVramGB :: Int,
    -- | When this rate was fetched
    grFetchedAt :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON RateSource where
  toJSON SourceLambdaLabs = "lambdalabs"
  toJSON SourceRunPod = "runpod"
  toJSON SourceVastAI = "vastai"
  toJSON SourceOpenRouter = "openrouter"
  toJSON SourceVenice = "venice"

instance ToJSON GPURate where
  toJSON GPURate {..} =
    object
      [ "source" .= grSource,
        "gpu_type" .= grGPUType,
        "price_per_hour" .= grPricePerHour,
        "available" .= grAvailable,
        "vram_gb" .= grVramGB,
        "fetched_at" .= grFetchedAt
      ]
