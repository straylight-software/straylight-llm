-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // straylight-llm // coeffect/types
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "A year here and he still dreamed of cyberspace, hope fading nightly."
--
--                                                              — Neuromancer
--
-- Coeffect types for tracking resource requirements. Mirrors the structure
-- defined in aleph-reference/dhall/DischargeProof.dhall and the Lean4
-- formalization in Continuity.lean.
--
-- Key types:
--   - Coeffect: what resources a computation may access
--   - NetworkAccess: witness of HTTP call (URL, method, content hash)
--   - FilesystemAccess: witness of file access (path, mode, hash)
--   - AuthUsage: witness of auth token usage (provider, scope)
--   - DischargeProof: complete evidence of coeffect satisfaction
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Coeffect.Types
    ( -- * Coeffect Types
      Coeffect (..)
    , combineCoeffects
    
      -- * Access Witnesses
    , NetworkAccess (..)
    , FilesystemAccess (..)
    , FilesystemMode (..)
    , AuthUsage (..)
    
      -- * Cryptographic Types
    , Hash (..)
    , PublicKey (..)
    , Signature (..)
    
      -- * Discharge Proof
    , DischargeProof (..)
    , OutputHash (..)
    
      -- * Predicates
    , isPure
    , isSigned
    , hasNetworkEvidence
    ) where

import Control.DeepSeq (NFData (rnf))
import Data.Aeson (ToJSON (..), FromJSON (..), object, (.=), (.:), (.:?), withObject, withText)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime)
import GHC.Generics (Generic)


-- ════════════════════════════════════════════════════════════════════════════
--                                                                // coeffect
-- ════════════════════════════════════════════════════════════════════════════

-- | Coeffect: what external resources a computation may access.
-- Matches Continuity.lean's Coeffect inductive type.
data Coeffect
    = Pure                        -- No external resources required
    | Network                     -- May access network
    | Auth Text                   -- May use auth for provider
    | Sandbox Text                -- May access sandbox at path
    | Filesystem Text             -- May access filesystem at path
    | Combined [Coeffect]         -- Multiple coeffects
    deriving stock (Eq, Show, Generic)

instance NFData Coeffect where
    rnf Pure = ()
    rnf Network = ()
    rnf (Auth t) = rnf t
    rnf (Sandbox t) = rnf t
    rnf (Filesystem t) = rnf t
    rnf (Combined cs) = rnf cs

instance ToJSON Coeffect where
    toJSON Pure = object ["type" .= ("pure" :: Text)]
    toJSON Network = object ["type" .= ("network" :: Text)]
    toJSON (Auth provider) = object ["type" .= ("auth" :: Text), "provider" .= provider]
    toJSON (Sandbox path) = object ["type" .= ("sandbox" :: Text), "path" .= path]
    toJSON (Filesystem path) = object ["type" .= ("filesystem" :: Text), "path" .= path]
    toJSON (Combined cs) = object ["type" .= ("combined" :: Text), "coeffects" .= cs]

instance FromJSON Coeffect where
    parseJSON = withObject "Coeffect" $ \o -> do
        ty <- o .: "type"
        case (ty :: Text) of
            "pure" -> pure Pure
            "network" -> pure Network
            "auth" -> Auth <$> o .: "provider"
            "sandbox" -> Sandbox <$> o .: "path"
            "filesystem" -> Filesystem <$> o .: "path"
            "combined" -> Combined <$> o .: "coeffects"
            _ -> fail $ "Unknown coeffect type: " ++ show ty

-- | Combine coeffects (monoid-like)
combineCoeffects :: Coeffect -> Coeffect -> Coeffect
combineCoeffects Pure c = c
combineCoeffects c Pure = c
combineCoeffects (Combined cs1) (Combined cs2) = Combined (cs1 ++ cs2)
combineCoeffects (Combined cs) c = Combined (cs ++ [c])
combineCoeffects c (Combined cs) = Combined (c : cs)
combineCoeffects c1 c2 = Combined [c1, c2]


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // access witnesses
-- ════════════════════════════════════════════════════════════════════════════

-- | Witness of network access. Recorded by TLS proxy.
-- The content hash allows replay verification.
data NetworkAccess = NetworkAccess
    { naUrl :: Text
    , naMethod :: Text              -- GET, POST, etc.
    , naContentHash :: Hash         -- SHA256 of response body
    , naTimestamp :: UTCTime
    }
    deriving stock (Eq, Show, Generic)

instance NFData NetworkAccess where
    rnf na =
        rnf (naUrl na) `seq`
        rnf (naMethod na) `seq`
        rnf (naContentHash na) `seq`
        rnf (naTimestamp na)

instance ToJSON NetworkAccess where
    toJSON na = object
        [ "url" .= naUrl na
        , "method" .= naMethod na
        , "contentHash" .= naContentHash na
        , "timestamp" .= naTimestamp na
        ]

