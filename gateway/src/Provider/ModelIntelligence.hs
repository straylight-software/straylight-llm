-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // straylight-llm // provider/model-intelligence
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "When the strategy changes, the coordinates shift."
--
--                                                              — Neuromancer
--
-- Model Intelligence System - tracks model specs, detects new releases,
-- monitors API changes across providers.
--
-- Features:
--   - Rich model specs: context window, pricing, capabilities, modalities
--   - New model detection with SSE events
--   - Historical tracking of model releases
--   - Provider API format tracking
--   - Queryable model database
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

module Provider.ModelIntelligence
  ( -- * Intelligence System
    ModelIntelligence,
    makeModelIntelligence,
    closeModelIntelligence,

    -- * Model Specs
    ModelSpec (..),
    ModelCapabilities (..),
    ModelPricing (..),
    ModelModality (..),
    APIFormat (..),

    -- * New Model Events
    NewModelEvent (..),

    -- * Queries
    getModelSpec,
    getAllSpecs,
    getProviderSpecs,
    getNewModels,
    getModelHistory,
    searchModels,

    -- * Sync
    syncIntelligence,

    -- * Events
    emitNewModelDetected,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.STM
import Control.Monad (forM, forM_, forever, when)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Effects.Graded (runGatewayM)
import GHC.Generics (Generic)
import Network.HTTP.Client (Manager)
import Provider.Types
  ( Provider (providerEnabled, providerModels, providerName),
    ProviderName (..),
    ProviderResult (Success),
    RequestContext (RequestContext, rcClientIp, rcManager, rcRequestId),
  )
import Streaming.Events (EventBroadcaster)
import Streaming.Events qualified as Events
import System.IO (hPutStrLn, stderr)
import System.Timeout (timeout)
import Types
  ( Model (modelOwnedBy),
    ModelId (unModelId),
    ModelList (mlData),
  )
import Types qualified

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | What modalities the model supports
data ModelModality
  = TextOnly -- Text in, text out
  | TextAndCode -- Text + code generation
  | Vision -- Can process images
  | Audio -- Can process audio
  | Multimodal -- Multiple modalities
  deriving (Eq, Show, Generic)

instance ToJSON ModelModality

instance FromJSON ModelModality

-- | API format/style the model uses
data APIFormat
  = OpenAICompat -- OpenAI-compatible API
  | AnthropicMessages -- Anthropic Messages API
  | GoogleVertex -- Google Vertex AI format
  | Custom Text -- Custom format with description
  deriving (Eq, Show, Generic)

instance ToJSON APIFormat

instance FromJSON APIFormat

-- | Model capabilities
data ModelCapabilities = ModelCapabilities
  { capToolUse :: Bool, -- Function/tool calling
    capStreaming :: Bool, -- Streaming responses
    capSystemPrompt :: Bool, -- System prompt support
    capJsonMode :: Bool, -- Structured JSON output
    capVision :: Bool, -- Image input
    capCodeExecution :: Bool, -- Code interpreter
    capWebSearch :: Bool, -- Web search capability
    capFileUpload :: Bool, -- File/document upload
    capFineTuning :: Bool, -- Fine-tuning available
    capBatching :: Bool -- Batch API available
  }
  deriving (Eq, Show, Generic)

instance ToJSON ModelCapabilities

instance FromJSON ModelCapabilities

defaultCapabilities :: ModelCapabilities
defaultCapabilities =
  ModelCapabilities
    { capToolUse = False,
      capStreaming = True,
      capSystemPrompt = True,
      capJsonMode = False,
      capVision = False,
      capCodeExecution = False,
      capWebSearch = False,
      capFileUpload = False,
      capFineTuning = False,
      capBatching = False
    }

-- | Model pricing (per million tokens, USD)
data ModelPricing = ModelPricing
  { priceInput :: Maybe Double, -- Input/prompt tokens
    priceOutput :: Maybe Double, -- Output/completion tokens
    priceCachedInput :: Maybe Double, -- Cached input (if supported)
    priceBatch :: Maybe Double, -- Batch API pricing
    priceFree :: Bool -- Free tier available
  }
  deriving (Eq, Show, Generic)

instance ToJSON ModelPricing

instance FromJSON ModelPricing

unknownPricing :: ModelPricing
unknownPricing = ModelPricing Nothing Nothing Nothing Nothing False

-- | Complete model specification
data ModelSpec = ModelSpec
  { specId :: Text, -- Model ID
    specProvider :: ProviderName, -- Provider
    specDisplayName :: Maybe Text, -- Human-friendly name
    specDescription :: Maybe Text, -- Model description
    specContextWindow :: Maybe Int, -- Max context length (tokens)
    specMaxOutput :: Maybe Int, -- Max output tokens
    specModality :: ModelModality, -- Input/output modalities
    specCapabilities :: ModelCapabilities,
    specPricing :: ModelPricing,
    specAPIFormat :: APIFormat, -- API format/style
    specFamily :: Maybe Text, -- Model family (llama, claude, gpt)
    specVersion :: Maybe Text, -- Version string
    specReleaseDate :: Maybe UTCTime, -- When model was released
    specDeprecated :: Bool, -- Is model deprecated
    specFirstSeen :: UTCTime, -- When we first saw this model
    specLastSeen :: UTCTime, -- Last time model was available
    specOwnedBy :: Maybe Text -- Model owner/creator
  }
  deriving (Eq, Show, Generic)

instance ToJSON ModelSpec

instance FromJSON ModelSpec

-- | New model event
data NewModelEvent = NewModelEvent
  { nmeModelId :: Text,
    nmeProvider :: ProviderName,
    nmeSpec :: ModelSpec,
    nmeDetectedAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

instance ToJSON NewModelEvent

instance FromJSON NewModelEvent

-- | Model intelligence state
data ModelIntelligence = ModelIntelligence
  { miSpecs :: TVar (Map (ProviderName, Text) ModelSpec), -- All known specs
    miHistory :: TVar [NewModelEvent], -- New model history
    miManager :: Manager,
    miProviders :: [Provider],
    miBroadcaster :: EventBroadcaster,
    miSyncThread :: Maybe ThreadId,
    miSyncInterval :: Int -- Seconds between syncs
  }

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create model intelligence system
makeModelIntelligence :: Manager -> [Provider] -> EventBroadcaster -> Int -> IO ModelIntelligence
makeModelIntelligence manager providers broadcaster syncIntervalSec = do
  specsVar <- newTVarIO Map.empty
  historyVar <- newTVarIO []

  let intel =
        ModelIntelligence
          { miSpecs = specsVar,
            miHistory = historyVar,
            miManager = manager,
            miProviders = providers,
            miBroadcaster = broadcaster,
            miSyncThread = Nothing,
            miSyncInterval = syncIntervalSec
          }

  -- Initial sync (async)
  _ <- forkIO $ do
    _ <- timeout (30 * 1000000) (syncIntelligence intel)
    pure ()

  -- Start background sync
  if syncIntervalSec > 0
    then do
      tid <- forkIO $ syncLoop intel
      pure intel {miSyncThread = Just tid}
    else pure intel

-- | Stop intelligence system
closeModelIntelligence :: ModelIntelligence -> IO ()
closeModelIntelligence intel =
  case miSyncThread intel of
    Just tid -> killThread tid
    Nothing -> pure ()

-- | Background sync loop
syncLoop :: ModelIntelligence -> IO ()
syncLoop intel = forever $ do
  threadDelay (miSyncInterval intel * 1000000)
  syncIntelligence intel

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // sync
-- ════════════════════════════════════════════════════════════════════════════

-- | Sync all providers and detect new models
syncIntelligence :: ModelIntelligence -> IO ()
syncIntelligence intel = do
  hPutStrLn stderr "[ModelIntelligence] Starting sync..."
  now <- getCurrentTime

  forM_ (miProviders intel) $ \provider -> do
    let name = providerName provider
        ctx =
          RequestContext
            { rcManager = miManager intel,
              rcRequestId = "model-intel-sync",
              rcClientIp = Nothing
            }

    -- Check if provider enabled
    (enabledResult, _, _, _) <- runGatewayM (providerEnabled provider)
    when enabledResult $ do
      -- Fetch models with timeout
      mResult <- timeout (10 * 1000000) $ do
        (modelsResult, _, _, _) <- runGatewayM (providerModels provider ctx)
        pure modelsResult

      case mResult of
        Just (Success modelList) -> do
          -- Get current known models for this provider
          currentSpecs <- readTVarIO (miSpecs intel)
          let currentIds =
                Set.fromList
                  [mid | ((prov, mid), _) <- Map.toList currentSpecs, prov == name]

          -- Process each model
          newModels <- forM (mlData modelList) $ \model -> do
            let mid = unModelId (Types.modelId model)
                key = (name, mid)

            -- Check if this is a new model
            let isNew = not (Set.member mid currentIds)

            -- Create or update spec
            existingSpec <- atomically $ do
              specs <- readTVar (miSpecs intel)
              pure $ Map.lookup key specs

            let spec = case existingSpec of
                  Just existing -> existing {specLastSeen = now}
                  Nothing -> makeDefaultSpec name model now

            -- Update spec in store
            atomically $ modifyTVar' (miSpecs intel) $ Map.insert key spec

            -- Return if new
            pure $ if isNew then Just (mid, spec) else Nothing

          -- Emit events for new models
          let newOnes = catMaybes newModels
          forM_ newOnes $ \(modelId, spec) -> do
            hPutStrLn stderr $ "[ModelIntelligence] NEW MODEL: " ++ T.unpack modelId ++ " from " ++ show name
            let event =
                  NewModelEvent
                    { nmeModelId = modelId,
                      nmeProvider = name,
                      nmeSpec = spec,
                      nmeDetectedAt = now
                    }
            -- Add to history
            atomically $ modifyTVar' (miHistory intel) (event :)
            -- Emit SSE event
            emitNewModelDetected (miBroadcaster intel) event
        _ -> pure () -- Timeout or error, skip
  hPutStrLn stderr "[ModelIntelligence] Sync complete"

-- | Create default spec from model info
makeDefaultSpec :: ProviderName -> Model -> UTCTime -> ModelSpec
makeDefaultSpec provider model now =
  let mid = unModelId (Types.modelId model)
   in ModelSpec
        { specId = mid,
          specProvider = provider,
          specDisplayName = Nothing,
          specDescription = Nothing,
          specContextWindow = inferContextWindow provider mid,
          specMaxOutput = inferMaxOutput provider mid,
          specModality = inferModality mid,
          specCapabilities = inferCapabilities provider mid,
          specPricing = unknownPricing,
          specAPIFormat = inferAPIFormat provider,
          specFamily = inferFamily mid,
          specVersion = Nothing,
          specReleaseDate = Just now, -- Use current time as release date
          specDeprecated = False,
          specFirstSeen = now,
          specLastSeen = now,
          specOwnedBy = Just (modelOwnedBy model)
        }

-- ════════════════════════════════════════════════════════════════════════════
--                                                              // inference
-- ════════════════════════════════════════════════════════════════════════════

-- | Infer context window from model name
inferContextWindow :: ProviderName -> Text -> Maybe Int
inferContextWindow _ modelId
  | "200k" `T.isInfixOf` modelId = Just 200000
  | "128k" `T.isInfixOf` modelId = Just 128000
  | "100k" `T.isInfixOf` modelId = Just 100000
  | "64k" `T.isInfixOf` modelId = Just 64000
  | "32k" `T.isInfixOf` modelId = Just 32768
  | "16k" `T.isInfixOf` modelId = Just 16384
  | "8k" `T.isInfixOf` modelId = Just 8192
  | "4k" `T.isInfixOf` modelId = Just 4096
  -- Model family defaults
  | "claude-3" `T.isPrefixOf` modelId = Just 200000
  | "claude-2" `T.isPrefixOf` modelId = Just 100000
  | "gpt-4-turbo" `T.isPrefixOf` modelId = Just 128000
  | "gpt-4o" `T.isPrefixOf` modelId = Just 128000
  | "gpt-4" `T.isPrefixOf` modelId = Just 8192
  | "gpt-3.5-turbo" `T.isPrefixOf` modelId = Just 16385
  | "llama-3.3" `T.isPrefixOf` modelId = Just 128000
  | "llama-3.2" `T.isPrefixOf` modelId = Just 128000
  | "llama-3.1" `T.isPrefixOf` modelId = Just 128000
  | "llama-3" `T.isPrefixOf` modelId = Just 8192
  | "llama-2" `T.isPrefixOf` modelId = Just 4096
  | "mistral" `T.isPrefixOf` modelId = Just 32768
  | "mixtral" `T.isPrefixOf` modelId = Just 32768
  | "deepseek" `T.isPrefixOf` modelId = Just 64000
  | "qwen" `T.isPrefixOf` modelId = Just 32768
  | "gemini" `T.isPrefixOf` modelId = Just 1000000
  | otherwise = Nothing

-- | Infer max output tokens
inferMaxOutput :: ProviderName -> Text -> Maybe Int
inferMaxOutput _ modelId
  | "claude-3" `T.isPrefixOf` modelId = Just 8192
  | "gpt-4" `T.isPrefixOf` modelId = Just 16384
  | "llama" `T.isPrefixOf` modelId = Just 4096
  | otherwise = Just 4096

-- | Infer modality from model name
inferModality :: Text -> ModelModality
inferModality modelId
  | any (`T.isInfixOf` modelId) ["vision", "4o", "gpt-4-turbo", "claude-3"] = Vision
  | any (`T.isInfixOf` modelId) ["code", "codellama", "starcoder", "deepseek-coder"] = TextAndCode
  | otherwise = TextOnly

-- | Infer capabilities from provider and model
inferCapabilities :: ProviderName -> Text -> ModelCapabilities
inferCapabilities provider modelId =
  defaultCapabilities
    { capToolUse = toolUse,
      capStreaming = True,
      capSystemPrompt = True,
      capJsonMode = jsonMode,
      capVision = vision
    }
  where
    toolUse =
      any
        (`T.isInfixOf` modelId)
        ["gpt-4", "gpt-3.5-turbo", "claude-3", "claude-2.1", "llama-3"]
        || provider == Anthropic
    jsonMode = any (`T.isInfixOf` modelId) ["gpt-4", "gpt-3.5-turbo"]
    vision = any (`T.isInfixOf` modelId) ["vision", "4o", "gpt-4-turbo", "claude-3"]

-- | Infer API format from provider
inferAPIFormat :: ProviderName -> APIFormat
inferAPIFormat Anthropic = AnthropicMessages
inferAPIFormat Vertex = GoogleVertex
inferAPIFormat _ = OpenAICompat

-- | Infer model family from name
inferFamily :: Text -> Maybe Text
inferFamily modelId
  | "claude" `T.isPrefixOf` modelId = Just "claude"
  | "gpt-4" `T.isPrefixOf` modelId = Just "gpt-4"
  | "gpt-3" `T.isPrefixOf` modelId = Just "gpt-3.5"
  | "llama" `T.isPrefixOf` modelId = Just "llama"
  | "mistral" `T.isPrefixOf` modelId = Just "mistral"
  | "mixtral" `T.isPrefixOf` modelId = Just "mixtral"
  | "deepseek" `T.isPrefixOf` modelId = Just "deepseek"
  | "qwen" `T.isPrefixOf` modelId = Just "qwen"
  | "gemini" `T.isPrefixOf` modelId = Just "gemini"
  | "phi" `T.isPrefixOf` modelId = Just "phi"
  | otherwise = Nothing

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // queries
-- ════════════════════════════════════════════════════════════════════════════

-- | Get spec for a specific model
getModelSpec :: ModelIntelligence -> ProviderName -> Text -> IO (Maybe ModelSpec)
getModelSpec intel provider modelId = do
  specs <- readTVarIO (miSpecs intel)
  pure $ Map.lookup (provider, modelId) specs

-- | Get all known specs
getAllSpecs :: ModelIntelligence -> IO [ModelSpec]
getAllSpecs intel = do
  specs <- readTVarIO (miSpecs intel)
  pure $ Map.elems specs

-- | Get specs for a specific provider
getProviderSpecs :: ModelIntelligence -> ProviderName -> IO [ModelSpec]
getProviderSpecs intel provider = do
  specs <- readTVarIO (miSpecs intel)
  pure [spec | ((prov, _), spec) <- Map.toList specs, prov == provider]

-- | Get recently detected new models
getNewModels :: ModelIntelligence -> Int -> IO [NewModelEvent]
getNewModels intel limit = do
  history <- readTVarIO (miHistory intel)
  pure $ take limit history

-- | Get full model history
getModelHistory :: ModelIntelligence -> IO [NewModelEvent]
getModelHistory intel = readTVarIO (miHistory intel)

-- | Search models by query
searchModels :: ModelIntelligence -> Text -> IO [ModelSpec]
searchModels intel query = do
  specs <- readTVarIO (miSpecs intel)
  let queryLower = T.toLower query
      matches spec =
        queryLower `T.isInfixOf` T.toLower (specId spec)
          || maybe False (T.isInfixOf queryLower . T.toLower) (specDisplayName spec)
          || maybe False (T.isInfixOf queryLower . T.toLower) (specFamily spec)
  pure $ filter matches $ Map.elems specs

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // events
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit SSE event for new model detection
emitNewModelDetected :: EventBroadcaster -> NewModelEvent -> IO ()
emitNewModelDetected broadcaster event = do
  let spec = nmeSpec event
      modality = case specModality spec of
        TextOnly -> "text"
        TextAndCode -> "code"
        Vision -> "vision"
        Audio -> "audio"
        Multimodal -> "multimodal"
      timestamp = T.pack $ show (nmeDetectedAt event)
  Events.emitModelNew
    broadcaster
    (nmeModelId event)
    (T.pack $ show $ nmeProvider event)
    (specContextWindow spec)
    (specMaxOutput spec)
    modality
    (capToolUse $ specCapabilities spec)
    (capVision $ specCapabilities spec)
    (specFamily spec)
    timestamp
