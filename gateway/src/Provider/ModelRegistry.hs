-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // provider/model-registry
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "The matrix has its roots in primitive arcade games..."
--
--                                                              — Neuromancer
--
-- Dynamic model registry with realtime sync from providers.
-- Replaces hardcoded model prefix matching with actual API queries.
--
-- Features:
--   - Fetches model lists from each provider at startup
--   - Periodic background sync to catch new model releases
--   - Thread-safe concurrent access via STM
--   - Graceful degradation if provider unreachable
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Provider.ModelRegistry
  ( -- * Registry
    ModelRegistry,
    makeModelRegistry,
    closeModelRegistry,

    -- * Queries
    registrySupportsModel,
    getProviderModels,
    getAllModels,

    -- * Sync
    syncAll,
    syncProvider,

    -- * Types
    ModelInfo (ModelInfo, miId, miProvider, miOwnedBy, miCreated),
    ProviderModels,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.STM
import Control.Exception (IOException, try)
import Control.Monad (forM_, forever, when)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Effects.Graded (runGatewayM)
import Network.HTTP.Client (Manager)
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
    ProviderError
      ( AuthError,
        InternalError,
        InvalidRequestError,
        ModelNotFoundError,
        ProviderUnavailable,
        QuotaExceededError,
        RateLimitError,
        TimeoutError,
        UnknownError
      ),
    ProviderName (Anthropic, Baseten, LambdaLabs, OpenRouter, RunPod, Triton, VastAI, Venice, Vertex),
    ProviderResult (Failure, Retry, Success),
    RequestContext (RequestContext, rcClientIp, rcManager, rcRequestId),
    StreamCallback,
  )
import System.Timeout (timeout)
import Types
  ( Model (Model, modelCreated, modelId, modelObject, modelOwnedBy),
    ModelId (ModelId, unModelId),
    ModelList (ModelList, mlData, mlObject),
  )

-- ════════════════════════════════════════════════════════════════════════════
--                                                                   // types
-- ════════════════════════════════════════════════════════════════════════════

-- | Extended model info with provider metadata
data ModelInfo = ModelInfo
  { miId :: Text, -- Model ID (e.g., "llama-3.3-70b", "anthropic/claude-3-opus")
    miProvider :: ProviderName,
    miOwnedBy :: Maybe Text,
    miCreated :: Maybe Int
  }
  deriving (Eq, Show)

-- | Model set for a single provider
type ProviderModels = Set Text

-- | Cache entry with timestamp
data CacheEntry = CacheEntry
  { ceModels :: ProviderModels,
    ceLastSync :: UTCTime
  }
  deriving (Show)

-- | Model registry state
data ModelRegistry = ModelRegistry
  { mrCache :: TVar (Map ProviderName CacheEntry),
    mrManager :: Manager,
    mrProviders :: [Provider],
    mrSyncThread :: Maybe ThreadId,
    mrSyncInterval :: Int -- Seconds between syncs
  }

-- ════════════════════════════════════════════════════════════════════════════
--                                                           // construction
-- ════════════════════════════════════════════════════════════════════════════

-- | Create a model registry and start background sync
-- syncIntervalSec: how often to refresh model lists (0 = no background sync)
--
-- Initial sync is async to avoid blocking server startup. The registry starts
-- empty and populates as providers respond (graceful degradation).
makeModelRegistry :: Manager -> [Provider] -> Int -> IO ModelRegistry
makeModelRegistry manager providers syncIntervalSec = do
  cacheVar <- newTVarIO Map.empty

  let registry =
        ModelRegistry
          { mrCache = cacheVar,
            mrManager = manager,
            mrProviders = providers,
            mrSyncThread = Nothing,
            mrSyncInterval = syncIntervalSec
          }

  -- Initial sync (async with timeout to avoid blocking startup)
  -- Runs in background so server can start immediately
  _ <- forkIO $ do
    -- 10 second timeout for initial sync of all providers
    _ <- timeout (10 * 1000000) (syncAll registry)
    pure ()

  -- Start background sync if interval > 0
  if syncIntervalSec > 0
    then do
      tid <- forkIO $ syncLoop registry
      pure registry {mrSyncThread = Just tid}
    else pure registry

-- | Stop background sync
closeModelRegistry :: ModelRegistry -> IO ()
closeModelRegistry registry =
  case mrSyncThread registry of
    Just tid -> killThread tid
    Nothing -> pure ()

-- | Background sync loop
syncLoop :: ModelRegistry -> IO ()
syncLoop registry = forever $ do
  threadDelay (mrSyncInterval registry * 1000000)
  syncAll registry

-- ════════════════════════════════════════════════════════════════════════════
--                                                                  // sync
-- ════════════════════════════════════════════════════════════════════════════

