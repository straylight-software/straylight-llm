-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // provider/vastai
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "Somewhere, very close by, the Finn would be waiting."
--
--                                                              — Neuromancer
--
-- vast.ai GPU marketplace provider. Peer-to-peer GPU rental.
-- API: https://cloud.vast.ai/api/v0
--
-- vast.ai is a marketplace where individuals rent out their GPUs.
-- Prices are highly variable and competitive.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RecordWildCards #-}

module Provider.VastAI
  ( -- * Provider
    makeVastAIProvider,

    -- * Rate Types
    VastAIOffer
      ( VastAIOffer,
        vaoId,
        vaoGPU,
        vaoGPUName,
        vaoNumGPUs,
        vaoPricePerHour,
        vaoMinBid,
        vaoVram,
        vaoCudaCores,
        vaoReliability,
        vaoVerified,
        vaoLocation,
        vaoInternetSpeed,
        vaoFetchedAt
      ),
    VastAIGPU
      ( VAST_RTX_4090,
        VAST_RTX_3090,
        VAST_RTX_3080,
        VAST_A100_80GB,
        VAST_A100_40GB,
        VAST_H100,
        VAST_A6000,
        VAST_A40,
        VAST_L40,
        VAST_Other
      ),
    fetchOffers,
    searchOffers,
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
    ProviderName (VastAI),
    ProviderResult (Failure, Success),
  )
import Types (ModelList (ModelList))

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | vast.ai GPU types (normalized)
data VastAIGPU
  = VAST_RTX_4090
  | VAST_RTX_3090
  | VAST_RTX_3080
  | VAST_A100_80GB
  | VAST_A100_40GB
  | VAST_H100
  | VAST_A6000
  | VAST_A40
  | VAST_L40
  | VAST_Other Text
  deriving (Eq, Show, Ord)

instance ToJSON VastAIGPU where
  toJSON VAST_RTX_4090 = "RTX_4090"
  toJSON VAST_RTX_3090 = "RTX_3090"
  toJSON VAST_RTX_3080 = "RTX_3080"
  toJSON VAST_A100_80GB = "A100_PCIE_80GB"
  toJSON VAST_A100_40GB = "A100_PCIE_40GB"
  toJSON VAST_H100 = "H100_PCIE"
  toJSON VAST_A6000 = "RTX_A6000"
  toJSON VAST_A40 = "A40"
  toJSON VAST_L40 = "L40"
  toJSON (VAST_Other t) = toJSON t

-- | Parse GPU name from vast.ai
parseVastGPU :: Text -> VastAIGPU
parseVastGPU name
  | "4090" `T.isInfixOf` name = VAST_RTX_4090
  | "3090" `T.isInfixOf` name = VAST_RTX_3090
  | "3080" `T.isInfixOf` name = VAST_RTX_3080
  | "A100" `T.isInfixOf` name && "80" `T.isInfixOf` name = VAST_A100_80GB
  | "A100" `T.isInfixOf` name = VAST_A100_40GB
  | "H100" `T.isInfixOf` name = VAST_H100
  | "A6000" `T.isInfixOf` name = VAST_A6000
  | "A40" `T.isInfixOf` name = VAST_A40
  | "L40" `T.isInfixOf` name = VAST_L40
  | otherwise = VAST_Other name

-- | vast.ai marketplace offer
data VastAIOffer = VastAIOffer
  { -- | Offer ID
    vaoId :: Int,
    -- | GPU type
    vaoGPU :: VastAIGPU,
    -- | Raw GPU name
    vaoGPUName :: Text,
    -- | Number of GPUs
    vaoNumGPUs :: Int,
    -- | USD per hour (DLPerf pricing)
    vaoPricePerHour :: Double,
    -- | Minimum bid price
    vaoMinBid :: Double,
    -- | VRAM per GPU in MB
    vaoVram :: Int,
    -- | CUDA cores
    vaoCudaCores :: Int,
    -- | Host reliability score (0-1)
    vaoReliability :: Double,
    -- | Verified host
    vaoVerified :: Bool,
    -- | Geographic location
    vaoLocation :: Text,
    -- | Download speed in Mbps
    vaoInternetSpeed :: Double,
    -- | When offer was fetched
    vaoFetchedAt :: UTCTime
  }
  deriving (Eq, Show)

instance ToJSON VastAIOffer where
  toJSON VastAIOffer {..} =
    object
      [ "id" .= vaoId,
        "gpu" .= vaoGPU,
        "gpu_name" .= vaoGPUName,
        "num_gpus" .= vaoNumGPUs,
        "price_per_hour" .= vaoPricePerHour,
        "min_bid" .= vaoMinBid,
        "vram_mb" .= vaoVram,
        "cuda_cores" .= vaoCudaCores,
        "reliability" .= vaoReliability,
        "verified" .= vaoVerified,
        "location" .= vaoLocation,
        "internet_speed_mbps" .= vaoInternetSpeed,
        "fetched_at" .= vaoFetchedAt
      ]

