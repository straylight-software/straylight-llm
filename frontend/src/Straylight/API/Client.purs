-- | API client for straylight-llm gateway
module Straylight.API.Client
  ( Config
  , defaultConfig
  , healthCheck
  , getModels
  , getProof
  , getRequests
  , getRequestDetail
  , getDashboard
  , HealthResponse
  , Model
  , ModelList
  , DischargeProof
  , Coeffect(Pure, Network, Auth, Sandbox, Filesystem, Combined)
  , NetworkAccess
  , FilesystemAccess
  , AuthUsage
  , OutputHash
  , SignatureInfo
  -- Request timeline types
  , RequestStatus(..)
  , RequestsResponse
  , GatewayRequest
  , RequestDetail
  , RequestFilter
  , RetryAttempt
  , defaultFilter
  -- Provider status types  
  , CircuitBreakerState(..)
  , ProviderStatus
  -- Dashboard types
  , DashboardResponse(DashboardResponse)
  , DashboardResponseRec
  , unwrapDashboardResponse
  , ProviderHealth(ProviderHealth)
  , ProviderHealthRec
  , unwrapProviderHealth
  ) where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (class DecodeJson, class EncodeJson, decodeJson, encodeJson, JsonDecodeError(TypeMismatch, MissingValue, UnexpectedValue), printJsonDecodeError, Json)
import Data.Argonaut.Decode.Decoders as Decoders
import Data.Argonaut.Core (toObject, fromString, fromObject, fromArray, fromNumber, fromBoolean)
import Data.Argonaut.Encode.Encoders as Encoders
import Data.Array as Array
import Data.Either (Either(Left, Right))
import Data.Maybe (Maybe(Nothing, Just))
import Data.Tuple (Tuple(Tuple))
import Effect.Aff (Aff)
import Foreign.Object as Object


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // config
-- ════════════════════════════════════════════════════════════════════════════

type Config =
  { baseUrl :: String
  , port :: Int
  }

-- | Default config using localhost.
-- For cross-machine access, use configFromLocation to auto-detect host.
defaultConfig :: Config
defaultConfig =
  { baseUrl: "http://localhost"
  , port: 8080
  }

mkUrl :: Config -> String -> String
mkUrl cfg path = cfg.baseUrl <> ":" <> show cfg.port <> path


-- ════════════════════════════════════════════════════════════════════════════
--                                                                     // types
-- ════════════════════════════════════════════════════════════════════════════

type HealthResponse =
  { status :: String
  , version :: String
  }

type Model =
  { id :: String
  , object :: String
  , created :: Int
  , ownedBy :: String
  }

type ModelList =
  { object :: String
  , data :: Array Model
  }

-- | Coeffect: what external resources a computation may access
data Coeffect
  = Pure
  | Network
  | Auth String
  | Sandbox String
  | Filesystem String
  | Combined (Array Coeffect)

instance decodeJsonCoeffect :: DecodeJson Coeffect where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for Coeffect")
    Just obj -> case Object.lookup "type" obj of
      Nothing -> Left MissingValue
      Just typeJson -> do
        ty <- Decoders.decodeString typeJson
        case ty of
          "pure" -> Right Pure
          "network" -> Right Network
          "auth" -> case Object.lookup "provider" obj of
            Just p -> Auth <$> Decoders.decodeString p
            Nothing -> Left MissingValue
          "sandbox" -> case Object.lookup "path" obj of
            Just p -> Sandbox <$> Decoders.decodeString p
            Nothing -> Left MissingValue
          "filesystem" -> case Object.lookup "path" obj of
            Just p -> Filesystem <$> Decoders.decodeString p
            Nothing -> Left MissingValue
          "combined" -> case Object.lookup "coeffects" obj of
            Just cs -> Combined <$> Decoders.decodeArray decodeJson cs
            Nothing -> Left MissingValue
          _ -> Left (UnexpectedValue json)

