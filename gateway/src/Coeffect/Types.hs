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
import Data.Aeson (ToJSON (..), FromJSON (..), object, (.=), (.:), (.:?), withObject)
import Data.ByteString (ByteString)
import Data.Text (Text)
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
    rnf NetworkAccess{..} =
        rnf naUrl `seq`
        rnf naMethod `seq`
        rnf naContentHash `seq`
        rnf naTimestamp

instance ToJSON NetworkAccess where
    toJSON NetworkAccess{..} = object
        [ "url" .= naUrl
        , "method" .= naMethod
        , "contentHash" .= naContentHash
        , "timestamp" .= naTimestamp
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
    parseJSON = withObject "FilesystemMode" $ \_ -> pure Read  -- Simplified

-- | Witness of filesystem access outside sandbox
data FilesystemAccess = FilesystemAccess
    { faPath :: Text
    , faMode :: FilesystemMode
    , faContentHash :: Maybe Hash   -- SHA256 if readable file
    , faTimestamp :: UTCTime
    }
    deriving stock (Eq, Show, Generic)

instance NFData FilesystemAccess where
    rnf FilesystemAccess{..} =
        rnf faPath `seq`
        rnf faMode `seq`
        rnf faContentHash `seq`
        rnf faTimestamp

instance ToJSON FilesystemAccess where
    toJSON FilesystemAccess{..} = object
        [ "path" .= faPath
        , "mode" .= faMode
        , "contentHash" .= faContentHash
        , "timestamp" .= faTimestamp
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
    rnf AuthUsage{..} =
        rnf auProvider `seq`
        rnf auScope `seq`
        rnf auTimestamp

instance ToJSON AuthUsage where
    toJSON AuthUsage{..} = object
        [ "provider" .= auProvider
        , "scope" .= auScope
        , "timestamp" .= auTimestamp
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
    toJSON (Hash bs) = toJSON (show bs)  -- Hex encode in practice

instance FromJSON Hash where
    parseJSON v = Hash . read <$> parseJSON v  -- Simplified

-- | Ed25519 public key (32 bytes)
newtype PublicKey = PublicKey { unPublicKey :: ByteString }
    deriving stock (Eq, Show, Generic)

instance NFData PublicKey where
    rnf (PublicKey bs) = rnf bs

instance ToJSON PublicKey where
    toJSON (PublicKey bs) = toJSON (show bs)

instance FromJSON PublicKey where
    parseJSON v = PublicKey . read <$> parseJSON v

-- | Ed25519 signature (64 bytes)
newtype Signature = Signature { unSignature :: ByteString }
    deriving stock (Eq, Show, Generic)

instance NFData Signature where
    rnf (Signature bs) = rnf bs

instance ToJSON Signature where
    toJSON (Signature bs) = toJSON (show bs)

instance FromJSON Signature where
    parseJSON v = Signature . read <$> parseJSON v


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
    rnf OutputHash{..} = rnf ohName `seq` rnf ohHash

instance ToJSON OutputHash where
    toJSON OutputHash{..} = object
        [ "name" .= ohName
        , "hash" .= ohHash
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
    rnf DischargeProof{..} =
        rnf dpCoeffects `seq`
        rnf dpNetworkAccess `seq`
        rnf dpFilesystemAccess `seq`
        rnf dpAuthUsage `seq`
        rnf dpBuildId `seq`
        rnf dpDerivationHash `seq`
        rnf dpOutputHashes `seq`
        rnf dpStartTime `seq`
        rnf dpEndTime `seq`
        rnf dpSignature

instance ToJSON DischargeProof where
    toJSON DischargeProof{..} = object
        [ "coeffects" .= dpCoeffects
        , "networkAccess" .= dpNetworkAccess
        , "filesystemAccess" .= dpFilesystemAccess
        , "authUsage" .= dpAuthUsage
        , "buildId" .= dpBuildId
        , "derivationHash" .= dpDerivationHash
        , "outputHashes" .= dpOutputHashes
        , "startTime" .= dpStartTime
        , "endTime" .= dpEndTime
        , "signature" .= fmap formatSig dpSignature
        ]
      where
        formatSig (pk, sig) = object ["publicKey" .= pk, "signature" .= sig]


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
