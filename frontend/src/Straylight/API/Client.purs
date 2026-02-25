-- | API client for straylight-llm gateway
module Straylight.API.Client
  ( Config
  , defaultConfig
  , healthCheck
  , getModels
  , getProof
  , getRequests
  , getRequestDetail
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
  ) where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (class DecodeJson, decodeJson, JsonDecodeError(TypeMismatch, MissingValue, UnexpectedValue), printJsonDecodeError)
import Data.Argonaut.Decode.Decoders as Decoders
import Data.Argonaut.Core (toObject)
import Data.Array as Array
import Data.Either (Either(Left, Right))
import Data.Maybe (Maybe(Nothing, Just))
import Effect.Aff (Aff)
import Foreign.Object as Object


-- ════════════════════════════════════════════════════════════════════════════
--                                                                    // config
-- ════════════════════════════════════════════════════════════════════════════

type Config =
  { baseUrl :: String
  , port :: Int
  }

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