instance encodeJsonCoeffect :: EncodeJson Coeffect where
  encodeJson = case _ of
    Pure -> fromObject $ Object.singleton "type" (fromString "pure")
    Network -> fromObject $ Object.singleton "type" (fromString "network")
    Auth provider -> fromObject $ Object.fromFoldable
      [ Tuple "type" (fromString "auth")
      , Tuple "provider" (fromString provider)
      ]
    Sandbox path -> fromObject $ Object.fromFoldable
      [ Tuple "type" (fromString "sandbox")
      , Tuple "path" (fromString path)
      ]
    Filesystem path -> fromObject $ Object.fromFoldable
      [ Tuple "type" (fromString "filesystem")
      , Tuple "path" (fromString path)
      ]
    Combined cs -> fromObject $ Object.fromFoldable
      [ Tuple "type" (fromString "combined")
      , Tuple "coeffects" (fromArray $ map encodeJson cs)
      ]

type NetworkAccess =
  { url :: String
  , method :: String
  , contentHash :: String
  , timestamp :: String
  }

type FilesystemAccess =
  { path :: String
  , mode :: String
  , contentHash :: Maybe String
  , timestamp :: String
  }

type AuthUsage =
  { provider :: String
  , scope :: Maybe String
  , timestamp :: String
  }

type OutputHash =
  { name :: String
  , hash :: String
  }

type SignatureInfo =
  { publicKey :: String
  , signature :: String
  }

