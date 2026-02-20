-- | API client for straylight-llm gateway
module Straylight.API.Client
  ( Config
  , defaultConfig
  , healthCheck
  , getModels
  , getProof
  , HealthResponse
  , Model
  , ModelList
  , DischargeProof
  , Coeffect(..)
  , NetworkAccess
  , FilesystemAccess
  , AuthUsage
  , OutputHash
  , SignatureInfo
  ) where

import Prelude

import Affjax.Web as AX
import Affjax.ResponseFormat as ResponseFormat
import Data.Argonaut (class DecodeJson, decodeJson, JsonDecodeError(..), printJsonDecodeError)
import Data.Argonaut.Decode.Decoders as Decoders
import Data.Argonaut.Core (toObject)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
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
