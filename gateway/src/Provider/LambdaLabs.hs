-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // straylight-llm // provider/lambdalabs
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd seen the same pattern in the sky over Chiba, spelled out in
--      glowing Chiba City kanji."
--
--                                                              — Neuromancer
--
-- Lambda Labs GPU cloud provider. On-demand H100/A100 instances.
-- API: https://cloud.lambdalabs.com/api/v1
--
-- NOTE: Lambda Labs is primarily a GPU compute provider, not an LLM inference
-- service. This module provides pricing aggregation for their GPU instances.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.LambdaLabs
  ( -- * Provider
    makeLambdaLabsProvider,

    -- * Rate Types
    LambdaLabsInstance
      ( GPU_1xH100_SXM,
        GPU_8xH100_SXM,
        GPU_1xA100_SXM,
        GPU_8xA100_SXM,
        GPU_1xA100_PCIe,
        GPU_1xA10,
        GPU_4xA6000
      ),
    LambdaLabsRate
      ( LambdaLabsRate,
        llrInstance,
        llrPricePerHour,
        llrAvailable,
        llrRegion,
        llrGpuCount,
        llrVram,
        llrFetchedAt
      ),
    fetchInstanceRates,
  )
where

import Config (ProviderConfig (pcApiKey, pcEnabled))
import Control.Exception (try)
import Data.Aeson (FromJSON (..), ToJSON (..), eitherDecode, object, withObject, (.:), (.:?), (.=))
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Effects.Do qualified as G
import Effects.Graded (Full, GatewayM, liftIO', recordConfigAccess)
import Network.HTTP.Client (HttpException)
import Network.HTTP.Client qualified as HC
import Network.HTTP.Types qualified as HT
import Provider.Types
  ( Provider
      ( Provider,
        providerChat,
        providerChatStream,
        providerEmbeddings,
        providerEnabled,
        providerModels,
        providerName,
        providerSupportsModel
      ),
    ProviderError (InvalidRequestError),
    ProviderName (LambdaLabs),
    ProviderResult (Failure, Success),
  )
import Types (ModelList (ModelList))

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Lambda Labs GPU instance types
data LambdaLabsInstance
  = -- | 1x H100 SXM (80GB)
    GPU_1xH100_SXM
  | -- | 8x H100 SXM cluster
    GPU_8xH100_SXM
  | -- | 1x A100 SXM (80GB)
    GPU_1xA100_SXM
  | -- | 8x A100 SXM cluster
    GPU_8xA100_SXM
  | -- | 1x A100 PCIe (40GB)
    GPU_1xA100_PCIe
  | -- | 1x A10 (24GB)
    GPU_1xA10
  | -- | 4x RTX A6000 (48GB each)
    GPU_4xA6000
  deriving (Eq, Show, Ord, Enum, Bounded)

instance ToJSON LambdaLabsInstance where
  toJSON GPU_1xH100_SXM = "gpu_1x_h100_sxm"
  toJSON GPU_8xH100_SXM = "gpu_8x_h100_sxm"
  toJSON GPU_1xA100_SXM = "gpu_1x_a100_sxm"
  toJSON GPU_8xA100_SXM = "gpu_8x_a100_sxm"
  toJSON GPU_1xA100_PCIe = "gpu_1x_a100_pcie"
  toJSON GPU_1xA10 = "gpu_1x_a10"
  toJSON GPU_4xA6000 = "gpu_4x_a6000"

instance FromJSON LambdaLabsInstance where
  parseJSON = withObject "LambdaLabsInstance" $ \v -> do
    name :: Text <- v .: "instance_type"
    case name of
      "gpu_1x_h100_sxm" -> pure GPU_1xH100_SXM
      "gpu_8x_h100_sxm" -> pure GPU_8xH100_SXM
      "gpu_1x_a100_sxm" -> pure GPU_1xA100_SXM
      "gpu_8x_a100_sxm" -> pure GPU_8xA100_SXM
      "gpu_1x_a100_pcie" -> pure GPU_1xA100_PCIe
      "gpu_1x_a10" -> pure GPU_1xA10
      "gpu_4x_a6000" -> pure GPU_4xA6000
      _ -> fail $ "Unknown Lambda Labs instance type: " <> T.unpack name

-- | Lambda Labs pricing rate
data LambdaLabsRate = LambdaLabsRate
  { -- | Instance type
    llrInstance :: LambdaLabsInstance,
    -- | USD per hour
    llrPricePerHour :: Double,
    -- | Currently available
    llrAvailable :: Bool,
    -- | Region (us-west-1, etc.)
    llrRegion :: Text,
    -- | Number of GPUs
    llrGpuCount :: Int,
    -- | VRAM in GB
    llrVram :: Int,
    -- | When rate was fetched
    llrFetchedAt :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON LambdaLabsRate where
  toJSON LambdaLabsRate {..} =
    object
      [ "instance" .= llrInstance,
        "price_per_hour" .= llrPricePerHour,
        "available" .= llrAvailable,
        "region" .= llrRegion,
        "gpu_count" .= llrGpuCount,
        "vram_gb" .= llrVram,
        "fetched_at" .= llrFetchedAt
      ]

-- | API response for instance types
data InstanceTypesResponse = InstanceTypesResponse
  { itrData :: [InstanceTypeData]
  }

instance FromJSON InstanceTypesResponse where
  parseJSON = withObject "InstanceTypesResponse" $ \v ->
    InstanceTypesResponse <$> v .: "data"

data InstanceTypeData = InstanceTypeData
  { itdInstanceType :: Text,
    itdPricePerHour :: Double,
    itdSpecs :: InstanceSpecs
  }

instance FromJSON InstanceTypeData where
  parseJSON = withObject "InstanceTypeData" $ \v ->
    InstanceTypeData
      <$> v .: "instance_type"
      <*> (v .: "specs" >>= (.: "price_cents_per_hour") >>= \cents -> pure (cents / 100.0))
      <*> v .: "specs"

data InstanceSpecs = InstanceSpecs
  { isGpus :: Int,
    isVram :: Int
  }

instance FromJSON InstanceSpecs where
  parseJSON = withObject "InstanceSpecs" $ \v ->
    InstanceSpecs
      <$> v .: "gpus"
      <*> (v .:? "vram_gib" >>= \m -> pure $ maybe 80 id m)

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | Lambda Labs provider for rate aggregation
-- Note: This provider is primarily for GPU pricing, not LLM inference
makeLambdaLabsProvider :: IORef ProviderConfig -> Provider
makeLambdaLabsProvider configRef =
  Provider
    { providerName = LambdaLabs,
      providerEnabled = isEnabled configRef,
      providerChat = \_ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "Lambda Labs is a GPU compute provider, not an LLM service. Use for rate aggregation only.",
      providerChatStream = \_ _ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "Lambda Labs is a GPU compute provider, not an LLM service. Use for rate aggregation only.",
      providerEmbeddings = \_ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "Lambda Labs is a GPU compute provider, not an LLM service. Use for rate aggregation only.",
      providerModels = \_ -> liftIO' $ pure $ Success $ ModelList "list" [],
      providerSupportsModel = const False
    }

-- | Check if Lambda Labs is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "lambdalabs.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // rate fetching
-- ════════════════════════════════════════════════════════════════════════════

-- | Fetch current GPU instance rates from Lambda Labs
fetchInstanceRates :: HC.Manager -> Text -> IO (Either Text [LambdaLabsRate])
fetchInstanceRates manager apiKey = do
  now <- getCurrentTime
  result <- fetchInstanceTypes manager apiKey
  case result of
    Left err -> pure $ Left err
    Right response -> pure $ Right $ map (toRate now) (itrData response)
  where
    toRate :: UTCTime -> InstanceTypeData -> LambdaLabsRate
    toRate now itd =
      LambdaLabsRate
        { llrInstance = parseInstanceType (itdInstanceType itd),
          llrPricePerHour = itdPricePerHour itd,
          llrAvailable = True, -- Would need availability check
          llrRegion = "us-west-1", -- Default region
          llrGpuCount = isGpus (itdSpecs itd),
          llrVram = isVram (itdSpecs itd),
          llrFetchedAt = now
        }

    parseInstanceType :: Text -> LambdaLabsInstance
    parseInstanceType t = case t of
      "gpu_1x_h100_sxm" -> GPU_1xH100_SXM
      "gpu_8x_h100_sxm" -> GPU_8xH100_SXM
      "gpu_1x_a100_sxm" -> GPU_1xA100_SXM
      "gpu_8x_a100_sxm" -> GPU_8xA100_SXM
      "gpu_1x_a100_pcie" -> GPU_1xA100_PCIe
      "gpu_1x_a10" -> GPU_1xA10
      "gpu_4x_a6000" -> GPU_4xA6000
      _ -> GPU_1xA100_PCIe -- Default fallback

-- | Fetch instance types from Lambda Labs API
fetchInstanceTypes :: HC.Manager -> Text -> IO (Either Text InstanceTypesResponse)
fetchInstanceTypes manager apiKey = do
  initReq <- HC.parseRequest "https://cloud.lambdalabs.com/api/v1/instance-types"
  let req =
        initReq
          { HC.method = "GET",
            HC.requestHeaders =
              [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("Accept", "application/json")
              ]
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left $ T.pack $ show e
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then case eitherDecode (HC.responseBody resp) of
          Left parseErr -> pure $ Left $ "Parse error: " <> T.pack parseErr
          Right response -> pure $ Right response
        else pure $ Left $ "HTTP " <> T.pack (show status)