instance FromJSON NetworkAccess where
    parseJSON = withObject "NetworkAccess" $ \o -> NetworkAccess
        <$> o .: "url"
        <*> o .: "method"
        <*> o .: "contentHash"
        <*> o .: "timestamp"

-- | Filesystem access mode
data FilesystemMode = Read | Write | Execute
    deriving stock (Eq, Show, Generic)

instance NFData FilesystemMode where
    rnf Read = ()
    rnf Write = ()
    rnf Execute = ()

instance ToJSON FilesystemMode where
    toJSON Read = "read"
    toJSON Write = "write"
    toJSON Execute = "execute"

instance FromJSON FilesystemMode where
    parseJSON = withText "FilesystemMode" $ \t ->
        case t of
            "read" -> pure Read
            "write" -> pure Write
            "execute" -> pure Execute
            _ -> fail $ "Unknown filesystem mode: " ++ show t

-- | Witness of filesystem access outside sandbox
data FilesystemAccess = FilesystemAccess
    { faPath :: Text
    , faMode :: FilesystemMode
    , faContentHash :: Maybe Hash   -- SHA256 if readable file
    , faTimestamp :: UTCTime
    }
    deriving stock (Eq, Show, Generic)

instance NFData FilesystemAccess where
    rnf fa =
        rnf (faPath fa) `seq`
        rnf (faMode fa) `seq`
        rnf (faContentHash fa) `seq`
        rnf (faTimestamp fa)

instance ToJSON FilesystemAccess where
    toJSON fa = object
        [ "path" .= faPath fa
        , "mode" .= faMode fa
        , "contentHash" .= faContentHash fa
        , "timestamp" .= faTimestamp fa
        ]

instance FromJSON FilesystemAccess where
    parseJSON = withObject "FilesystemAccess" $ \o -> FilesystemAccess
        <$> o .: "path"
        <*> o .: "mode"
        <*> o .:? "contentHash"
        <*> o .: "timestamp"

-- | Witness of auth token usage
-- Token value is NOT recorded (security), just metadata
data AuthUsage = AuthUsage
    { auProvider :: Text            -- e.g., "github", "openrouter"
    , auScope :: Maybe Text         -- what scope was used
    , auTimestamp :: UTCTime
    }
    deriving stock (Eq, Show, Generic)

instance NFData AuthUsage where
    rnf au =
        rnf (auProvider au) `seq`
        rnf (auScope au) `seq`
        rnf (auTimestamp au)

instance ToJSON AuthUsage where
    toJSON au = object
        [ "provider" .= auProvider au
        , "scope" .= auScope au
        , "timestamp" .= auTimestamp au
        ]

instance FromJSON AuthUsage where
    parseJSON = withObject "AuthUsage" $ \o -> AuthUsage
        <$> o .: "provider"
        <*> o .:? "scope"
        <*> o .: "timestamp"


-- ════════════════════════════════════════════════════════════════════════════
--                                                        // cryptographic types
-- ════════════════════════════════════════════════════════════════════════════

-- | SHA256 hash (32 bytes)
newtype Hash = Hash { unHash :: ByteString }
    deriving stock (Eq, Show, Generic)

instance NFData Hash where
    rnf (Hash bs) = rnf bs

instance ToJSON Hash where
    toJSON (Hash bs) = toJSON (TE.decodeUtf8 (Base16.encode bs))

instance FromJSON Hash where
    parseJSON = withText "Hash" $ \t ->
        case Base16.decode (TE.encodeUtf8 t) of
            Right bs -> pure (Hash bs)
            Left err -> fail $ "Invalid hex encoding for Hash: " ++ err

-- | Ed25519 public key (32 bytes)
newtype PublicKey = PublicKey { unPublicKey :: ByteString }
    deriving stock (Eq, Show, Generic)

instance NFData PublicKey where
    rnf (PublicKey bs) = rnf bs

instance ToJSON PublicKey where
    toJSON (PublicKey bs) = toJSON (TE.decodeUtf8 (Base16.encode bs))

instance FromJSON PublicKey where
    parseJSON = withText "PublicKey" $ \t ->
        case Base16.decode (TE.encodeUtf8 t) of
            Right bs -> pure (PublicKey bs)
            Left err -> fail $ "Invalid hex encoding for PublicKey: " ++ err

-- | Ed25519 signature (64 bytes)
newtype Signature = Signature { unSignature :: ByteString }
    deriving stock (Eq, Show, Generic)

instance NFData Signature where
    rnf (Signature bs) = rnf bs

instance ToJSON Signature where
    toJSON (Signature bs) = toJSON (TE.decodeUtf8 (Base16.encode bs))

instance FromJSON Signature where
    parseJSON = withText "Signature" $ \t ->
        case Base16.decode (TE.encodeUtf8 t) of
            Right bs -> pure (Signature bs)
            Left err -> fail $ "Invalid hex encoding for Signature: " ++ err


