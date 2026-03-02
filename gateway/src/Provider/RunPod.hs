-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // provider/runpod
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The Sprawl was a single conurban pulse, a vast, irregular heart of
--      neon and shadow."
--
--                                                              — Neuromancer
--
-- RunPod GPU cloud provider. Serverless GPU inference and pods.
-- API: https://api.runpod.io/graphql
--
-- RunPod offers both:
-- - Serverless endpoints (pay per second of compute)
-- - GPU Pods (hourly instances like Lambda Labs)
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.RunPod
  ( -- * Provider
    makeRunPodProvider,

    -- * Rate Types
    RunPodGPU
      ( RTX_4090,
        RTX_3090,
        RTX_A6000,
        A100_80GB_PCIe,
        A100_80GB_SXM,
        H100_80GB_PCIe,
        H100_80GB_SXM,
        L40S,
        A40
      ),
    RunPodRate
      ( RunPodRate,
        rprGPU,
        rprTier,
        rprPricePerHour,
        rprSpotPrice,
        rprAvailable,
        rprVram,
        rprFetchedAt
      ),
    RunPodTier (Community, Secure),
    fetchGPURates,

    -- * API Response Types (for direct API access)
    GPUTypeData
      ( GPUTypeData,
        gtdId,
        gtdDisplayName,
        gtdMemory,
        gtdSecure,
        gtdCommunity,
        gtdLowestPrice
      ),
    LowestPrice
      ( LowestPrice,
        lpMinBid,
        lpUninterruptible
      ),
  )
where