instance FromJSON VastAIOffer where
  parseJSON = withObject "VastAIOffer" $ \v -> do
    vaoId <- v .: "id"
    vaoGPUName <- v .: "gpu_name"
    let vaoGPU = parseVastGPU vaoGPUName
    vaoNumGPUs <- v .: "num_gpus"
    vaoPricePerHour <- v .: "dph_total"
    vaoMinBid <- v .:? "min_bid" >>= \m -> pure $ maybe vaoPricePerHour id m
    vaoVram <- v .: "gpu_ram"
    vaoCudaCores <- v .:? "cuda_max_good" >>= \m -> pure $ maybe 0 id m
    vaoReliability <- v .:? "reliability2" >>= \m -> pure $ maybe 0.95 id m
    vaoVerified <- v .:? "verified" >>= \m -> pure $ maybe False id m
    vaoLocation <- v .:? "geolocation" >>= \m -> pure $ maybe "Unknown" id m
    vaoInternetSpeed <- v .:? "inet_down" >>= \m -> pure $ maybe 0 id m
    -- vaoFetchedAt will be set by caller
    pure VastAIOffer {vaoFetchedAt = error "Must set fetched_at", ..}

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // provider
-- ════════════════════════════════════════════════════════════════════════════

-- | vast.ai provider for rate aggregation
makeVastAIProvider :: IORef ProviderConfig -> Provider
makeVastAIProvider configRef =
  Provider
    { providerName = VastAI,
      providerEnabled = isEnabled configRef,
      providerChat = \_ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "vast.ai is a GPU marketplace, not an LLM service. Use for rate aggregation only.",
      providerChatStream = \_ _ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "vast.ai is a GPU marketplace, not an LLM service. Use for rate aggregation only.",
      providerEmbeddings = \_ _ ->
        liftIO' $
          pure $
            Failure $
              InvalidRequestError
                "vast.ai is a GPU marketplace, not an LLM service. Use for rate aggregation only.",
      providerModels = \_ -> liftIO' $ pure $ Success $ ModelList "list" [],
      providerSupportsModel = const False
    }

-- | Check if vast.ai is configured
isEnabled :: IORef ProviderConfig -> GatewayM Full Bool
isEnabled configRef = G.do
  recordConfigAccess "vastai.enabled"
  config <- liftIO' $ readIORef configRef
  liftIO' $ pure $ pcEnabled config && pcApiKey config /= Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // rate fetching
-- ════════════════════════════════════════════════════════════════════════════

-- | Search parameters for vast.ai offers
data SearchParams = SearchParams
  { -- | Minimum number of GPUs
    spMinGPUs :: Int,
    -- | Maximum number of GPUs
    spMaxGPUs :: Int,
    -- | Minimum VRAM in GB
    spMinVRAM :: Int,
    -- | Specific GPU name filter
    spGPUName :: Maybe Text,
    -- | Only verified hosts
    spVerifiedOnly :: Bool,
    -- | Sort order (dph_total, reliability, etc.)
    spOrderBy :: Text
  }

defaultSearchParams :: SearchParams
defaultSearchParams =
  SearchParams
    { spMinGPUs = 1,
      spMaxGPUs = 8,
      spMinVRAM = 24,
      spGPUName = Nothing,
      spVerifiedOnly = False,
      spOrderBy = "dph_total"
    }

-- | Fetch all available offers from vast.ai
fetchOffers :: HC.Manager -> Text -> IO (Either Text [VastAIOffer])
fetchOffers manager apiKey = searchOffers manager apiKey defaultSearchParams

-- | Search for offers with specific parameters
searchOffers :: HC.Manager -> Text -> SearchParams -> IO (Either Text [VastAIOffer])
searchOffers manager apiKey params = do
  now <- getCurrentTime
  let url = "https://console.vast.ai/api/v0/bundles?" <> buildQuery params
  initReq <- HC.parseRequest (T.unpack url)
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
          Right (OffersResponse offers) -> pure $ Right $ map (setTimestamp now) offers
        else pure $ Left $ "HTTP " <> T.pack (show status)

-- | Set the fetched timestamp on an offer
setTimestamp :: UTCTime -> VastAIOffer -> VastAIOffer
setTimestamp t offer = offer {vaoFetchedAt = t}

-- | Build query string from search params
buildQuery :: SearchParams -> Text
buildQuery SearchParams {..} =
  T.intercalate
    "&"
    [ "num_gpus_min=" <> T.pack (show spMinGPUs),
      "num_gpus_max=" <> T.pack (show spMaxGPUs),
      "gpu_ram_min=" <> T.pack (show (spMinVRAM * 1024)), -- API expects MB
      "order=" <> spOrderBy,
      "type=on-demand",
      "rentable=true"
    ]
    <> maybe "" (\g -> "&gpu_name=" <> g) spGPUName
    <> if spVerifiedOnly then "&verified=true" else ""

-- ════════════════════════════════════════════════════════════════════════════
--                                                          // api response types
-- ════════════════════════════════════════════════════════════════════════════

newtype OffersResponse = OffersResponse [VastAIOffer]

instance FromJSON OffersResponse where
  parseJSON = withObject "OffersResponse" $ \v -> do
    offers <- v .: "offers"
    pure $ OffersResponse offers