-- ════════════════════════════════════════════════════════════════════════════
--                                                          // discharge proof
-- ════════════════════════════════════════════════════════════════════════════

-- | Output hash record
data OutputHash = OutputHash
    { ohName :: Text
    , ohHash :: Hash
    }
    deriving stock (Eq, Show, Generic)

instance NFData OutputHash where
    rnf oh = rnf (ohName oh) `seq` rnf (ohHash oh)

instance ToJSON OutputHash where
    toJSON oh = object
        [ "name" .= ohName oh
        , "hash" .= ohHash oh
        ]

instance FromJSON OutputHash where
    parseJSON = withObject "OutputHash" $ \o -> OutputHash
        <$> o .: "name"
        <*> o .: "hash"

-- | Complete evidence that coeffects were satisfied during execution.
-- This is the key type for the aleph cube architecture — a DischargeProof
-- provides cryptographic evidence that a build/request accessed only the
-- resources it declared.
data DischargeProof = DischargeProof
    { -- | What coeffects were required
      dpCoeffects :: [Coeffect]
      
      -- | Evidence of network access (from witness proxy)
    , dpNetworkAccess :: [NetworkAccess]
    
      -- | Evidence of filesystem access (from sandbox hooks)
    , dpFilesystemAccess :: [FilesystemAccess]
    
      -- | Evidence of auth token usage
    , dpAuthUsage :: [AuthUsage]
    
      -- | Build/request metadata
    , dpBuildId :: Text                 -- unique identifier
    , dpDerivationHash :: Hash          -- content hash of inputs
    , dpOutputHashes :: [OutputHash]    -- hashes of outputs
    , dpStartTime :: UTCTime
    , dpEndTime :: UTCTime
    
      -- | Optional cryptographic signature
      -- Signs: sha256(derivationHash ++ outputHashes ++ evidence)
    , dpSignature :: Maybe (PublicKey, Signature)
    }
    deriving stock (Eq, Show, Generic)

instance NFData DischargeProof where
    rnf dp =
        rnf (dpCoeffects dp) `seq`
        rnf (dpNetworkAccess dp) `seq`
        rnf (dpFilesystemAccess dp) `seq`
        rnf (dpAuthUsage dp) `seq`
        rnf (dpBuildId dp) `seq`
        rnf (dpDerivationHash dp) `seq`
        rnf (dpOutputHashes dp) `seq`
        rnf (dpStartTime dp) `seq`
        rnf (dpEndTime dp) `seq`
        rnf (dpSignature dp)

instance ToJSON DischargeProof where
    toJSON dp = object
        [ "coeffects" .= dpCoeffects dp
        , "networkAccess" .= dpNetworkAccess dp
        , "filesystemAccess" .= dpFilesystemAccess dp
        , "authUsage" .= dpAuthUsage dp
        , "buildId" .= dpBuildId dp
        , "derivationHash" .= dpDerivationHash dp
        , "outputHashes" .= dpOutputHashes dp
        , "startTime" .= dpStartTime dp
        , "endTime" .= dpEndTime dp
        , "signature" .= fmap formatSig (dpSignature dp)
        ]
      where
        formatSig (pk, sig) = object ["publicKey" .= pk, "signature" .= sig]

instance FromJSON DischargeProof where
    parseJSON = withObject "DischargeProof" $ \o -> do
        coeffects <- o .: "coeffects"
        networkAccess <- o .: "networkAccess"
        filesystemAccess <- o .: "filesystemAccess"
        authUsage <- o .: "authUsage"
        buildId <- o .: "buildId"
        derivationHash <- o .: "derivationHash"
        outputHashes <- o .: "outputHashes"
        startTime <- o .: "startTime"
        endTime <- o .: "endTime"
        sigObj <- o .:? "signature"
        sig <- case sigObj of
            Nothing -> pure Nothing
            Just s -> withObject "Signature" (\so -> do
                pk <- so .: "publicKey"
                sg <- so .: "signature"
                pure $ Just (pk, sg)) s
        pure $ DischargeProof coeffects networkAccess filesystemAccess
                              authUsage buildId derivationHash outputHashes
                              startTime endTime sig


-- ════════════════════════════════════════════════════════════════════════════
--                                                               // predicates
-- ════════════════════════════════════════════════════════════════════════════

-- | Check if proof is for a pure computation (no external resources)
isPure :: DischargeProof -> Bool
isPure proof = all isPureCoeffect (dpCoeffects proof)
  where
    isPureCoeffect Pure = True
    isPureCoeffect (Combined cs) = all isPureCoeffect cs
    isPureCoeffect _ = False

-- | Check if proof is cryptographically signed
isSigned :: DischargeProof -> Bool
isSigned proof = case dpSignature proof of
    Just _ -> True
    Nothing -> False

-- | Check if proof has network access evidence
hasNetworkEvidence :: DischargeProof -> Bool
hasNetworkEvidence proof = not (null (dpNetworkAccess proof))