import Config (ProviderConfig (pcApiKey, pcEnabled))
import Control.Exception (try)
import Data.Aeson (FromJSON (..), ToJSON (..), eitherDecode, encode, object, withObject, (.:), (.:?), (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Effects.Graded (GatewayM, liftGatewayIO, recordConfigAccess)
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
    ProviderName (RunPod),
    ProviderResult (Failure, Success),
  )
import Types (ModelList (ModelList))

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | RunPod GPU types
data RunPodGPU
  = -- | RTX 4090 (24GB)
    RTX_4090
  | -- | RTX 3090 (24GB)
    RTX_3090
  | -- | RTX A6000 (48GB)
    RTX_A6000
  | -- | A100 PCIe (80GB)
    A100_80GB_PCIe
  | -- | A100 SXM (80GB)
    A100_80GB_SXM
  | -- | H100 PCIe (80GB)
    H100_80GB_PCIe
  | -- | H100 SXM (80GB)
    H100_80GB_SXM
  | -- | L40S (48GB)
    L40S
  | -- | A40 (48GB)
    A40
  deriving (Eq, Show, Ord, Enum, Bounded)

instance ToJSON RunPodGPU where
  toJSON RTX_4090 = "NVIDIA GeForce RTX 4090"
  toJSON RTX_3090 = "NVIDIA GeForce RTX 3090"
  toJSON RTX_A6000 = "NVIDIA RTX A6000"
  toJSON A100_80GB_PCIe = "NVIDIA A100 80GB PCIe"
  toJSON A100_80GB_SXM = "NVIDIA A100-SXM4-80GB"
  toJSON H100_80GB_PCIe = "NVIDIA H100 PCIe"
  toJSON H100_80GB_SXM = "NVIDIA H100 80GB HBM3"
  toJSON L40S = "NVIDIA L40S"
  toJSON A40 = "NVIDIA A40"

instance FromJSON RunPodGPU where
  parseJSON = withObject "RunPodGPU" $ \v -> do
    name :: Text <- v .: "id"
    pure $ parseGPUName name

-- | Parse GPU name from RunPod API
parseGPUName :: Text -> RunPodGPU
parseGPUName name
  | "4090" `T.isInfixOf` name = RTX_4090
  | "3090" `T.isInfixOf` name = RTX_3090
  | "A6000" `T.isInfixOf` name = RTX_A6000
  | "A100" `T.isInfixOf` name && "SXM" `T.isInfixOf` name = A100_80GB_SXM
  | "A100" `T.isInfixOf` name = A100_80GB_PCIe
  | "H100" `T.isInfixOf` name && "SXM" `T.isInfixOf` name = H100_80GB_SXM
  | "H100" `T.isInfixOf` name = H100_80GB_PCIe
  | "L40S" `T.isInfixOf` name = L40S
  | "A40" `T.isInfixOf` name = A40
  | otherwise = RTX_4090 -- Default fallback

-- | RunPod pricing tier
data RunPodTier
  = -- | Community cloud (cheaper, less reliable)
    Community
  | -- | Secure cloud (dedicated, more expensive)
    Secure
  deriving (Eq, Show, Ord)

instance ToJSON RunPodTier where
  toJSON Community = "COMMUNITY"
  toJSON Secure = "SECURE"

-- | RunPod pricing rate
data RunPodRate = RunPodRate
  { -- | GPU type
    rprGPU :: RunPodGPU,
    -- | Community or Secure
    rprTier :: RunPodTier,
    -- | USD per hour (on-demand)
    rprPricePerHour :: Double,
    -- | USD per hour (spot/interruptible)
    rprSpotPrice :: Maybe Double,
    -- | Number available
    rprAvailable :: Int,
    -- | VRAM in GB
    rprVram :: Int,
    -- | When rate was fetched
    rprFetchedAt :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON RunPodRate where
  toJSON RunPodRate {..} =
    object
      [ "gpu" .= rprGPU,
        "tier" .= rprTier,
        "price_per_hour" .= rprPricePerHour,
        "spot_price" .= rprSpotPrice,
        "available" .= rprAvailable,
        "vram_gb" .= rprVram,
        "fetched_at" .= rprFetchedAt
      ]

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | RunPod provider for rate aggregation
makeRunPodProvider :: IORef ProviderConfig -> Provider
makeRunPodProvider configRef =
  Provider
    { providerName = RunPod,
      providerEnabled = isEnabled configRef,
      providerChat = \_ _ ->
        pure $
          Failure $
            InvalidRequestError
              "RunPod rate provider - use serverless endpoints directly for inference",
      providerChatStream = \_ _ _ ->
        pure $
          Failure $
            InvalidRequestError
              "RunPod rate provider - use serverless endpoints directly for inference",
      providerEmbeddings = \_ _ ->
        pure $
          Failure $
            InvalidRequestError
              "RunPod rate provider - use serverless endpoints directly for inference",
      providerModels = \_ -> pure $ Success $ ModelList "list" [],
      providerSupportsModel = const False
    }

-- | Check if RunPod is configured
isEnabled :: IORef ProviderConfig -> GatewayM Bool
isEnabled configRef = do
  recordConfigAccess "runpod.enabled"
  config <- liftGatewayIO $ readIORef configRef
  pure $ pcEnabled config && pcApiKey config /= Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // rate fetching
-- ════════════════════════════════════════════════════════════════════════════

-- | GraphQL query for GPU types
gpuTypesQuery :: LBS.ByteString
gpuTypesQuery =
  encode $
    object
      [ "query" .= ("query { gpuTypes { id displayName memoryInGb secureCloud communityCloud lowestPrice { minimumBidPrice uninterruptiblePrice } } }" :: Text)
      ]

-- | Fetch current GPU rates from RunPod
fetchGPURates :: HC.Manager -> Text -> IO (Either Text [RunPodRate])
fetchGPURates manager apiKey = do
  now <- getCurrentTime
  initReq <- HC.parseRequest "https://api.runpod.io/graphql"
  let req =
        initReq
          { HC.method = "POST",
            HC.requestHeaders =
              [ ("Authorization", "Bearer " <> encodeUtf8 apiKey),
                ("Content-Type", "application/json")
              ],
            HC.requestBody = HC.RequestBodyLBS gpuTypesQuery
          }

  result <- try @HttpException $ HC.httpLbs req manager
  case result of
    Left e -> pure $ Left $ T.pack $ show e
    Right resp -> do
      let status = HT.statusCode $ HC.responseStatus resp
      if status >= 200 && status < 300
        then case eitherDecode (HC.responseBody resp) of
          Left parseErr -> pure $ Left $ "Parse error: " <> T.pack parseErr
          Right (GPUTypesResponse gpus) -> pure $ Right $ concatMap (toRates now) gpus
        else pure $ Left $ "HTTP " <> T.pack (show status)

-- | Convert API response to rates
toRates :: UTCTime -> GPUTypeData -> [RunPodRate]
toRates now gpu =
  let base =
        RunPodRate
          { rprGPU = parseGPUName (gtdId gpu),
            rprTier = Community,
            rprPricePerHour = 0,
            rprSpotPrice = Nothing,
            rprAvailable = 0,
            rprVram = gtdMemory gpu,
            rprFetchedAt = now
          }
      communityRate =
        if gtdCommunity gpu
          then [base {rprTier = Community, rprPricePerHour = maybe 0 lpUninterruptible (gtdLowestPrice gpu), rprSpotPrice = fmap lpMinBid (gtdLowestPrice gpu)}]
          else []
      secureRate =
        if gtdSecure gpu
          then [base {rprTier = Secure, rprPricePerHour = maybe 0 lpUninterruptible (gtdLowestPrice gpu) * 1.2}] -- Secure is typically ~20% more
          else []
   in communityRate <> secureRate

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // api response types
-- ════════════════════════════════════════════════════════════════════════════

newtype GPUTypesResponse = GPUTypesResponse [GPUTypeData]

instance FromJSON GPUTypesResponse where
  parseJSON = withObject "GPUTypesResponse" $ \v -> do
    dataObj <- v .: "data"
    gpuTypes <- dataObj .: "gpuTypes"
    pure $ GPUTypesResponse gpuTypes

data GPUTypeData = GPUTypeData
  { gtdId :: Text,
    gtdDisplayName :: Text,
    gtdMemory :: Int,
    gtdSecure :: Bool,
    gtdCommunity :: Bool,
    gtdLowestPrice :: Maybe LowestPrice
  }

instance FromJSON GPUTypeData where
  parseJSON = withObject "GPUTypeData" $ \v ->
    GPUTypeData
      <$> v .: "id"
      <*> v .: "displayName"
      <*> v .: "memoryInGb"
      <*> v .: "secureCloud"
      <*> v .: "communityCloud"
      <*> v .:? "lowestPrice"

data LowestPrice = LowestPrice
  { lpMinBid :: Double,
    lpUninterruptible :: Double
  }

instance FromJSON LowestPrice where
  parseJSON = withObject "LowestPrice" $ \v ->
    LowestPrice
      <$> v .: "minimumBidPrice"
      <*> v .: "uninterruptiblePrice"