type DischargeProof =
  { coeffects :: Array Coeffect
  , networkAccess :: Array NetworkAccess
  , filesystemAccess :: Array FilesystemAccess
  , authUsage :: Array AuthUsage
  , buildId :: String
  , derivationHash :: String
  , outputHashes :: Array OutputHash
  , startTime :: String
  , endTime :: String
  , signature :: Maybe SignatureInfo
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // request timeline types
-- ════════════════════════════════════════════════════════════════════════════

-- | Status of a gateway request
data RequestStatus
  = Pending
  | Success
  | Error
  | Retrying

derive instance eqRequestStatus :: Eq RequestStatus

instance decodeJsonRequestStatus :: DecodeJson RequestStatus where
  decodeJson json = do
    str <- Decoders.decodeString json
    case str of
      "pending" -> Right Pending
      "success" -> Right Success
      "error" -> Right Error
      "retrying" -> Right Retrying
      _ -> Left (UnexpectedValue json)

instance encodeJsonRequestStatus :: EncodeJson RequestStatus where
  encodeJson = fromString <<< case _ of
    Pending -> "pending"
    Success -> "success"
    Error -> "error"
    Retrying -> "retrying"

-- | Response from GET /v1/admin/requests
type RequestsResponse =
  { requests :: Array GatewayRequest
  , total :: Int
  , offset :: Int
  , limit :: Int
  }

-- | A gateway request in the list
type GatewayRequest =
  { requestId :: String
  , timestamp :: String
  , model :: String
  , provider :: String
  , status :: RequestStatus
  , latencyMs :: Int
  , promptTokens :: Int
  , completionTokens :: Int
  }

-- | Detailed view of a single request
type RequestDetail =
  { requestId :: String
  , timestamp :: String
  , model :: String
  , provider :: String
  , status :: RequestStatus
  , latencyMs :: Int
  , promptTokens :: Int
  , completionTokens :: Int
  , requestBody :: String
  , responseBody :: String
  , coeffects :: Array Coeffect
  , retryHistory :: Array RetryAttempt
  , errorMessage :: Maybe String
  , proofId :: Maybe String
  }

-- | A retry attempt in the request history
type RetryAttempt =
  { provider :: String
  , timestamp :: String
  , status :: RequestStatus
  , latencyMs :: Int
  , errorMessage :: Maybe String
  }

-- | Filter options for request listing
type RequestFilter =
  { provider :: Maybe String
  , model :: Maybe String
  , status :: Maybe RequestStatus
  , limit :: Int
  , offset :: Int
  }

-- | Default filter (no filtering, first page)
defaultFilter :: RequestFilter
defaultFilter =
  { provider: Nothing
  , model: Nothing
  , status: Nothing
  , limit: 50
  , offset: 0
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                      // provider status types
-- ════════════════════════════════════════════════════════════════════════════

-- | Circuit breaker state
data CircuitBreakerState
  = CBClosed
  | CBOpen
  | CBHalfOpen

derive instance eqCircuitBreakerState :: Eq CircuitBreakerState

instance decodeJsonCircuitBreakerState :: DecodeJson CircuitBreakerState where
  decodeJson json = do
    str <- Decoders.decodeString json
    case str of
      "closed" -> Right CBClosed
      "open" -> Right CBOpen
      "half-open" -> Right CBHalfOpen
      _ -> Left (UnexpectedValue json)

instance encodeJsonCircuitBreakerState :: EncodeJson CircuitBreakerState where
  encodeJson = fromString <<< case _ of
    CBClosed -> "closed"
    CBOpen -> "open"
    CBHalfOpen -> "half-open"

-- | Provider status from admin endpoint
type ProviderStatus =
  { name :: String
  , status :: String
  , circuitBreakerState :: CircuitBreakerState
  , failures :: Int
  , threshold :: Int
  , lastSuccess :: Maybe String
  , avgLatencyMs :: Maybe Int
  }


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // api calls
-- ════════════════════════════════════════════════════════════════════════════

-- | Health check endpoint
healthCheck :: Config -> Aff (Either String HealthResponse)
healthCheck cfg = do
  result <- AX.get ResponseFormat.json (mkUrl cfg "/health")
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Get available models
getModels :: Config -> Aff (Either String ModelList)
getModels cfg = do
  result <- AX.get ResponseFormat.json (mkUrl cfg "/v1/models")
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Get discharge proof by request ID
getProof :: Config -> String -> Aff (Either String DischargeProof)
getProof cfg requestId = do
  result <- AX.get ResponseFormat.json (mkUrl cfg $ "/v1/proof/" <> requestId)
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Get request history with optional filtering
getRequests :: Config -> RequestFilter -> Aff (Either String RequestsResponse)
getRequests cfg filter = do
  let queryParams = buildFilterParams filter
      url = mkUrl cfg "/v1/admin/requests" <> queryParams
  result <- AX.get ResponseFormat.json url
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Get detailed info for a single request
getRequestDetail :: Config -> String -> Aff (Either String RequestDetail)
getRequestDetail cfg requestId = do
  result <- AX.get ResponseFormat.json (mkUrl cfg $ "/v1/admin/requests/" <> requestId)
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Build query params from filter
buildFilterParams :: RequestFilter -> String
buildFilterParams f = 
  let params = 
        [ Just ("limit=" <> show f.limit)
        , Just ("offset=" <> show f.offset)
        , (\p -> "provider=" <> p) <$> f.provider
        , (\m -> "model=" <> m) <$> f.model
        , (\s -> "status=" <> statusToString s) <$> f.status
        ]
      validParams = Array.catMaybes params
  in if Array.null validParams
       then ""
       else "?" <> joinWith "&" validParams

statusToString :: RequestStatus -> String
statusToString = case _ of
  Pending -> "pending"
  Success -> "success"
  Error -> "error"
  Retrying -> "retrying"

joinWith :: String -> Array String -> String
joinWith sep arr = case Array.uncons arr of
  Nothing -> ""
  Just { head, tail } -> 
    if Array.null tail 
      then head 
      else head <> sep <> joinWith sep tail


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // dashboard types
-- ════════════════════════════════════════════════════════════════════════════

-- | Provider health with latency percentiles, TTFT, and health score
-- | Uses snake_case field names matching backend JSON for automatic deriving
type ProviderHealthRec =
  { name :: String
  , enabled :: Boolean
  , circuit_state :: CircuitBreakerState
  , health_score :: Number        -- 0-100
  , latency_avg_ms :: Maybe Number
  , latency_p50_ms :: Maybe Number
  , latency_p95_ms :: Maybe Number
  , latency_p99_ms :: Maybe Number
  , ttft_avg_ms :: Maybe Number   -- Time to first token (streaming)
  , ttft_p50_ms :: Maybe Number
  , ttft_p95_ms :: Maybe Number
  , ttft_p99_ms :: Maybe Number
  , error_rate :: Number          -- 0.0-1.0
  , request_count :: Int
  , error_count :: Int
  , last_error :: Maybe String
  }

-- | Newtype wrapper for ProviderHealth with custom JSON instances
newtype ProviderHealth = ProviderHealth ProviderHealthRec

-- | Unwrap ProviderHealth to access fields
unwrapProviderHealth :: ProviderHealth -> ProviderHealthRec
unwrapProviderHealth (ProviderHealth r) = r

instance decodeJsonProviderHealth :: DecodeJson ProviderHealth where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ProviderHealth")
    Just obj -> do
      name <- getFieldReq obj "name"
      enabled <- getFieldReq obj "enabled"
      circuit_state <- getFieldReq obj "circuit_state"
      health_score <- getFieldReq obj "health_score"
      latency_avg_ms <- getFieldOpt obj "latency_avg_ms"
      latency_p50_ms <- getFieldOpt obj "latency_p50_ms"
      latency_p95_ms <- getFieldOpt obj "latency_p95_ms"
      latency_p99_ms <- getFieldOpt obj "latency_p99_ms"
      ttft_avg_ms <- getFieldOpt obj "ttft_avg_ms"
      ttft_p50_ms <- getFieldOpt obj "ttft_p50_ms"
      ttft_p95_ms <- getFieldOpt obj "ttft_p95_ms"
      ttft_p99_ms <- getFieldOpt obj "ttft_p99_ms"
      error_rate <- getFieldReq obj "error_rate"
      request_count <- getFieldReq obj "request_count"
      error_count <- getFieldReq obj "error_count"
      last_error <- getFieldOpt obj "last_error"
      pure $ ProviderHealth { name, enabled, circuit_state, health_score, latency_avg_ms, latency_p50_ms, latency_p95_ms, latency_p99_ms, ttft_avg_ms, ttft_p50_ms, ttft_p95_ms, ttft_p99_ms, error_rate, request_count, error_count, last_error }

instance encodeJsonProviderHealth :: EncodeJson ProviderHealth where
  encodeJson (ProviderHealth ph) = fromObject $ Object.fromFoldable
    [ Tuple "name" (fromString ph.name)
    , Tuple "enabled" (fromBoolean ph.enabled)
    , Tuple "circuit_state" (encodeJson ph.circuit_state)
    , Tuple "health_score" (fromNumber ph.health_score)
    , Tuple "latency_avg_ms" (encodeJson ph.latency_avg_ms)
    , Tuple "latency_p50_ms" (encodeJson ph.latency_p50_ms)
    , Tuple "latency_p95_ms" (encodeJson ph.latency_p95_ms)
    , Tuple "latency_p99_ms" (encodeJson ph.latency_p99_ms)
    , Tuple "ttft_avg_ms" (encodeJson ph.ttft_avg_ms)
    , Tuple "ttft_p50_ms" (encodeJson ph.ttft_p50_ms)
    , Tuple "ttft_p95_ms" (encodeJson ph.ttft_p95_ms)
    , Tuple "ttft_p99_ms" (encodeJson ph.ttft_p99_ms)
    , Tuple "error_rate" (fromNumber ph.error_rate)
    , Tuple "request_count" (encodeJson ph.request_count)
    , Tuple "error_count" (encodeJson ph.error_count)
    , Tuple "last_error" (encodeJson ph.last_error)
    ]

-- | Dashboard response with aggregate provider health
type DashboardResponseRec =
  { timestamp :: String          -- ISO8601
  , uptime_seconds :: Number
  , providers :: Array ProviderHealth
  , total_requests :: Int
  , active_requests :: Int
  , cache_hit_rate :: Maybe Number -- 0.0-1.0
  }

-- | Newtype wrapper for DashboardResponse with custom JSON instances
newtype DashboardResponse = DashboardResponse DashboardResponseRec

-- | Unwrap DashboardResponse to access fields
unwrapDashboardResponse :: DashboardResponse -> DashboardResponseRec
unwrapDashboardResponse (DashboardResponse r) = r

instance decodeJsonDashboardResponse :: DecodeJson DashboardResponse where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for DashboardResponse")
    Just obj -> do
      timestamp <- getFieldReq obj "timestamp"
      uptime_seconds <- getFieldReq obj "uptime_seconds"
      providers <- getFieldReq obj "providers"
      total_requests <- getFieldReq obj "total_requests"
      active_requests <- getFieldReq obj "active_requests"
      cache_hit_rate <- getFieldOpt obj "cache_hit_rate"
      pure $ DashboardResponse { timestamp, uptime_seconds, providers, total_requests, active_requests, cache_hit_rate }

instance encodeJsonDashboardResponse :: EncodeJson DashboardResponse where
  encodeJson (DashboardResponse dr) = fromObject $ Object.fromFoldable
    [ Tuple "timestamp" (fromString dr.timestamp)
    , Tuple "uptime_seconds" (fromNumber dr.uptime_seconds)
    , Tuple "providers" (encodeJson dr.providers)
    , Tuple "total_requests" (encodeJson dr.total_requests)
    , Tuple "active_requests" (encodeJson dr.active_requests)
    , Tuple "cache_hit_rate" (encodeJson dr.cache_hit_rate)
    ]

-- Helper for required fields
getFieldReq :: forall a. DecodeJson a => Object.Object Json -> String -> Either JsonDecodeError a
getFieldReq obj key = case Object.lookup key obj of
  Nothing -> Left MissingValue
  Just v -> decodeJson v

-- Helper for optional fields  
getFieldOpt :: forall a. DecodeJson a => Object.Object Json -> String -> Either JsonDecodeError (Maybe a)
getFieldOpt obj key = case Object.lookup key obj of
  Nothing -> Right Nothing
  Just v -> Just <$> decodeJson v


-- ════════════════════════════════════════════════════════════════════════════
--                                                     // dashboard api call
-- ════════════════════════════════════════════════════════════════════════════

-- | Get dashboard with provider health data
getDashboard :: Config -> Aff (Either String DashboardResponse)
getDashboard cfg = do
  result <- AX.get ResponseFormat.json (mkUrl cfg "/v1/admin/dashboard")
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r


-- ════════════════════════════════════════════════════════════════════════════
--                                                  // model intelligence types
-- ════════════════════════════════════════════════════════════════════════════

-- | Model modality (what types of input/output the model supports)
data ModelModality
  = TextOnly
  | TextAndCode
  | Vision
  | Audio
  | Multimodal

derive instance eqModelModality :: Eq ModelModality

instance decodeJsonModelModality :: DecodeJson ModelModality where
  decodeJson json = do
    str <- Decoders.decodeString json
    case str of
      "TextOnly" -> Right TextOnly
      "TextAndCode" -> Right TextAndCode
      "Vision" -> Right Vision
      "Audio" -> Right Audio
      "Multimodal" -> Right Multimodal
      _ -> Left (UnexpectedValue json)

instance encodeJsonModelModality :: EncodeJson ModelModality where
  encodeJson = fromString <<< case _ of
    TextOnly -> "TextOnly"
    TextAndCode -> "TextAndCode"
    Vision -> "Vision"
    Audio -> "Audio"
    Multimodal -> "Multimodal"

-- | API format the model uses
data APIFormat
  = OpenAICompat
  | AnthropicMessages
  | GoogleVertex
  | CustomFormat String

derive instance eqAPIFormat :: Eq APIFormat

instance decodeJsonAPIFormat :: DecodeJson APIFormat where
  decodeJson json = case toObject json of
    Nothing -> do
      str <- Decoders.decodeString json
      case str of
        "OpenAICompat" -> Right OpenAICompat
        "AnthropicMessages" -> Right AnthropicMessages
        "GoogleVertex" -> Right GoogleVertex
        _ -> Left (UnexpectedValue json)
    Just obj -> case Object.lookup "Custom" obj of
      Just desc -> CustomFormat <$> Decoders.decodeString desc
      Nothing -> Left (TypeMismatch "Unknown APIFormat variant")

instance encodeJsonAPIFormat :: EncodeJson APIFormat where
  encodeJson = case _ of
    OpenAICompat -> fromString "OpenAICompat"
    AnthropicMessages -> fromString "AnthropicMessages"
    GoogleVertex -> fromString "GoogleVertex"
    CustomFormat desc -> fromObject $ Object.singleton "Custom" (fromString desc)

-- | Model capabilities
type ModelCapabilitiesRec =
  { capToolUse :: Boolean
  , capStreaming :: Boolean
  , capSystemPrompt :: Boolean
  , capJsonMode :: Boolean
  , capVision :: Boolean
  , capCodeExecution :: Boolean
  , capWebSearch :: Boolean
  , capFileUpload :: Boolean
  , capFineTuning :: Boolean
  , capBatching :: Boolean
  }

newtype ModelCapabilities = ModelCapabilities ModelCapabilitiesRec

unwrapModelCapabilities :: ModelCapabilities -> ModelCapabilitiesRec
unwrapModelCapabilities (ModelCapabilities r) = r

instance decodeJsonModelCapabilities :: DecodeJson ModelCapabilities where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ModelCapabilities")
    Just obj -> do
      capToolUse <- getFieldReq obj "capToolUse"
      capStreaming <- getFieldReq obj "capStreaming"
      capSystemPrompt <- getFieldReq obj "capSystemPrompt"
      capJsonMode <- getFieldReq obj "capJsonMode"
      capVision <- getFieldReq obj "capVision"
      capCodeExecution <- getFieldReq obj "capCodeExecution"
      capWebSearch <- getFieldReq obj "capWebSearch"
      capFileUpload <- getFieldReq obj "capFileUpload"
      capFineTuning <- getFieldReq obj "capFineTuning"
      capBatching <- getFieldReq obj "capBatching"
      pure $ ModelCapabilities { capToolUse, capStreaming, capSystemPrompt, capJsonMode, capVision, capCodeExecution, capWebSearch, capFileUpload, capFineTuning, capBatching }

instance encodeJsonModelCapabilities :: EncodeJson ModelCapabilities where
  encodeJson (ModelCapabilities mc) = fromObject $ Object.fromFoldable
    [ Tuple "capToolUse" (fromBoolean mc.capToolUse)
    , Tuple "capStreaming" (fromBoolean mc.capStreaming)
    , Tuple "capSystemPrompt" (fromBoolean mc.capSystemPrompt)
    , Tuple "capJsonMode" (fromBoolean mc.capJsonMode)
    , Tuple "capVision" (fromBoolean mc.capVision)
    , Tuple "capCodeExecution" (fromBoolean mc.capCodeExecution)
    , Tuple "capWebSearch" (fromBoolean mc.capWebSearch)
    , Tuple "capFileUpload" (fromBoolean mc.capFileUpload)
    , Tuple "capFineTuning" (fromBoolean mc.capFineTuning)
    , Tuple "capBatching" (fromBoolean mc.capBatching)
    ]

-- | Model pricing (per million tokens, USD)
type ModelPricingRec =
  { priceInput :: Maybe Number
  , priceOutput :: Maybe Number
  , priceCachedInput :: Maybe Number
  , priceBatch :: Maybe Number
  , priceFree :: Boolean
  }

newtype ModelPricing = ModelPricing ModelPricingRec

unwrapModelPricing :: ModelPricing -> ModelPricingRec
unwrapModelPricing (ModelPricing r) = r

instance decodeJsonModelPricing :: DecodeJson ModelPricing where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ModelPricing")
    Just obj -> do
      priceInput <- getFieldOpt obj "priceInput"
      priceOutput <- getFieldOpt obj "priceOutput"
      priceCachedInput <- getFieldOpt obj "priceCachedInput"
      priceBatch <- getFieldOpt obj "priceBatch"
      priceFree <- getFieldReq obj "priceFree"
      pure $ ModelPricing { priceInput, priceOutput, priceCachedInput, priceBatch, priceFree }

instance encodeJsonModelPricing :: EncodeJson ModelPricing where
  encodeJson (ModelPricing mp) = fromObject $ Object.fromFoldable
    [ Tuple "priceInput" (encodeJson mp.priceInput)
    , Tuple "priceOutput" (encodeJson mp.priceOutput)
    , Tuple "priceCachedInput" (encodeJson mp.priceCachedInput)
    , Tuple "priceBatch" (encodeJson mp.priceBatch)
    , Tuple "priceFree" (fromBoolean mp.priceFree)
    ]

-- | Complete model specification
type ModelSpecRec =
  { specId :: String
  , specProvider :: String
  , specDisplayName :: Maybe String
  , specDescription :: Maybe String
  , specContextWindow :: Maybe Int
  , specMaxOutput :: Maybe Int
  , specModality :: ModelModality
  , specCapabilities :: ModelCapabilities
  , specPricing :: ModelPricing
  , specAPIFormat :: APIFormat
  , specFamily :: Maybe String
  , specVersion :: Maybe String
  , specReleaseDate :: Maybe String
  , specDeprecated :: Boolean
  , specFirstSeen :: String
  , specLastSeen :: String
  , specOwnedBy :: Maybe String
  }

newtype ModelSpec = ModelSpec ModelSpecRec

unwrapModelSpec :: ModelSpec -> ModelSpecRec
unwrapModelSpec (ModelSpec r) = r

instance decodeJsonModelSpec :: DecodeJson ModelSpec where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ModelSpec")
    Just obj -> do
      specId <- getFieldReq obj "specId"
      specProvider <- getFieldReq obj "specProvider"
      specDisplayName <- getFieldOpt obj "specDisplayName"
      specDescription <- getFieldOpt obj "specDescription"
      specContextWindow <- getFieldOpt obj "specContextWindow"
      specMaxOutput <- getFieldOpt obj "specMaxOutput"
      specModality <- getFieldReq obj "specModality"
      specCapabilities <- getFieldReq obj "specCapabilities"
      specPricing <- getFieldReq obj "specPricing"
      specAPIFormat <- getFieldReq obj "specAPIFormat"
      specFamily <- getFieldOpt obj "specFamily"
      specVersion <- getFieldOpt obj "specVersion"
      specReleaseDate <- getFieldOpt obj "specReleaseDate"
      specDeprecated <- getFieldReq obj "specDeprecated"
      specFirstSeen <- getFieldReq obj "specFirstSeen"
      specLastSeen <- getFieldReq obj "specLastSeen"
      specOwnedBy <- getFieldOpt obj "specOwnedBy"
      pure $ ModelSpec { specId, specProvider, specDisplayName, specDescription, specContextWindow, specMaxOutput, specModality, specCapabilities, specPricing, specAPIFormat, specFamily, specVersion, specReleaseDate, specDeprecated, specFirstSeen, specLastSeen, specOwnedBy }

instance encodeJsonModelSpec :: EncodeJson ModelSpec where
  encodeJson (ModelSpec ms) = fromObject $ Object.fromFoldable
    [ Tuple "specId" (fromString ms.specId)
    , Tuple "specProvider" (fromString ms.specProvider)
    , Tuple "specDisplayName" (encodeJson ms.specDisplayName)
    , Tuple "specDescription" (encodeJson ms.specDescription)
    , Tuple "specContextWindow" (encodeJson ms.specContextWindow)
    , Tuple "specMaxOutput" (encodeJson ms.specMaxOutput)
    , Tuple "specModality" (encodeJson ms.specModality)
    , Tuple "specCapabilities" (encodeJson ms.specCapabilities)
    , Tuple "specPricing" (encodeJson ms.specPricing)
    , Tuple "specAPIFormat" (encodeJson ms.specAPIFormat)
    , Tuple "specFamily" (encodeJson ms.specFamily)
    , Tuple "specVersion" (encodeJson ms.specVersion)
    , Tuple "specReleaseDate" (encodeJson ms.specReleaseDate)
    , Tuple "specDeprecated" (fromBoolean ms.specDeprecated)
    , Tuple "specFirstSeen" (fromString ms.specFirstSeen)
    , Tuple "specLastSeen" (fromString ms.specLastSeen)
    , Tuple "specOwnedBy" (encodeJson ms.specOwnedBy)
    ]

-- | New model event (for newly detected models)
type NewModelEventRec =
  { nmeModelId :: String
  , nmeProvider :: String
  , nmeDetectedAt :: String
  }

newtype NewModelEvent = NewModelEvent NewModelEventRec

unwrapNewModelEvent :: NewModelEvent -> NewModelEventRec
unwrapNewModelEvent (NewModelEvent r) = r

instance decodeJsonNewModelEvent :: DecodeJson NewModelEvent where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for NewModelEvent")
    Just obj -> do
      nmeModelId <- getFieldReq obj "nmeModelId"
      nmeProvider <- getFieldReq obj "nmeProvider"
      nmeDetectedAt <- getFieldReq obj "nmeDetectedAt"
      pure $ NewModelEvent { nmeModelId, nmeProvider, nmeDetectedAt }

instance encodeJsonNewModelEvent :: EncodeJson NewModelEvent where
  encodeJson (NewModelEvent nme) = fromObject $ Object.fromFoldable
    [ Tuple "nmeModelId" (fromString nme.nmeModelId)
    , Tuple "nmeProvider" (fromString nme.nmeProvider)
    , Tuple "nmeDetectedAt" (fromString nme.nmeDetectedAt)
    ]

-- | Response from GET /v1/admin/models
type ModelsListResponseRec =
  { models :: Array ModelSpec
  , total :: Int
  , timestamp :: String
  }

newtype ModelsListResponse = ModelsListResponse ModelsListResponseRec

unwrapModelsListResponse :: ModelsListResponse -> ModelsListResponseRec
unwrapModelsListResponse (ModelsListResponse r) = r

instance decodeJsonModelsListResponse :: DecodeJson ModelsListResponse where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ModelsListResponse")
    Just obj -> do
      models <- getFieldReq obj "models"
      total <- getFieldReq obj "total"
      timestamp <- getFieldReq obj "timestamp"
      pure $ ModelsListResponse { models, total, timestamp }

instance encodeJsonModelsListResponse :: EncodeJson ModelsListResponse where
  encodeJson (ModelsListResponse mlr) = fromObject $ Object.fromFoldable
    [ Tuple "models" (encodeJson mlr.models)
    , Tuple "total" (encodeJson mlr.total)
    , Tuple "timestamp" (fromString mlr.timestamp)
    ]

-- | Response from GET /v1/admin/models/new
type ModelsNewResponseRec =
  { models :: Array NewModelEvent
  , total :: Int
  }

newtype ModelsNewResponse = ModelsNewResponse ModelsNewResponseRec

unwrapModelsNewResponse :: ModelsNewResponse -> ModelsNewResponseRec
unwrapModelsNewResponse (ModelsNewResponse r) = r

instance decodeJsonModelsNewResponse :: DecodeJson ModelsNewResponse where
  decodeJson json = case toObject json of
    Nothing -> Left (TypeMismatch "Expected object for ModelsNewResponse")
    Just obj -> do
      models <- getFieldReq obj "models"
      total <- getFieldReq obj "total"
      pure $ ModelsNewResponse { models, total }

instance encodeJsonModelsNewResponse :: EncodeJson ModelsNewResponse where
  encodeJson (ModelsNewResponse mnr) = fromObject $ Object.fromFoldable
    [ Tuple "models" (encodeJson mnr.models)
    , Tuple "total" (encodeJson mnr.total)
    ]


-- ════════════════════════════════════════════════════════════════════════════
--                                                // model intelligence api calls
-- ════════════════════════════════════════════════════════════════════════════

-- | Model list filter options
type ModelFilter =
  { provider :: Maybe String
  , search :: Maybe String
  }

defaultModelFilter :: ModelFilter
defaultModelFilter =
  { provider: Nothing
  , search: Nothing
  }

-- | Get all model specs with optional filtering
getModelSpecs :: Config -> ModelFilter -> Aff (Either String ModelsListResponse)
getModelSpecs cfg filter = do
  let params = buildModelFilterParams filter
      url = mkUrl cfg "/v1/admin/models" <> params
  result <- AX.get ResponseFormat.json url
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Get newly detected models
getNewModels :: Config -> Maybe Int -> Aff (Either String ModelsNewResponse)
getNewModels cfg mLimit = do
  let limitParam = case mLimit of
        Nothing -> ""
        Just n -> "?limit=" <> show n
      url = mkUrl cfg "/v1/admin/models/new" <> limitParam
  result <- AX.get ResponseFormat.json url
  pure $ case result of
    Left err -> Left $ AX.printError err
    Right response -> case decodeJson response.body of
      Left e -> Left $ printJsonDecodeError e
      Right r -> Right r

-- | Build query params from model filter
buildModelFilterParams :: ModelFilter -> String
buildModelFilterParams f = 
  let params = 
        [ (\p -> "provider=" <> p) <$> f.provider
        , (\s -> "search=" <> s) <$> f.search
        ]
      validParams = Array.catMaybes params
  in if Array.null validParams
       then ""
       else "?" <> joinWith "&" validParams