-- | Sync all providers
syncAll :: ModelRegistry -> IO ()
syncAll registry =
  forM_ (mrProviders registry) $ \provider ->
    syncProvider registry provider

-- | Sync a single provider (with timeout per provider)
syncProvider :: ModelRegistry -> Provider -> IO ()
syncProvider registry provider = do
  let name = providerName provider
      ctx =
        RequestContext
          { rcManager = mrManager registry,
            rcRequestId = "model-sync",
            rcClientIp = Nothing
          }

  -- Check if provider is enabled first
  (enabledResult, _, _, _) <- runGatewayM (providerEnabled provider)
  when enabledResult $ do
    -- Fetch models with 5s timeout per provider
    -- Uses IOException instead of SomeException for precise error handling
    mResult <- timeout (5 * 1000000) $ do
      result <- try @IOException $ do
        (modelsResult, _, _, _) <- runGatewayM (providerModels provider ctx)
        pure modelsResult
      pure result

    case mResult of
      Nothing ->
        -- Timeout, keep existing cache
        pure ()
      Just (Left _err) ->
        -- IO error (network), keep existing cache
        pure ()
      Just (Right (Success modelList)) -> do
        let modelIds = Set.fromList $ map (unModelId . modelId) $ mlData modelList
        now <- getCurrentTime
        atomically $
          modifyTVar' (mrCache registry) $
            Map.insert name (CacheEntry modelIds now)
      Just (Right (Failure _)) ->
        -- Provider returned error, keep existing cache
        pure ()
      Just (Right (Retry _)) ->
        -- Temporary error, keep existing cache
        pure ()

-- ════════════════════════════════════════════════════════════════════════════
--                                                                // queries
-- ════════════════════════════════════════════════════════════════════════════

-- | Check if a provider supports a given model
-- Falls back to heuristics if no cached data
registrySupportsModel :: ModelRegistry -> ProviderName -> Text -> IO Bool
registrySupportsModel registry name modelId = do
  cache <- readTVarIO (mrCache registry)
  case Map.lookup name cache of
    Just entry -> pure $ Set.member modelId (ceModels entry)
    Nothing -> pure $ fallbackSupportsModel name modelId

-- | Get all models for a provider
getProviderModels :: ModelRegistry -> ProviderName -> IO (Set Text)
getProviderModels registry name = do
  cache <- readTVarIO (mrCache registry)
  pure $ maybe Set.empty ceModels (Map.lookup name cache)

-- | Get all models across all providers
getAllModels :: ModelRegistry -> IO (Map ProviderName (Set Text))
getAllModels registry = do
  cache <- readTVarIO (mrCache registry)
  pure $ Map.map ceModels cache

-- ════════════════════════════════════════════════════════════════════════════
--                                                    // fallback heuristics
-- ════════════════════════════════════════════════════════════════════════════

-- | Fallback heuristics when registry has no cached data
-- Used during initial sync or if provider is unreachable
fallbackSupportsModel :: ProviderName -> Text -> Bool
fallbackSupportsModel Triton modelId =
  -- Triton/TensorRT-LLM typically runs these model families
  any
    (`T.isPrefixOf` modelId)
    [ "llama",
      "meta-llama",
      "codellama",
      "mistral",
      "mixtral",
      "qwen",
      "deepseek",
      "phi",
      "triton/",
      "local/"
    ]
fallbackSupportsModel Venice modelId =
  -- Venice supports these model prefixes
  any
    (`T.isPrefixOf` modelId)
    [ "llama-",
      "deepseek-",
      "qwen-",
      "dolphin-",
      "mistral-",
      "venice-"
    ]
fallbackSupportsModel OpenRouter modelId =
  -- OpenRouter uses provider/model format
  "/" `T.isInfixOf` modelId
    || any
      (`T.isPrefixOf` modelId)
      [ "gpt-",
        "claude-",
        "llama-",
        "mistral-",
        "gemini-"
      ]
fallbackSupportsModel Anthropic modelId =
  -- Anthropic models
  any
    (`T.isPrefixOf` modelId)
    [ "claude-"
    ]
fallbackSupportsModel Vertex modelId =
  -- Vertex supports Google models
  any
    (`T.isPrefixOf` modelId)
    [ "gemini-",
      "palm-",
      "text-bison"
    ]
fallbackSupportsModel Baseten modelId =
  -- Baseten deploys custom models
  any
    (`T.isPrefixOf` modelId)
    [ "llama-",
      "mistral-",
      "deepseek-",
      "deepseek-ai/",  -- Full org/model format (e.g., deepseek-ai/DeepSeek-V3.1)
      "qwen-"
    ]
-- GPU compute providers (rate aggregation only, no LLM inference)
fallbackSupportsModel LambdaLabs _ = False
fallbackSupportsModel RunPod _ = False
fallbackSupportsModel VastAI _ = False
